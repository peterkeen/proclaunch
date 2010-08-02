package App::ProcLaunch;

use strict;
use App::ProcLaunch::Util qw/
    cleanup_dead_pid_file
    daemonize
    redirect_output
    write_pid_file
/;

use App::ProcLaunch::Profile;
use Cwd qw/ abs_path cwd /;
use File::Stat qw/ stat /;;

use Class::Struct
    pidfile      => '$',
    profiles_dir => '$',
    dir_stat     => '$',
;

sub run
{
    my $self = shift;
    unless(cleanup_dead_pid_file($self->pidfile())) {
        die "already running stop that";
    }

    my $profiles_dir = $self->profiles_dir();
    warn "Starting for profiles_dir = $profiles_dir";

    redirect_output("$profiles_dir/error.log");
    daemonize();
    write_pid_file($self->pidfile(), $$);

    chdir $profiles_dir;

    my $stat = stat(cwd('.'));
    $self->dir_stat($stat);

    my @profiles = $self->scan_profiles();
    $_->run() for @profiles;

    $SIG{HUP} = sub {
        warn "Received HUP. Sending TERM to all profiles and exiting.";
        for my $profile ( @profiles ) {
            $profile->send_signal(15);
        }
        exit 111;
    };

    while(1) {
        for my $profile ( @profiles ) {
            next if $profile->is_running();
            next unless $profile->should_restart();

            if ($profile->has_changed()) {
                warn "Restarting " . $profile->directory();
                $profile->send_signal(15);
                waitpid($profile->current_pid(), 0);
            }

            $profile->run();
            die $profile->directory() . " did not create pid_file " . $profile->pid_file()
                unless $profile->pid_file_exists();
        }
        sleep 1;
    }
}

sub scan_profiles
{
    my $self = shift;
    my @potentials = glob('*');
    return map { warn "creating profile for $_"; App::ProcLaunch::Profile->new(directory => $_) }
           grep { -d $_ }
           grep { $_ ne '.' && $_ ne '..' }
           @potentials;
}

1;
