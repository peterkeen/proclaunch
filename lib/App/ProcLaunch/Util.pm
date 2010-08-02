package App::ProcLaunch::Util;

use strict;
use base 'Exporter';
use vars qw/ @EXPORT_OK /;
use IO::File;
use POSIX qw/ setsid /;

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
    /;
}

sub still_running
{
    my $pidfile = shift;
    my $pid = read_pid_file($pidfile);
    return 0 unless defined($pid);
    return kill(0, $pid);
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
    my ($filename, $append) = @_;
    my $mode = $append ? '>>' : '>';
    open(FH, $mode, $filename) or die "Cannot open $filename: $!";

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
    defined(my $pid = fork()) or die "Could not fork: $!";
    exit if $pid;
    setsid()                  or die "Could not setsid: $!";
    defined($pid = fork())    or die "Could not fork: $!";
    exit if $pid;
}

1;
