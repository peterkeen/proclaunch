package App::ProcLaunch;

our $VERSION = 1.1;

use strict;
use warnings;

use App::ProcLaunch::Profile;

use App::ProcLaunch::Util qw/
    cleanup_dead_pid_file
    daemonize
    redirect_output
    write_pid_file
/;

use App::ProcLaunch::Log qw/
    set_log_level
    log_info
    log_debug
    log_fatal
    log_warn
    log_level_number
/;

use File::Slurp qw/
    read_file write_file
/;

use constant RESCAN_EVERY_SECONDS => 1;

use Class::Struct
    state_dir         => '$',
    profiles_dir      => '$',
    foreground        => '$',
    log_level         => '$',
    log_path          => '$',
    _profiles         => '%',
    _last_scan_time   => '$',
;

sub foreach_profile
{
    my ($self, $code) = @_;
    for my $name ( keys %{ $self->_profiles } ) {
        $code->($self->_profiles($name));
    }
}

sub run
{
    my $self = shift;
    $self->_profiles({});
    $self->_last_scan_time(0);

    unless(cleanup_dead_pid_file($self->pidfile())) {
        exit 0;
    }

    my $profiles_dir = $self->profiles_dir();
    my $log_level = log_level_number($self->log_level());
    set_log_level($log_level);

    unless ($self->foreground()) {
        daemonize($self->log_path());
        write_pid_file($self->pidfile(), $$);
    }

    log_info "ProcLaunch started pid $$";

    log_debug "ProcLaunch changing to $profiles_dir";
    chdir $profiles_dir;

    $SIG{HUP} = sub {
        log_info "ProcLaunch received HUP. Stopping all profiles.";
        $self->foreach_profile(sub { shift->stop() });

        log_info "ProcLaunch exiting";
        exit 111;
    };

    $SIG{TERM} = sub {
        log_info "ProcLaunch exiting";
        exit 0;
    };

    while(1) {

        $self->scan_profiles();

        $self->foreach_profile(sub { shift->run(); });

        sleep 1;
    }
}

sub scan_profiles
{
    my $self = shift;

    for my $dir ( keys %{ $self->_profiles() } ) {
        my $profile = $self->_profiles()->{$dir};

        if (! -e $dir && ! $profile->disappeared()) {
            log_info "%s disappeared. Stopping and not restarting.", $dir;
            $profile->stop();
            $profile->disappeared(1);
        }

        if ($profile->disappeared() && ! $profile->is_running()) {
            log_debug "%s deleting", $dir;
            delete $self->_profiles()->{$dir};
        }
    }

    return unless $self->_should_scan();

    my @potentials = glob('*');

    for my $profile ( @potentials ) {
        next if $profile eq '.' || $profile eq '..';
        next unless -d $profile;

        unless ($self->_profiles($profile)) {
            log_debug "ProcLaunch creating profile for $profile";
            my $p = App::ProcLaunch::Profile->new(
                directory => $profile,
            );

            $self->_profiles($profile, $p);
        }
    }

    $self->_last_scan_time(time());
}

sub _should_scan
{
    my ($self) = @_;
    return 1 if (time() - $self->_last_scan_time()) >= RESCAN_EVERY_SECONDS;
    return 0;
}

sub pidfile
{
    my $self = shift;
    return $self->state_dir() . "/proclaunch.pid";
}

1;
