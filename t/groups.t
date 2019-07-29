use strict;
use warnings;
use Getopt::Long;
use Test::More;

my $app = eval 'use Applify; app {0};' or die $@;
my $script = $app->_script;
$script->group_options(sub {
  $script->option(flag => debug => description => 0, required => 1);
}, 'group-name');
is_deeply $script->{groups}, { 'group-name' => {
  'mode' => 'exclusive', 'options' => ['debug'] } }, 'exclusive default mode';
$script->group_options(sub {
  $script->option(flag => wait => description => 0);
}, 'group-name', 'required');
is_deeply $script->{groups}, { 'group-name' => {
  'mode' => 'exclusive', 'options' => ['debug', 'wait'] } },
  'adding to groups ok, but mode cannot be changed';
$script = $app->_script;
is_deeply $script->{groups}, { 'group-name' => {
  'mode' => 'exclusive', 'options' => ['debug', 'wait'] } },
  'groups remain';
$script->group_options(sub {
  $script->option(flag => foo => description => 0);
  $script->option(flag => bar => description => 0, required => 1);
}, 'new-group', 'required');
is_deeply $script->{groups}, {
  'group-name' => { 'mode' => 'exclusive', 'options' => ['debug', 'wait'] },
  'new-group'  => { 'mode' => 'required', 'options' => ['foo', 'bar'] }
}, 'groups remain';
my $options = $script->options;
ok !exists $_->{required}, 'grouped options cannot be required' for @$options;

my %o = (map {$script->_attr_to_option($_->{name}) => $_->{default}} @$options);
$o{$script->_attr_to_option($_->{name})} =
  $script->_generate_group_handler($_, \%o) for @$options;
{
  my @messages;
  local $SIG{__WARN__} = sub { push @messages, "@_" };
  is_deeply [map { $_->() } values %o], [0, 0, 0, 0],
    'code ref and defaults correct';
  is_deeply \@messages, [
    qq{[new-group] Required attribute missing, specify one of [--foo|--bar]\n}
    ], 'correct message';
}

# interface
# test grouping
$app = eval <<"HERE" or die $@;
use Applify;

option str => input_file => 'input';
group_options {
  option str => save => 'save work';
  option str => example => 'array', n_of => '\@';
  option flag => debug_verbose => 'really debug everything', default => 0 ;
} 'exclusive test name', 'exclusive';
option file => output => 'write output here';
app {};
HERE

$script = $app->_script;
my $instance = run($script, -example => 1, -input => 'test.txt',
  -output => 'test.out');
is $instance->input_file, 'test.txt', '--input sets input_file';
is $instance->save, undef, 'default';
is_deeply $instance->example, [1], 'single';
is $instance->debug_verbose, 0, 'off';
is $instance->output, 'test.out', 'not part of group';

# array does not trigger exclusive guard
$instance = run($script, -example => 1, -example => 42, -input => 'test.txt');
is $instance->save, undef, 'default';
is_deeply $instance->example, [1, 42], 'multiple - array option ok';
is $instance->debug_verbose, 0, 'off';

#
$instance = run($script, -save => 1, -example => 42, -input => 'test.txt');
is $instance->save, 1, 'default';
is_deeply $instance->example, [], 'multiple';
is $instance->debug_verbose, 0, 'off';

# multiple groups do the right thing
$app = eval <<"HERE" or die $@;
use Applify;

option str => input_file => 'input';
group_options {
  option str => save => 'save work';
  option str => example => 'array', n_of => '\@';
  option flag => debug_verbose => 'really debug everything', default => 0 ;
} 'exclusive test name', 'exclusive';
option file => output => 'write output here';
group_options {
  option file => input_two => 'more input', alias => 'extra';
  option flag => stdin => 'use stdin for more input', default => 0;
};
app {};
HERE

$script = $app->_script;
$instance = run($script,
  -example => 1, -example => 4, '-input-file' => 'test.txt',
  -output => 'test.out', '-stdin', '-input-two' => 'more.txt');
is $instance->save, undef, 'default';
is_deeply $instance->example, [1, 4], 'array ok';
is $instance->debug_verbose, 0, 'off';
is $instance->input_file, 'test.txt', 'input sets';
is $instance->output, 'test.out', 'not part of group';
is $instance->stdin, 1, 'stdin set - separate group not part of exclusive';
is $instance->input_two, undef, 'default as group already set';
# aliases do not confound finding the group search
$instance = run($script, qw{-stdin -stdin -stdin -stdin -extra more.txt});
is $instance->stdin, 1, 'set';
is $instance->input_two, undef, 'aliases - alias not available for message';

# at least one...
sub group_required {
  my @lines;
  local $SIG{__WARN__} = sub { push @lines, "@_" };
  # way to have control over input i.e. better than --format JSON where a typo
  # in JSON part causes bad behaviour - good to catch early.
  my $app = eval <<"HERE" or die $@;
use Applify;

option str => input_file => 'input';
group_options {
  option flag => json => 'output json file', default => 0;
  option flag => yaml => 'output yaml file', default => 0;
  option flag => text => 'output simple text file', default => 0;
} format => 'required';

app {};
HERE
  my $script = $app->_script;
  my $instance = run($script, @_);
  my $stderr = join "\n", @lines[1 .. $#lines];
  return ($instance, $stderr);
}
my ($inst, $stderr) = group_required;
is $inst->json, 0, 'default';
is $inst->yaml, 0, 'default';
is $inst->text, 0, 'default';
is $stderr =~ tr/\n/\n/, 1, 'single message';
my @lines = split "\n" => $stderr;
is $_, 
  q{[format] Required attribute missing, specify one of [--json|--yaml|--text]},
  'messages correct' for @lines;

($inst, $stderr) = group_required('-json');
is $inst->json, 1, 'default';
is $inst->yaml, 0, 'default';
is $inst->text, 0, 'default';
is $stderr, '', 'no messages';

($inst, $stderr) = group_required('-json', '-yaml', '-text');
is $inst->json, 1, 'default';
is $inst->yaml, 1, 'default';
is $inst->text, 1, 'default';
is $stderr, '', 'no messages';

# should this be fatal?
$app = eval <<'EOF';
use Applify;
group_options {} 'empty';
app {};
EOF
like $@, qr/^no options added to group '\w+'/;



sub run {
  my ($script, @lines) = shift;
  local @ARGV = @_;
  local $SIG{__WARN__} = $SIG{__WARN__} || sub { push @lines, "@_" };
  my ($app) = $script->app(@ARGV);
  return $app;
}

done_testing;

__END__
