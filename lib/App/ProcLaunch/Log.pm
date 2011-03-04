package App::ProcLaunch::Log;

use strict;
use warnings;

use base 'Exporter';
use vars qw/ @EXPORT_OK /;

use constant FATAL => 0;
use constant WARN  => 1;
use constant INFO  => 2;
use constant DEBUG => 3;

my $LOG_LEVEL = INFO;
my $LOG_TARGET = \*STDERR;

BEGIN {
    @EXPORT_OK = qw/
        set_log_level
        set_log_target
        log_fatal
        log_warn
        log_info
        log_debug
        log_level_number
        FATAL
        WARN
        INFO
        DEBUG
    /;
}

sub set_log_level
{
    $LOG_LEVEL = shift;
}

sub set_log_target
{
    $LOG_TARGET = shift;
}

sub log_line
{
    my ($level, $include_caller, $line, @args) = @_;

    die "Log level '$level' is not numeric!" unless $level =~ /^\d+$/;
    return unless $level <= $LOG_LEVEL;

    my $time = scalar localtime;
    my ($package, $filename, $caller_line, $sub) = caller 1;
    my $caller_info = $include_caller ? " at $filename line $caller_line" : "";

    my $logged_line = sprintf("%s %s ${line}${caller_info}\n", $time, _level_text($level), @args);
    print $LOG_TARGET $logged_line;
    return $logged_line
}

sub log_fatal
{
    die log_line(FATAL, 1, @_);
}

sub log_warn
{
    log_line(WARN, 1, @_);
}

sub log_info
{
    log_line(INFO, 0, @_);
}

sub log_debug
{
    log_line(DEBUG, 1, @_);
}

sub _level_text
{
    return ['FATAL', 'WARN ', 'INFO ', 'DEBUG']->[shift];

}

sub log_level_number
{
    return {
        'fatal' => FATAL,
        'warn'  => WARN,
        'info'  => INFO,
        'debug' => DEBUG,
    }->{lc shift};
}

1;
