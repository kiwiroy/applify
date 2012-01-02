use warnings;
use strict;
use lib qw(lib);
use Test::More;
use Applify ();

plan tests => 38;

{
    my $app = eval q[use Applify; app {}] or BAIL_OUT $@;
    my $script = $app->script;

    isa_ok($script, 'Applify');
    can_ok($script, qw/
        option app documentation version
        caller options
        new print_help import
    /);

    is($script->caller->[0], 'main', 'called from main::');
    isa_ok($script->_option_parser, 'Getopt::Long::Parser');

    {
        local $TODO = 'need to define config for Getopt::Long';
        is_deeply($script->_option_parser->{'settings'}, [qw/ no_auto_help pass_through /], 'Getopt::Long has correct config');
    }

    eval { $script->option(undef) };
    like($@, qr{^Usage:.*type =>}, 'option() require type');
    eval { $script->option(str => undef) };
    like($@, qr{^Usage:.*name =>}, 'option() require name');
    eval { $script->option(str => foo => undef) };
    like($@, qr{^Usage:.*documentation}, 'option() require documentation');

    $script->option(str => foo_bar => 'Foo can something');
    is_deeply($script->options, [
        {
            default => undef,
            type => 'str',
            name => 'foo_bar',
            documentation => 'Foo can something',
        }
    ], 'add foo as option');

    $script->option(str => foo_2 => 'foo_2 can something else', 42);
    is($script->options->[1]{'default'}, 42, 'foo_2 has default value');

    $script->option(str => foo_3 => 'foo_3 can also something', 123, required => 1);
    is($script->options->[2]{'default'}, 123, 'foo_3 has default value');
    is($script->options->[2]{'required'}, 1, 'foo_3 is required');

    is($script->_calculate_option_spec({ name => 'a_b', type => 'bool' }), 'a-b!', 'a_b!');
    is($script->_calculate_option_spec({ name => 'a_b', type => 'flag' }), 'a-b!', 'a_b!');
    is($script->_calculate_option_spec({ name => 'a_b', type => 'inc' }), 'a-b+', 'a_b+');
    is($script->_calculate_option_spec({ name => 'a_b', type => 'str' }), 'a-b=s', 'a_b=s');
    is($script->_calculate_option_spec({ name => 'a_b', type => 'int' }), 'a-b=i', 'a_b=i');
    is($script->_calculate_option_spec({ name => 'a_b', type => 'num' }), 'a-b=f', 'a_b=f');

    {
        local $TODO = 'Add proper support for file/dir';
        is($script->_calculate_option_spec({ name => 'a_b', type => 'file' }), 'a-b=s', 'a_b=s');
        is($script->_calculate_option_spec({ name => 'a_b', type => 'dir' }), 'a-b=s', 'a_b=s');
    }

    my $application_class = $script->_generate_application_class(sub{});
    like($application_class, qr{^Applify::__ANON__2__::}, 'generated application class');
    can_ok($application_class, qw/
        new run script
        foo_bar foo_2 foo_3
    /);

    is_deeply([$script->_default_options], [qw/ help /], 'default options');
    is((run_method($script, 'print_help'))[0], <<'    HELP', 'print_help()');
Usage:
   --foo-bar  Foo can something
   --foo-2    foo_2 can something else
 * --foo-3    foo_3 can also something

   --help     Print this help text

    HELP

    eval { $script->documentation(undef) };
    like($@, qr{Usage: documentation }, 'need to give documentation(...) a true value');
    is($script->documentation('Applify'), $script, 'documentation(...) return $self on set');
    is($script->documentation, 'Applify', 'documentation() return what was set');

    eval { $script->print_version };
    like($@, qr{Cannot print version}, 'cannot print version without version(...)');

    eval { $script->version(undef) };
    like($@, qr{Usage: version }, 'need to give version(...) a true value');
    is($script->version('1.23'), $script, 'version(...) return $self');
    is($script->version, '1.23', 'version() return what was set');

    is_deeply([$script->_default_options], [qw/ help man version /], 'default options after documentation() and version()');
    is((run_method($script, 'print_help'))[0], <<'    HELP', 'print_help()');
Usage:
   --foo-bar  Foo can something
   --foo-2    foo_2 can something else
 * --foo-3    foo_3 can also something

   --help     Print this help text
   --man      Display manual for this application
   --version  Print application name and version

    HELP

    is((run_method($script, 'print_version'))[0], <<'    VERSION', 'print_version(numeric)');
10-basic.t version 1.23
    VERSION

    $script->version('Applify');
    is((run_method($script, 'print_version'))[0], <<"    VERSION", 'print_version(module)');
10-basic.t version $Applify::VERSION
    VERSION
}

{
    my $app = do 'example/script-simple.pl';
    my $script = $app->script;

    isa_ok($script, 'Applify');
    can_ok($app, qw/ input_file output_dir dry_run generate_exit_value /);

    eval { run_method($app, 'run') };
    is($@, "Required attribute missing: --dry-run\n", '--dry-run missing');
}

sub run_method {
    my($thing, $method, @args) = @_;
    local *STDOUT;
    local *STDERR;
    my $stdout = '';
    my $stderr = '';
    open STDOUT, '>', \$stdout;
    open STDERR, '>', \$stderr;
    return $stdout, $stderr, $thing->$method(@args);
}