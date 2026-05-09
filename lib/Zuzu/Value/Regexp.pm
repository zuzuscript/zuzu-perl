package Zuzu::Value::Regexp;

use utf8;

our $VERSION = '0.001';

use Moo;

has 'pattern' => ( is => 'rw', default => sub { '' } );
has 'flags' => ( is => 'rw', default => sub { '' } );

sub is_truthy { 1 }

sub to_String {
	my ( $self ) = @_;

	return $self->pattern // '';
}

1;
