package Zuzu::AST::Stmt::LetUnpack;

use utf8;

our $VERSION = '0.001';

use Moo;

has 'bindings' => ( is => 'rw' );
has 'init' => ( is => 'rw' );
has 'is_const' => ( is => 'rw' );

with 'Zuzu::AST::Role::Node';

sub evaluate {
	no warnings 'recursion';
	$_[1]->eval_let_unpack($_[0])
}

=pod

=head1 NAME

Zuzu::AST::Stmt::LetUnpack - AST node for declaration unpacking

=head1 DESCRIPTION

Represents C<let { ... } := expr> and C<const { ... } := expr>
declarations.

=head1 METHODS

=head2 evaluate

Dispatches this AST node to the matching runtime evaluator.

=cut

1;
