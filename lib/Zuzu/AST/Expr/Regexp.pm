package Zuzu::AST::Expr::Regexp;

use utf8;

our $VERSION = '0.001';

use Moo;

has 'parts' => ( is => 'rw' );
has 'flags' => ( is => 'rw', default => sub { '' } );

with 'Zuzu::AST::Role::Node';

sub evaluate { $_[1]->eval_regexp_literal($_[0]) }

1;
