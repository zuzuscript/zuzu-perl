package Zuzu::AST::Expr::Spawn;

use utf8;

our $VERSION = '0.001';

use Moo;

has 'block' => ( is => 'rw' );
has 'detach' => ( is => 'rw', default => sub { 0 } );

with 'Zuzu::AST::Role::Node';

sub evaluate { $_[1]->eval_spawn($_[0]) }

1;
