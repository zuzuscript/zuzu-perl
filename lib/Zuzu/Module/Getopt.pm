package Zuzu::Module::Getopt;

use utf8;

our $VERSION = '0.001';

use Getopt::Long qw( GetOptionsFromArray Configure );

use Zuzu::Util::NativeHelpers qw(
	native_class
	native_function
	perl_to_zuzu
	zuzu_bool
	zuzu_to_perl
);

sub _schema_type_name {
	my ( $value ) = @_;

	return 'Boolean' if not defined $value;
	return "$value" if not ref($value);

	if ( eval { $value->can('name') } ) {
		my $name = eval { $value->name };
		return "$name" if defined $name;
	}

	if ( ref($value) eq 'HASH' and exists $value->{name} ) {
		return "$value->{name}";
	}

	return "$value";
}

sub _schema_type_to_suffix {
	my ( $type_name ) = @_;

	my $name = lc( defined $type_name ? "$type_name" : 'boolean' );
	return '' if $name eq 'boolean' or $name eq 'bool';
	return '=f' if $name eq 'number' or $name eq 'num';
	return '=s' if $name eq 'string' or $name eq 'str';
	return '=i' if $name eq 'int' or $name eq 'integer';

	return '=s';
}

sub IMPORT {
	my ( $class, $runtime ) = @_;

	my $getopt_class = native_class(
		name => 'Getopt',
	);

	$getopt_class->static_methods->{parse} = native_function(
		name => 'parse',
		native => sub {
			my ( $self, $argv_value, $specs_value, $config_value ) = @_;

			my $argv = zuzu_to_perl( $argv_value );
			$argv = [] if ref($argv) ne 'ARRAY';
			my @argv = map { defined $_ ? "$_" : '' } @{ $argv };

			my $specs = zuzu_to_perl( $specs_value );
			$specs = [] if ref($specs) ne 'ARRAY';
			my @specs = map { defined $_ ? "$_" : '' } @{ $specs };

			my $config = zuzu_to_perl( $config_value );
			$config = [] if ref($config) ne 'ARRAY';
			my @config = map { defined $_ ? "$_" : '' } @{ $config };

			my %options;
			my $warning = '';
			my $ok;

			{
				local $SIG{__WARN__} = sub {
					$warning .= $_[0];
					return;
				};
				Configure( @config ) if scalar @config;
				$ok = GetOptionsFromArray( \@argv, \%options, @specs ) ? 1 : 0;
			}

			$warning =~ s/\s+\z//;

			return perl_to_zuzu(
				{
					ok => $ok,
					options => \%options,
					argv => \@argv,
					error => ( $warning eq '' ? undef : $warning ),
				},
			);
		},
	);

	$getopt_class->static_methods->{schema} = native_function(
		name => 'schema',
		native => sub {
			my ( $self, $argv_value, $schema_value, $config_value ) = @_;

			my $argv = zuzu_to_perl( $argv_value );
			$argv = [] if ref($argv) ne 'ARRAY';
			my @argv = map { defined $_ ? "$_" : '' } @{ $argv };

			my $schema = zuzu_to_perl( $schema_value );
			$schema = [] if ref($schema) ne 'ARRAY';

			my $config = zuzu_to_perl( $config_value );
			$config = [] if ref($config) ne 'ARRAY';
			my @config = map { defined $_ ? "$_" : '' } @{ $config };

			my @specs;
			my @usage;
			my %meta;

				for my $entry ( @{ $schema } ) {
					next if ref($entry) ne 'HASH';
					my $name = defined $entry->{name} ? "$entry->{name}" : '';
					next if $name eq '';
					my $short = defined $entry->{short} ? "$entry->{short}" : '';
					my $type = _schema_type_name( $entry->{type} );
					my $required = zuzu_bool( $entry->{required}, 0 ) ? 1 : 0;
					my $multiple = zuzu_bool( $entry->{multiple}, 0 ) ? 1 : 0;
					my $desc = defined $entry->{desc} ? "$entry->{desc}" : '';
					my $default = $entry->{default};

					my $suffix = _schema_type_to_suffix($type);
					$suffix .= '@' if $multiple;

				my $spec = $short ne '' ? "$name|$short$suffix" : "$name$suffix";
				push @specs, $spec;

				$meta{$name} = {
					required => $required,
					default => $default,
					type => $type,
					multiple => $multiple,
				};

					my $usage = '  --' . $name;
					$usage .= ", -$short" if $short ne '';
					$usage .= " <$type>" if lc($type) ne 'boolean' and lc($type) ne 'bool';
				$usage .= ' (required)' if $required;
				$usage .= "  $desc" if $desc ne '';
				push @usage, $usage;
			}

			my %options;
			my $warning = '';
			my $ok;

			{
				local $SIG{__WARN__} = sub {
					$warning .= $_[0];
					return;
				};
				Configure( @config ) if scalar @config;
				$ok = GetOptionsFromArray( \@argv, \%options, @specs ) ? 1 : 0;
			}

			my @errors;
			if ( $warning ne '' ) {
				$warning =~ s/\s+\z//;
				push @errors, $warning;
			}

			for my $name ( sort CORE::keys %meta ) {
				my $m = $meta{$name};
				if ( not exists $options{$name} and exists $m->{default} ) {
					$options{$name} = $m->{default};
				}
				if ( $m->{required} and not exists $options{$name} ) {
					push @errors, "missing required option --$name";
				}
			}

			$ok = 0 if scalar @errors;

			return perl_to_zuzu(
				{
					ok => $ok ? 1 : 0,
					options => \%options,
					argv => \@argv,
					error => scalar @errors ? join( "\n", @errors ) : undef,
					errors => \@errors,
					usage => join( "\n", @usage ),
					specs => \@specs,
				},
			);
		},
	);

	return {
		Getopt => $getopt_class,
	};
}

1;

=pod

=head1 NAME

Zuzu::Module::Getopt - C<std/getopt> bindings for ZuzuScript.

=head1 DESCRIPTION

Implements C<std/getopt>, exporting C<Getopt>.

=head1 CLASSES

=head2 Getopt

Static option-parsing helpers backed by C<Getopt::Long>.

=over

=item * C<parse(argv, specs, config?)>

Parses options from the provided C<argv> array with
C<Getopt::Long::GetOptionsFromArray>. Returns a dictionary containing
C<ok>, C<options>, C<argv> (remaining positional args), and C<error>
(warning text when parse fails).

This does not read Perl's C<@ARGV>; callers provide C<argv>
explicitly, which is useful for C<__main__(argv)> in script files.

=back

=cut
