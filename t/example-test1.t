use lib '.';
use t::Helper;
use File::Spec::Functions qw(catfile rel2abs);

my $app    = do(rel2abs(catfile(qw(example test1.pl))));
my $script = $app->_script;

isa_ok($script, 'Applify');
can_ok($app, qw(input_file output_dir dry_run generate_exit_value));

run_method($app, 'run');
is($@, "Required attribute missing: --dry-run\n", '--dry-run missing');

is($app->dry_run, undef, '--dry-run is not set');
$app->dry_run(1);
is($app->dry_run, 1, '--dry-run was set');

$app->dry_run(0);
is($app->dry_run, 0, '--no-dry-run was set');
my ($stdout, $stderr, $retval) = run_method $app, 'run';
like $stdout, qr/will/im, 'output includes will';
is $stderr, '', 'empty stderr';
ok $retval >= 0 and $retval <= 100, 'random number between 0 and 100';

done_testing;
