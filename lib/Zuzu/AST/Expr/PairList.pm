package Zuzu::AST::Expr::PairList;

use utf8;

our $VERSION = '0.001';

use Moo;

has 'pairs' => ( is => 'rw' ); # [ [key_expr, val_expr], ... ]

with 'Zuzu::AST::Role::Node';

sub evaluate { $_[1]->eval_pairlist($_[0]) }

1;
