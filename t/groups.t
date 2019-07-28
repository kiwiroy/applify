use strict;
use warnings;
use Getopt::Long;
use Test::More;

# test grouping
my $app = eval <<"HERE" or die $@;
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

my $script = $app->_script;
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

# should this be fatal?
$app = eval <<'EOF';
use Applify;
group_options {} 'empty';
app {};
EOF
like $@, qr/^no options added to group '\w+'/;



sub run {
  my $script = shift;
  local @ARGV = @_;
  my ($app) = $script->app(@ARGV);
  return $app;
}

done_testing;

__END__
sub _make_group_processor {
  my ($options, $names) = @_;
  return sub {
    my ($name, $value) = @_;
    $options->{$name} = undef;
    diag $name;
    return unless grep { $_ eq $name } @$names;
    $options->{$name} = $value;
  };
};

{
  local @ARGV = qw{-a a -b 5 -a k};
  my $parser = Getopt::Long::Parser->new(
    config => [qw(no_auto_help no_auto_version pass_through)]);
  my %options;
  $options{'a'} = _make_group_processor(\%options, [qw{b}]);
  $parser->getoptions(\%options,
    'a=s', 'b=i'
  );
  diag explain \%options;
}
