package Zuzu::Value::Boolean;

use utf8;

our $VERSION = '0.001';

use Moo;

use overload
	'0+' => sub { $_[0]->value ? 1 : 0 },
	'""' => sub { $_[0]->value ? '1' : '0' },
	'bool' => sub { $_[0]->value ? 1 : 0 },
	fallback => 1;

has 'value' => ( is => 'rw', default => sub { 0 } );

sub is_truthy {
	my ( $self ) = @_;

	return $self->value ? 1 : 0;
}

1;
