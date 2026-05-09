package Zuzu::Value::Object;

use utf8;

our $VERSION = '0.001';

use Moo;

has 'class' => ( is => 'rw' );
has 'slots' => ( is => 'rw' );
has 'const' => ( is => 'rw' );
has 'types' => ( is => 'rw', default => sub { {} } );
has 'weak' => ( is => 'rw', default => sub { {} } );
has 'demolish_hook' => ( is => 'rw' );

sub is_truthy { 1 }

sub DESTROY {
	my ( $self ) = @_;

	my $hook = $self->demolish_hook;
	return if ref($hook) ne 'CODE';

	local $@;
	eval { $hook->($self); 1 } or return;

	return;
}

=pod

=head1 NAME

Zuzu::Value::Object - runtime value class for class instances

=head1 DESCRIPTION

Represents an instantiated object with class reference and slot
storage.

=head1 INHERITANCE

Inherits from C<Moo::Object>.

=head1 ROLES

None.

=head1 ATTRIBUTES

=head2 class

Type: B<InstanceOf["Zuzu::Value::Class"]>.

Class value used for method dispatch and inheritance checks.

=head2 slots

Type: B<HashRef>.

Storage for instance members and class constants copied to object.

=head2 const

Type: B<HashRef[Bool]>.

Per-slot const flags enforcing assignment restrictions.

=head1 METHODS

=head2 is_truthy

Returns this runtime value's truthiness in ZuzuScript.

=head2 DESTROY

Runs the optional lifecycle cleanup callback before this object is
garbage collected.

=head1 SEE ALSO

Subclasses: none in this distribution.

=cut

1;
