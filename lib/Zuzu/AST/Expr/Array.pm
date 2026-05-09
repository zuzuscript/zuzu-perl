package Zuzu::AST::Expr::Array;

use utf8;

our $VERSION = '0.001';

use Moo;

has 'items' => ( is => 'rw' );

with 'Zuzu::AST::Role::Node';

sub evaluate { $_[1]->eval_array($_[0]) }

=pod

=head1 NAME

Zuzu::AST::Expr::Array - AST node for array expressions

=head1 DESCRIPTION

Represents one expression form in the abstract syntax tree and delegates evaluation to C<Zuzu::Runtime>.

=head1 INHERITANCE

Inherits from C<Moo::Object>.

=head1 ROLES

Consumes C<Zuzu::AST::Role::Node>.

=head1 ATTRIBUTES

=head2 items

Type: B<ArrayRef>.

Ordered array elements (expressions or runtime values).

=head1 METHODS

=head2 evaluate

Dispatches this AST node to the matching runtime evaluator.

=head1 SEE ALSO

C<Zuzu::AST::Role::Node>.

Subclasses: none in this distribution.

=cut

1;