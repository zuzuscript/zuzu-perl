package Zuzu::Module::JSON;

use strict;
use utf8;

our $VERSION = '0.001';

use Scalar::Util qw( blessed );
use Zuzu::Error;
use Zuzu::Util::NativeHelpers qw(
	native_class
	native_function
	native_object
	perl_to_zuzu
	zuzu_bool
	zuzu_to_perl
);

{
	package Zuzu::Module::JSON::Codec;
	require JSON::MultiValueOrdered;
	our @ISA = 'JSON::MultiValueOrdered';
	
	sub _new_hash {
		if ( $_[0]{pairlists} ) {
			tie my %h, 'Tie::Hash::MultiValueOrdered';
			return \%h;
		}
		return {};
	}
	
	sub _encode_object {
		my $self = shift;
		my $object = shift;
		
		my $indent;
		if (exists $self->{_indent}) {
			$indent = $self->{_indent};
			$self->{_indent} .= "\t";
		}
		
		my @pairs;
		my $space = defined $indent ? q( ) : q();
		my $tied = tied(%$object);
		if ($tied and $tied->DOES('Tie::Hash::MultiValueOrdered')) {
			my @list = $tied->pairs;
			for ( my $i = 0; $i < @list; $i += 2 ) {
				push @pairs, sprintf(
					'%s:%s%s',
					$self->_encode_string($list[$i]),
					$space,
					$self->_encode_values($list[$i + 1]),
				);
			}
		}
		elsif ( $self->{canonical} ) {
			for my $k ( sort keys %$object ) {
				push @pairs, sprintf(
					'%s:%s%s',
					$self->_encode_string($k),
					$space,
					$self->_encode_values($object->{$k}),
				);
			}
		}
		else {
			while ( my ($k, $v) = each %$object ) {
				push @pairs, sprintf(
					'%s:%s%s',
					$self->_encode_string($k),
					$space,
					$self->_encode_values($v),
				);
			}
		}
		
		if ( defined $indent ) {
			$self->{_indent} =~ s/^.//;
				return "{}" unless @pairs;
				return "\{\n$indent\t" . join(",\n$indent\t", @pairs) . "\n$indent\}";
		}
		else {
			return '{' . join(',', @pairs) . '}';
		}
	}
}

sub _path_tiny_from_object {
	my ( $path_obj, $method_name ) = @_;

	if (
		blessed($path_obj)
		and $path_obj->isa('Zuzu::Value::Object')
		and exists $path_obj->slots->{_path_tiny}
	) {
		return $path_obj->slots->{_path_tiny};
	}
	elsif ( ref($path_obj) eq 'HASH' and exists $path_obj->{_path_tiny} ) {
		return $path_obj->{_path_tiny};
	}

	die Zuzu::Error->new_runtime(
		message => "TypeException: $method_name expects Path as first argument",
		file => '<std/data/json>',
		line => 0,
	);
}

sub IMPORT {
	my ( $class, $runtime ) = @_;

	my $json_class = native_class(
		name => 'JSON',
	);

	$json_class->native_constructor( sub {
		my ( $rt, $klass, $positional, $named ) = @_;
		my %config = %{ $named // {} };
		if ( @{ $positional // [] } ) {
			my $first = $positional->[0];
			if ( ref($first) ) {
				my $first_hash = zuzu_to_perl( $first );
				if ( ref($first_hash) eq 'HASH' ) {
					for my $key ( CORE::keys %{ $first_hash } ) {
						$config{$key} = $first_hash->{$key};
					}
				}
			}
		}

		my $encoder = Zuzu::Module::JSON::Codec->new(
			canonical => zuzu_bool( $config{canonical}, 0 ) ? 1 : 0,
			pairlists => zuzu_bool( $config{pairlists}, 0 ) ? 1 : 0,
			pretty    => zuzu_bool( $config{pretty}, 0 ) ? 1 : 0,
			utf8      => zuzu_bool( $config{utf8}, 0 ) ? 1 : 0,
		);

		return native_object(
			class => $klass,
			slots => { _encoder => $encoder },
			const => { _encoder => 1 },
		);
	} );

	my $encode = native_function(
		name => 'encode',
		native => sub {
			my ( $self, @args ) = @_;
			my $value = @args ? $args[0] : undef;
			my $perl = zuzu_to_perl(
				$value,
				boolean_mapper => sub {
					return $_[0] ? JSON::Tiny::Subclassable->true : JSON::Tiny::Subclassable->false;
				},
			);
			return $self->slots->{_encoder}->encode( $perl );
		},
	);
	$json_class->methods->{encode} = $encode;

	my $decode = native_function(
		name => 'decode',
		native => sub {
			my ( $self, @args ) = @_;
			my $json = @args ? $args[0] : '';
			$json = defined($json) ? "$json" : '';
			my $perl = $self->slots->{_encoder}->decode( $json );
			return perl_to_zuzu(
				$perl,
				is_boolean => sub {
					blessed( $_[0] ) and $_[0]->DOES('JSON::PP::Boolean');
				},
			);
		},
	);
	$json_class->methods->{decode} = $decode;

	$json_class->methods->{load} = native_function(
		name => 'load',
		native => sub {
			my ( $self, $path_obj ) = @_;
			$runtime->assert_capability( 'fs', "JSON.load is denied by runtime policy" );
			my $path_tiny = _path_tiny_from_object( $path_obj, 'JSON.load' );
			my $json = $path_tiny->slurp_utf8;
			my $perl = $self->slots->{_encoder}->decode( $json );
			return perl_to_zuzu(
				$perl,
				is_boolean => sub {
					blessed( $_[0] ) and $_[0]->DOES('JSON::PP::Boolean');
				},
			);
		},
	);

	$json_class->methods->{dump} = native_function(
		name => 'dump',
		native => sub {
			my ( $self, $path_obj, @args ) = @_;
			$runtime->assert_capability( 'fs', "JSON.dump is denied by runtime policy" );
			my $path_tiny = _path_tiny_from_object( $path_obj, 'JSON.dump' );
			my $value = @args ? $args[0] : undef;
			my $perl = zuzu_to_perl(
				$value,
				boolean_mapper => sub {
					return $_[0] ? JSON::Tiny::Subclassable->true : JSON::Tiny::Subclassable->false;
				},
			);
			my $json = $self->slots->{_encoder}->encode( $perl );
			$path_tiny->spew_utf8( $json );
			return $path_obj;
		},
	);

	return {
		JSON => $json_class,
	};
}

1;

=pod

=head1 NAME

Zuzu::Module::JSON - std/data/json bindings for ZuzuScript.

=head1 DESCRIPTION

Implements the C<std/data/json> module. The importer provides a single class
named C<JSON>. If C<JSON::XS> is installed, it will be used as the
underlying backend; otherwise C<JSON::PP> is used.

=head1 CLASSES

=head2 JSON

Constructor options:

=over

=item * C<utf8> (default true)

=item * C<pretty> (default false)

=item * C<canonical> (default false)

=back

Instance methods:

=over

=item * C<encode(value)>

Encodes a ZuzuScript value as JSON text.

=item * C<decode(json)>

Decodes JSON text and returns the corresponding ZuzuScript value.

=item * C<load(path)>

Reads JSON text from a C<std/io> C<Path> and decodes it.
Throws if given anything other than C<Path>.

=item * C<dump(path, value)>

Encodes C<value> and writes JSON text to a C<std/io> C<Path>.
Throws if given anything other than C<Path>.

=back

=cut
