package App::ProcLaunch;

use strict;
use warnings;
use App::ProcLaunch::Util qw/
    cleanup_dead_pid_file
    daemonize
    redirect_output
    write_pid_file
    stat_hash
    diff_stats
/;

use App::ProcLaunch::Log qw/
    set_log_level
    log_info
    log_debug
    DEBUG
    INFO
/;

use App::ProcLaunch::Profile;
use File::Slurp qw/ read_file write_file /;

use constant RESCAN_EVERY_SECONDS => 5;

use Class::Struct
    state_dir         => '$',
    profiles_dir      => '$',
    dir_stat          => '$',
    foreground        => '$',
    debug             => '$',
;


sub run
{
    my $self = shift;
    unless(cleanup_dead_pid_file($self->pidfile())) {
        exit 0;
    }

    my $profiles_dir = $self->profiles_dir();
    set_log_level($self->debug() ? DEBUG : INFO);

    unless($self->foreground()) {
        daemonize("$profiles_dir/error.log");
        write_pid_file($self->pidfile(), $$);
    }

    log_info "Started pid $$";

    log_debug "Getting stat for $profiles_dir";
    $self->dir_stat(stat_hash($profiles_dir));

    log_debug "Changing to $profiles_dir";
    chdir $profiles_dir;

    log_info "Scanning profiles";
    my @profiles = $self->scan_profiles();
    $_->run() for @profiles;

    $SIG{HUP} = sub {
        log_info "Received HUP. Sending TERM to all profiles.";
        for my $profile ( @profiles ) {
            $profile->send_signal(15);
        }
        log_info "Exiting";
        exit 111;
    };

    $SIG{TERM} = sub {
        log_info "Exiting";
        exit 0;
    };

    my $last_rescan_time = time();

    while(1) {

        if (my $reason = $self->should_rescan($last_rescan_time)) {
            log_debug "Rescanning profiles";

            my %old_profiles = map { $_->directory() => $_ } @profiles;
            @profiles = $self->scan_profiles();
            my %new_profiles = map { $_->directory() => $_ } @profiles;

            for my $dir ( sort keys %old_profiles ) {
                if (!defined($new_profiles{$dir}) || $old_profiles{$dir}->has_changed()) {
                    $old_profiles{$dir}->stop();
                }
            }

            $self->dir_stat(stat_hash($self->profiles_dir()));
            $last_rescan_time = time();
        }

        for my $profile ( @profiles ) {

            next if $profile->is_running();
            next unless $profile->should_restart();

            $profile->run();
            log_fatal $profile->directory() . " did not create pid_file " . $profile->pid_file()
                unless $profile->pid_file_exists();
        }
        sleep 1;
    }
}

sub scan_profiles
{
    my $self = shift;
    my @potentials = glob('*');
    return map {
        log_debug "creating profile for $_";

        App::ProcLaunch::Profile->new(
            directory => $_,
            dir_stat  => stat_hash($_)
        )
    } grep {
        -d $_
    } grep {
        $_ ne '.' && $_ ne '..'
    } @potentials;
}

sub should_rescan
{
    my ($self, $last_rescan_time) = @_;
    return 1 if (time() - $last_rescan_time) >= RESCAN_EVERY_SECONDS;

    my $stat = stat_hash($self->profiles_dir());

    if (diff_stats($stat, $self->dir_stat())) {
        log_info "Profiles dir changed. Rescanning.";
        return 1;
    }

    return 0;
}

sub pidfile
{
    my $self = shift;
    return $self->state_dir() . "/proclaunch.pid";
}

1;
