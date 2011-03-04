package App::ProcLaunch::Util;

use strict;
use warnings;

use base 'Exporter';
use vars qw/ @EXPORT_OK /;
use IO::File;
use POSIX qw/ setsid :signal_h /;

use App::ProcLaunch::Log qw/
    log_warn
    log_debug
    log_fatal
/;

use Carp;

use File::Slurp qw/ read_file write_file /;

BEGIN {
    @EXPORT_OK = qw/
        still_running
        cleanup_dead_pid_file
        redirect_output
        read_file
        read_pid_file
        write_file
        write_pid_file
        daemonize
        stat_hash
        diff_stats
        signal_name_to_num
    /;
}

sub still_running
{
    my $pidfile = shift;
    my $pid = read_pid_file($pidfile);
    unless (defined($pid)) {
        return 0;
    }

    my $num_killed = kill(0, $pid);
    my $error = "$!";

    if ($num_killed == 0 && $error =~ /Operation not permitted/) {
        return 1;
    }

    return $num_killed;
}

sub read_pid_file
{
    my $filename = shift;
    return undef unless -e $filename;
    my $pid = read_file($filename);
    $pid =~ s/\s//g;
    return undef unless $pid =~ /^\d+$/;
    return $pid;
}

sub write_pid_file
{
    my ($filename, $pid) = @_;
    die "'$pid' does not look like a pid" unless $pid =~ /^\d+$/;
    write_file($filename, $pid);
}

sub redirect_output
{
    my ($filename) = @_;

    return unless $filename;

    open(FH, ">>", $filename) or die "Cannot open $filename: $!";
    FH->autoflush(1);

    *STDOUT = *FH;
    *STDERR = *FH;
    close STDIN;
}

sub cleanup_dead_pid_file
{
    my $filename = shift;
    unless (still_running($filename)) {
        unlink $filename;
        return 1;
    }
    return 0;
}

sub daemonize
{
    my $output_file = shift;
    defined(my $pid = fork()) or die "Could not fork: $!";
    exit if $pid;
    setsid()                  or die "Could not setsid: $!";
    defined($pid = fork())    or die "Could not fork: $!";
    exit if $pid;
    redirect_output($output_file);
}

sub stat_hash
{
    my $filename = shift;

    my @elements = qw/
        device
        inode
        mode
        nlink
        uid
        gid
        rdev
        size
        atime
        mtime
        ctime
        blksize
        blocks
    /;

    my @stat = stat($filename);
    return { map { $elements[$_] => $stat[$_] } (0 .. $#stat) };
}

sub diff_stats
{
    my ($a, $b) = @_;
    log_fatal "need two things to diff!" unless $a && $b;

    return 1 if $a->{inode}  != $b->{inode}
             || $a->{mtime}  != $b->{mtime}
             || $a->{device} != $b->{device}
    ;
    return 0;
}

sub signal_name_to_num
{
    my ($signal_name) = @_;

    return {
        SIGHUP    => SIGHUP,
        SIGHUP    => SIGHUP,
        SIGINT    => SIGINT,
        SIGQUIT   => SIGQUIT,
        SIGABRT   => SIGABRT,
        SIGTERM   => SIGTERM,
        SIGCONT   => SIGCONT,
        SIGUSR1   => SIGUSR1,
        SIGUSR2   => SIGUSR2,
    }->{$signal_name};
}

1;
