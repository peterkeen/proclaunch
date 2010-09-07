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

use Class::Struct
    directory => '$',
    dir_stat  => '$',
    _pid_file => '$',
;

sub run
{
    my $self = shift;

    return unless cleanup_dead_pid_file($self->pid_file());
    log_info "Starting profile " . $self->directory();

    defined(my $pid = fork()) or log_fatal "Could not fork: $!";

    if ($pid == 0) {
        $self->drop_privs();
        chdir $self->directory();
        exec("./run");
    } else {
        waitpid($pid, 0);
    }
}

sub drop_privs
{
    my $self = shift;

    return unless -e $self->profile_file('user');

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

    my $restart_time = time();
    my $seconds_to_wait = 7;

    try {
        my $seconds_to_wait = $self->profile_setting('wait_for_stop');
    } catch { }

    my $wait_until = $restart_time + $seconds_to_wait;

    log_info "Stopping profile " . $self->directory();
    $self->send_signal(15);
    log_debug "Waiting for pid " . $self->current_pid() . " to stop";

    while(time() <= $wait_until) {
        return unless $self->is_running();
        sleep 1;
    }

    log_warn $self->directory() . " did not respond to TERM.";
}

sub has_changed
{
    my $self = shift;
    my $stat = stat_hash($self->directory());

    return diff_stats($stat, $self->dir_stat());
}

1;
