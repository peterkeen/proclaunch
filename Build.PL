use Module::Build;

Module::Build->new(
    module_name => 'Calorific',
    license => 'perl',
    dist_author => 'Pete Keen <pete@bugsplat.info>',
    license => 'perl',
    dist_abstract => 'A command-line application for tracking nutrients',
    requires => {
        'File::Slurp'               => '9999.13',
    }
)->create_build_script();
