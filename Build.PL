use 5.006;
use strict;
use warnings FATAL => 'all';
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'BVA::KALE',
    license             => 'artistic_2',
    dist_author         => q{Bruce W Van Allen <bva@cruzio.com>},
    dist_version_from   => 'lib/BVA/KALE.pm',
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'BVA::XUI'              => 3.6,
    },
    add_to_cleanup     => [ 'BVA-KALE-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
