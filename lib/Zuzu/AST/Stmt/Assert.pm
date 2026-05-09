package Zuzu::AST::Stmt::Assert;

use utf8;

our $VERSION = '0.001';

use Moo;

has 'expr' => ( is => 'rw' );

with 'Zuzu::AST::Role::Node';

sub evaluate { $_[1]->eval_assert($_[0]) }

1;
