package Zuzu::Error::Compile;

use utf8;

our $VERSION = '0.001';

use Moo;

extends 'Zuzu::Error';

sub kind { 'CompileError' }

=pod

=head1 NAME

Zuzu::Error::Compile - compile-time error for parsing/analysis failures

=head1 DESCRIPTION

Represents failures detected before execution.

Typical examples include syntax errors, use of undeclared identifiers
detected by the parser, and invalid declarations such as using C<=>
instead of C<:=>.

=head1 INHERITANCE

Inherits from L<Zuzu::Error>.

=head1 METHODS

=head2 kind

Returns C<CompileError>.

=cut

1;