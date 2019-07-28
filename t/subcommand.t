use strict;
use warnings;

package MyListing;
our $VERSION = 1;
sub list {}
package MyLogging;
our $VERSION = 1;
sub start_log {}
sub end_log {}
package main;
use B::Deparse;
use Test::More;
use lib '.';
use t::Helper;
no lib '.';

my ($stdout, $stderr);

my $code = <<'HERE';
use Applify;
option str => input_file => 'input';
option flag => save => 'save work';
subcommand list => 'provide a listing' => sub {
  extends 'MyListing';
  option str => long => 'long list';
};
subcommand log => 'provide a log' => sub {
  extends 'MyLogging';
  option str => age => 'age of log', required => 1;
};

sub command_list {
  my ($self, @extra) = @_;
  return 2;
}
sub command_log {
  my ($self, @extra) = @_;
  return 0;
}

app {
  my ($self, @extra) = @_;
  $self->_script->print_help;
  return 0;
};
HERE

{
  my $a = eval_script("use Applify; app {};");
  is $a->_script->subcommand, undef, 'does not die';
}

{
  my $app = eval_script(<<'HERE');
package App::Base;
sub none {}
package main;
use Applify;
subcommand disallow => 'app call' => sub {
  option str => name => 'name';
  extends 'App::Base';
  documentation 'Applify';
  app {
    my ($self, @extra) = @_;
    return 0;
  };
};
app { return 1 };
HERE
  ok $app, 'not undef';
  
  local @ARGV = qw{disallow};
  like + (run_method($app->_script, 'app'))[1],
    qr/Looks like you have a typo/, 'confessions of a app happy coder.';
}

{
  my $app = eval_script($code, 'list', '--save', '--long', 1);
  isa_ok $app, 'MyListing', 'correct inheritance';
  is $app->save, 1, 'global option set';
  is $app->long, 1, 'long list option set';

  my $script = $app->_script;
  is $script->subcommand, 'list', 'access the subcommand being run';
  my $code = $script->_subcommand_code($app);
  isa_ok $code, 'CODE', 'code reference';
  is deparse($code), deparse(sub {
    my ($self, @extra) = @_;
    return 2;
  }), 'correct subroutine';
}

{
  my $app = eval_script($code, 'log', '--age', '2d', '--save');
  isa_ok $app, 'MyLogging', 'correct inheritance';
  is $app->age, '2d', 'age option set';
  is $app->save, 1, 'global option set';
  $app->run(qw{});
  my $script = $app->_script;
  is $script->subcommand, 'log', 'access the subcommand being run';
  my $has_log = can_ok $app, qw{start_log end_log};
  ok $has_log, 'app extends MyLogging';
  my $code = $script->_subcommand_code($app);
  isa_ok $code, 'CODE', 'code reference';
  is deparse($code), deparse(sub {
    my ($self, @extra) = @_;
    return 0;
  }), 'correct subroutine';

  is + (run_method($script, 'print_help'))[0], <<'HERE', 'print_help()';
Usage:

    subcommand.t [command] [options]

commands:
    list  provide a listing
    log   provide a log

options:
   --input-file  input
   --save        save work
 * --age         age of log

   --help        Print this help text

HERE

}

{
  my $app = eval_script($code, 'logs', '--long', 'prefix');
  isa_ok $app, 'HASH', 'object as exit did not happen';
  is $app->save, undef, 'not set';
  my $script = $app->_script;
  is $script->subcommand, undef, 'no matching subcommand';
  my $code = $script->_subcommand_code($app);
  is $code, undef, 'no code reference';
  is + (run_method($app, 'run'))[0], <<'HERE', 'should print help';
Usage:

    subcommand.t [command] [options]

commands:
    list  provide a listing
    log   provide a log

options:
   --input-file  input
   --save        save work

   --help        Print this help text

HERE

}

{
  my $app = eval_script(<<'HERE', qw{new -name app -output app.pm});
use Applify;
$Applify::SUBCMD_PREFIX = 'app';
subcommand new => 'new event' => sub {
  option str => name => 'event name', required => 1;
  option file => output => 'file to write', required => 1;
  documentation 'File::Temp';
};
sub app_new {
  my ($self, @extra) = @_;
  $self->create(name => $self->name, file => $self->output);
  return 0;
}
app {
  my ($self, @extra) = @_;
  return 0;
}
HERE
  isa_ok $app, 'HASH', 'object as exit did not happen';
  is $app->name, 'app', 'name set';
  is $app->output, 'app.pm', 'output set';
  my $script = $app->_script;
  is $script->subcommand, 'new', 'matching subcommand';
  my $code = $script->_subcommand_code($app);
  isa_ok $code, 'CODE', 'no code reference';
  is deparse($code), deparse(sub {
    my ($self, @extra) = @_;
    $self->create(name => $self->name, file => $self->output);
    return 0;
  }), 'Applify::SUBCMD_PREFIX can be set';
}

