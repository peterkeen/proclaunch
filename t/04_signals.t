use Test::More tests => 3;

use POSIX;
use App::ProcLaunch;
use App::ProcLaunch::Util qw/ read_pid_file /;

use File::Temp qw/ tempdir /;
use File::Slurp qw/ read_file write_file /;
use File::Spec::Functions qw/ catfile /;
use File::Basename qw/ dirname /;
use Cwd qw/ abs_path /;

my $profiles_dir = tempdir();
my $state_dir = tempdir();

mkdir catfile($profiles_dir, 'test_profile');

my $libdir = abs_path(dirname(__FILE__) . "/../lib");

write_file(catfile($profiles_dir, 'test_profile', 'run'), <<HERE);
#!/usr/bin/env perl

use lib '$libdir';
use App::ProcLaunch::Util qw/ write_pid_file daemonize /;

\$SIG{TERM} = sub {
    sleep 10;
};

\$SIG{USR2} = sub {
    exit 0;
};

daemonize();
write_pid_file("$profiles_dir/sleeper.pid", \$\$);

while (1) {
    sleep 10;
}

HERE

system("chmod +x $profiles_dir/test_profile/run");

write_file(catfile($profiles_dir, 'test_profile', 'restart'), "1");
write_file(catfile($profiles_dir, 'test_profile', 'pid_file'), "$profiles_dir/sleeper.pid");

my $dir = dirname(__FILE__);
system("$dir/../bin/proclaunch $state_dir $profiles_dir") == 0 or die "something bad happened: $?";

sleep 2;

my $sleeper_pid = read_pid_file(catfile($profiles_dir, 'sleeper.pid'));
ok($sleeper_pid, "sleeper pid exists");

my $proc_pid = read_pid_file(catfile($state_dir, 'proclaunch.pid'));
ok($proc_pid, "proc pid exists");
kill SIGHUP, $proc_pid;

sleep 3;

kill SIGHUP, $proc_pid;
kill SIGUSR2, $sleeper_pid;

my @lines = read_file(catfile($profiles_dir, 'error.log'));
chomp @lines;

my $log = "\n" . join("\n",  map { my $l = substr($_, 25); $l =~ s/pid \d+/pid PID/g; $l } @lines) . "\n";

is($log, <<HERE);

INFO  ProcLaunch started pid PID
INFO  test_profile starting
INFO  test_profile running pid PID
INFO  ProcLaunch received HUP. Stopping all profiles.
INFO  test_profile stopping
INFO  ProcLaunch received HUP again. Exiting immediately.
HERE


# unlink $profile_dir;
# unlink $state_dir;
