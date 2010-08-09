use Module::Build;

Module::Build->new(
    module_name => 'App::ProcLaunch',
    dist_author => 'Pete Keen <pete@bugsplat.info>',
    license => 'perl',
    dist_abstract => 'A small user-space process manager',
    requires => {
        'File::Slurp' => '9999.13',
    }
)->create_build_script();
