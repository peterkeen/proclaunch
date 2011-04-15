use Test::More tests => 3;

use POSIX;
use App::ProcLaunch;
use App::ProcLaunch::Util qw/ read_pid_file /;

use File::Temp qw/ tempdir /;
use File::Slurp qw/ read_file write_file /;
use File::Spec::Functions qw/ catfile /;
use File::Basename qw/ dirname /;

my $profiles_dir = tempdir();
my $state_dir = tempdir();

mkdir catfile($profiles_dir, 'test_profile');

write_file(catfile($profiles_dir, 'test_profile', 'run'), <<HERE);
#!/bin/sh

nohup bash -c 'while true; do sleep 1; done' </dev/null &> $profiles_dir/sleeper.log &
echo \$! > $profiles_dir/sleeper.pid

HERE

system("chmod +x $profiles_dir/test_profile/run");

write_file(catfile($profiles_dir, 'test_profile', 'restart'), "1");
write_file(catfile($profiles_dir, 'test_profile', 'pid_file'), "$profiles_dir/sleeper.pid");

my $dir = dirname(__FILE__);
my $log_file = catfile($state_dir, "test_run.log");
system("$dir/../bin/proclaunch --log-path=$log_file $state_dir $profiles_dir") == 0 or die "something bad happened: $?";

sleep 2;

my $sleeper_pid = read_pid_file(catfile($profiles_dir, 'sleeper.pid'));
ok($sleeper_pid, "sleeper pid exists");

my $proc_pid = read_pid_file(catfile($state_dir, 'proclaunch.pid'));
ok($proc_pid, "proc pid exists");
kill SIGHUP, $proc_pid;

sleep 3;

my @lines = read_file($log_file);
chomp @lines;

my $log = "\n" . join("\n",  map { my $l = substr($_, 25); $l =~ s/pid \d+/pid PID/g; $l } @lines) . "\n";

is($log, <<HERE);

INFO  ProcLaunch started pid PID
INFO  test_profile starting
INFO  test_profile running pid PID
INFO  ProcLaunch received HUP. Stopping all profiles.
INFO  test_profile stopping
INFO  test_profile stopped
INFO  ProcLaunch all profiles stopped. Exiting.
HERE


unlink $profile_dir;
unlink $state_dir;
