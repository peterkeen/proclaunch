package App::ProcLaunch::Profile;

use strict;
use warnings;

use POSIX qw/ :sys_wait_h /;
use English '-no_match_vars';

use App::ProcLaunch::Util qw/
    read_file
    read_pid_file
    still_running
    cleanup_dead_pid_file
    diff_stats
    stat_hash
/;

use App::ProcLaunch::Log qw/
    log_info
    log_warn
    log_debug
    log_fatal
/;

use constant STATUS_STOPPED  => 1;
use constant STATUS_STARTING => 2;
use constant STATUS_RUNNING  => 3;
use constant STATUS_STOPPING => 4;

use constant KNOWN_FILES => [ qw/ run pid_file user restart / ];

use Class::Struct
    directory     => '$',
    _pid_file     => '$',
    _status       => '$',
    _should_start => '$',
    _file_stats   => '%',
;

sub run
{
    my $self = shift;

    # Class::Struct doesn't give us an init() so we have to do this here
    unless ($self->_status()) {
        $self->_status(STATUS_STOPPED);
        $self->_should_start(1);
        $self->_refresh_file_stats();
    }

    my $behavior = {
        STATUS_STOPPED()  => \&start_if_should_start,
        STATUS_STARTING() => \&check_if_running,
        STATUS_RUNNING()  => \&stop_if_should_stop,
        STATUS_STOPPING() => \&check_if_stopped,
    };

    $behavior->{$self->_status()}->($self);
}

sub start_if_should_start
{
    my ($self) = @_;
    if ($self->_should_start()) {
        $self->start();
    }
}

sub start
{
    my ($self) = @_;

    log_info "Starting profile " . $self->directory();

    defined(my $pid = fork()) or log_fatal "Could not fork: $!";

    if ($pid == 0) {
        $self->drop_privs();
        chdir $self->directory();
        exec("./run 2>&1 >> ../run.log");
    } else {
        waitpid($pid, WNOHANG);
    }

    $self->_status(STATUS_STARTING);
}

sub check_if_running
{
    my ($self) = @_;

    if ($self->is_running()) {
        $self->_status(STATUS_RUNNING);
        log_info "Profile " . $self->directory() . " running pid " . $self->current_pid();
    }
}

sub stop_if_should_stop
{
    my ($self) = @_;

    if ($self->has_changed()) {
        $self->stop();
        $self->_status(STATUS_STOPPING);
        $self->_should_start($self->should_restart());
    }

    $self->_refresh_file_stats();
}

sub check_if_stopped
{
    my ($self) = @_;

    if ($self->is_running()) {
        log_debug("Profile %s still running on pid %s", $self->directory(), $self->current_pid());
    } else {
        log_info("Profile %s stopped", $self->directory());
        $self->_status(STATUS_STOPPED);
    }
}

sub drop_privs
{
    my $self = shift;

    return unless -e $self->profile_file('user');

    log_debug("Current UID: $UID");
    return unless $UID == 0;

    my $user = $self->profile_setting('user');
    chomp $user;

    my ($uid, $gid, $home, $shell) = (getpwnam($user))[2,3,7,8];

    $ENV{USER} = $user;
    $ENV{LOGNAME} = $user;
    $ENV{HOME} = $home;
    $ENV{SHELL} = $shell;

    $GID = $EGID = $gid;
    $UID = $EUID = $uid;

    my %GIDHash = map { $_ => 1 } ($gid, split(/\s/, $GID));
    my %EGIDHash = map { $_ => 1 } ($gid, split(/\s/, $EGID));

    if (
        $UID ne $uid
        or $EUID ne $uid
        or !defined($GIDHash{$gid})
        or !defined($EGIDHash{$gid})
    ) {
        log_fatal("Could not drop privileges to uid:$uid, gid:$gid");
    }
}

sub pid_file_exists
{
    my $self = shift;

    return -e $self->pid_file();
}

sub current_pid
{
    my $self = shift;

    return read_pid_file($self->pid_file());
}

sub is_running
{
    my $self = shift;

    return still_running($self->pid_file());
}

sub should_restart
{
    my $self = shift;

    return -e $self->profile_file('restart');
}

sub profile_file
{
    my ($self, $filename) = @_;

    return join("/", $self->directory(), $filename);
}

sub profile_setting
{
    my ($self, $setting) = @_;

    my $setting_file = $self->profile_file($setting);

    die "No file named $setting for profile " . $self->directory()
        unless -e $setting_file;

    return read_file($setting_file);
}

sub pid_file
{
    my $self = shift;

    unless ($self->_pid_file()) {
        my $pid_file = $self->profile_setting('pid_file');
        $pid_file =~ s/\s*$//;
        $self->_pid_file($pid_file);
    }

    return $self->_pid_file();
}

sub send_signal
{
    my ($self, $signal) = @_;
    log_debug "Sending $signal to " . $self->current_pid();
    kill $signal, $self->current_pid();
}

sub stop
{
    my ($self) = @_;

    unless ($self->is_running()) {
        log_warn $self->directory() . " is not running! Thought pid was: " . $self->current_pid();
        return;
    }

    log_info "Stopping profile " . $self->directory();
    $self->send_signal(15);
}

sub has_changed
{
    my $self = shift;

    for my $file ( @{ KNOWN_FILES() } ) {
        if (-e $self->profile_file($file)) {
            my $stat = stat_hash($self->profile_file($file));
            if ($self->_file_stats($file) && diff_stats($stat, $self->_file_stats($file))) {
                return 1;
            }
        }
    }

    return 0;
}

sub _refresh_file_stats
{
    my $self = shift;

    for my $file ( @{ KNOWN_FILES() } ) {
        if (-e $self->profile_file($file)) {
            $self->_file_stats($file, stat_hash($self->profile_file($file)));
        }
    }
}

1;
