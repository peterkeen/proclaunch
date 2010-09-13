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

BEGIN {
    @EXPORT_OK = qw/
        set_log_level
        log_fatal
        log_warn
        log_info
        log_debug
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

sub log_line
{
    my ($level, $include_caller, $line, @args) = @_;
    return unless $level <= $LOG_LEVEL;

    my $time = scalar localtime;
    my ($package, $filename, $caller_line, $sub) = caller 1;
    my $caller_info = $include_caller ? " at $filename line $caller_line" : "";

    print STDERR sprintf("%s %s ${line}${caller_info}\n", $time, _level_text($level), @args);
}

sub log_fatal
{
    log_line(FATAL, 1, @_);
    die @_;
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

1;
