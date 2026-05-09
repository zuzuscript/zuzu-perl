package Zuzu::AST::Block;

use utf8;

our $VERSION = '0.001';

use Moo;

has 'statements' => ( is => 'rw' );

with 'Zuzu::AST::Role::Node';

sub evaluate {
	no warnings 'recursion';
	$_[1]->eval_block($_[0])
}

=pod

=head1 NAME

Zuzu::AST::Block - AST node representing a statement block

=head1 DESCRIPTION

AST container for a lexical block body that executes statements sequentially.

=head1 INHERITANCE

Inherits from C<Moo::Object>.

=head1 ROLES

Consumes C<Zuzu::AST::Role::Node>.

=head1 ATTRIBUTES

=head2 statements

Type: B<ArrayRef[ConsumerOf["Zuzu::AST::Role::Node"]]>.

Ordered child statements contained in the node.

=head1 METHODS

=head2 evaluate

Dispatches this AST node to the matching runtime evaluator.

=head1 SEE ALSO

C<Zuzu::AST::Role::Node>.

Subclasses: none in this distribution.

=cut

1;