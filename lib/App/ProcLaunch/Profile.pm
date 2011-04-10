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
    signal_name_to_num
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

use constant KNOWN_FILES => [ qw/ run pid_file user restart reload / ];

use Class::Struct
    directory     => '$',
    disappeared   => '$',
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
        if ($self->is_running()) {
            $self->_status(STATUS_RUNNING);
        } else {
            $self->_status(STATUS_STOPPED);
        }

        $self->_should_start(1);
        $self->disappeared(0);
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
    if ($self->_should_start() && ! $self->disappeared()) {
        $self->start();
    }
}

sub start
{
    my ($self) = @_;

    log_info "%s starting", $self->directory();

    defined(my $pid = fork()) or log_fatal "ProcLaunch could not fork: $!";

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
        log_info "%s running pid %s", $self->directory(), $self->current_pid();
    }
}

sub stop_if_should_stop
{
    my ($self) = @_;

    if (!$self->is_running()) {
        log_info("%s died", $self->directory());
        $self->_status(STATUS_STOPPED);
    } elsif ($self->has_changed()) {
        if ($self->should_reload()) {
            $self->reload();
        } else {
            $self->stop();
        }
    }

    $self->_should_start($self->should_restart());
    $self->_refresh_file_stats();
}


sub check_if_stopped
{
    my ($self) = @_;

    if ($self->is_running()) {
        log_debug("%s still running on pid %s", $self->directory(), $self->current_pid());
    } else {
        log_info("%s stopped", $self->directory());
        $self->set_status_stopped_and_clean_pid_file();
    }
}

sub set_status_stopped_and_clean_pid_file
{
    my ($self) = @_;

    $self->_status(STATUS_STOPPED);

    log_debug("%s removing dead pid file", $self->directory());
    cleanup_dead_pid_file($self->pid_file());
}

sub drop_privs
{
    my $self = shift;

    return unless -e $self->profile_file('user');

    log_debug("ProcLaunch current UID: $UID");
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
        log_fatal("ProcLaunch could not drop privileges to uid:$uid, gid:$gid");
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

sub is_stopped
{
    my $self = shift;

    return $self->_status() == STATUS_STOPPED;
}

sub should_restart
{
    my $self = shift;

    return -e $self->profile_file('restart');
}

sub should_reload
{
    my $self = shift;

    return -e $self->profile_file('reload');
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

    log_fatal("%s no file named %s", $self->directory(), $setting)
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
    my $pid = $self->current_pid();

    $signal =~ s/\s//g;

    log_debug "%s sending %s to %s", $self->directory(), $signal, $self->current_pid();

    if ($signal !~ /^\d+/) {
        $signal = signal_name_to_num($signal);
    }

    unless (kill $signal, $pid) {
        log_debug "%s not able to send signal! Assuming profile dead.", $self->directory();
        $self->set_status_stopped_and_clean_pid_file();
    }
}

sub stop
{
    my ($self) = @_;

    unless ($self->is_running()) {
        log_warn "%s is not running! Should be running on pid %s", $self->directory(), $self->current_pid();
        return;
    }

    log_info "%s stopping", $self->directory();

    my $signal = -e $self->profile_file('stop_signal') ? $self->profile_setting('stop_signal') : 'SIGTERM';

    $self->send_signal($signal);

    $self->_status(STATUS_STOPPING);
}

sub reload
{
    my $self = shift;

    unless ($self->is_running()) {
        log_warn "%s is not running! Should be running on pid %s", $self->directory(), $self->current_pid();
        return;
    }

    log_info "%s reloading", $self->directory();

    $self->send_signal($self->profile_setting('reload') || 'SIGHUP');
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