my $excl_regex =
  qr{^\[\w+\] Cannot also specify '\-\-\w+' when '\-\-\w+' already specified$};
{
  # group_options
  my $script = <<'EOF';
use Applify;
group_options {
  option flag => one => zero => 1;
  option flag => two => four => 0;
} binary => 'exclusive';
subcommand size => 'determine size' => sub {
  group_options {
    option flag => approx => approximate => 0;
    option flag => precise => 'precision is not accuracy' => 0;
    option flag => accurate => exact => 0;
  } accuracy => 'exclusive';
};
app {};
EOF
  # no options - baseline
  my $app = eval_script($script);
  is $app->one, 1, 'default';
  is $app->two, 0, 'default';
  is $stderr =~ tr/\n/\n/, 0, 'STDERR has zero lines';
  # negate to sanity check
  $app = eval_script($script, '-no-one');
  is $app->one, 0, 'unset via cmdline';
  ok !$app->can('approx'), 'can not';
  is $stderr =~ tr/\n/\n/, 0, 'STDERR has zero lines';
  # negate option plus normal within exclusive group
  $app = eval_script($script, '-no-one', '-two');
  is $app->one, 0, 'unset';
  is $app->two, 0, 'cannot alter multiple exclusives';
  is $stderr =~ tr/\n/\n/, 1, 'STDERR has correct line count';
  like $_, $excl_regex, 'line matches expected message' for split $/, $stderr;
  # subcommand size, check both groups interactions
  $app = eval_script($script, qw{size -approx -precise -accurate -no-one});
  is $app->one, 0, 'was unset';
  is $app->approx, 1, 'first one won';
  is $app->precise, 0, 'not set';
  is $app->accurate, 0, 'not set';
  is $stderr =~ tr/\n/\n/, 2, 'STDERR has correct line count';
  like $_, $excl_regex, 'line matches expected message' for split $/, $stderr;
  # subcommand size, trigger exclusive guard in both groups
  $app = eval_script($script, qw{size -accurate -precise -no-one -two});
  is $app->one, 0, 'was unset';
  is $app->two, 0, 'still exclusive';
  is $app->approx, 0, 'remain unset';
  is $app->precise, 0, 'not set';
  is $app->accurate, 1, 'first one set';
  is $stderr =~ tr/\n/\n/, 2, 'STDERR has correct line count';
  like $_, $excl_regex, 'line matches expected message' for split $/, $stderr;
}

{
  # group_options - groups of same name act as if one.
  my $script = <<'EOF';
use Applify;
group_options {
  option flag => one => zero => 1;
  option flag => two => four => 0;
} accuracy => 'exclusive';
subcommand size => 'determine size' => sub {
  group_options {
    option flag => approx => approximate => 0;
    option flag => precise => 'precision is not accuracy' => 0;
    option flag => accurate => exact => 0;
  } accuracy => 'exclusive';
};
app {};
EOF
  # subcommand size, check trigger across both specifications
  my $app = eval_script($script, qw{size -two -accurate});
  is $app->one, 1, 'default functions';
  is $app->two, 1, 'set';
  is $app->accurate, 0, 'acts as exclusive';
  is $stderr =~ tr/\n/\n/, 1, 'STDERR has correct line count';
  like $_, $excl_regex, 'line matches expected message' for split $/, $stderr;

  $app = eval_script($script, qw{size -precise -accurate});
  is $app->two, 0, 'set';
  is $app->precise, 1, 'first set';
  is $app->accurate, 0, 'acts as exclusive';
  is $stderr =~ tr/\n/\n/, 1, 'STDERR has correct line count';
  like $_, $excl_regex, 'line matches expected message' for split $/, $stderr;
}

sub deparse {
  my $dp = B::Deparse->new();
  return $dp->coderef2text($_[0] || sub {
    warn "this is not the code you are looking for";
  });
}

sub eval_script {
    my ($code, @args) = @_;
    local @ARGV = @args;
    local *STDOUT;
    local *STDERR;
    $stdout = $stderr = '';
    open STDOUT, '>', \$stdout;
    open STDERR, '>', \$stderr;
    my $app = eval "$code" or die $@;

    return $app;
}

done_testing();
