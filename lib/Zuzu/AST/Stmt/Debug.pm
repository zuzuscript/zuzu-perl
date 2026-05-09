package Zuzu::AST::Stmt::Debug;

use utf8;

our $VERSION = '0.001';

use Moo;

has 'level_expr' => ( is => 'rw' );
has 'message_expr' => ( is => 'rw' );

with 'Zuzu::AST::Role::Node';

sub evaluate { $_[1]->eval_debug($_[0]) }

1;
