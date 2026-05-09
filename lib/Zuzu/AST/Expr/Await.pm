package Zuzu::AST::Expr::Await;

use utf8;

our $VERSION = '0.001';

use Moo;

has 'block' => ( is => 'rw' );

with 'Zuzu::AST::Role::Node';

sub evaluate { $_[1]->eval_await($_[0]) }

1;
