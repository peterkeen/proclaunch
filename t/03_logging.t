use Test::More tests => 2;

BEGIN {
    use_ok('App::ProcLaunch::Log', qw/
        log_level_number
        FATAL
    /);
}

is(log_level_number('fatal'), FATAL);

