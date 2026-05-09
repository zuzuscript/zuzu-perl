package Zuzu::Parser;

use utf8;

our $VERSION = '0.001';

use Zuzu::Error;
use Zuzu::Lexer;
use Zuzu::Parser::_Impl;
use Zuzu::AST::Visitor::TypeCheckHints;
use Zuzu::Util ();

use Moo;

sub parse {
	my ($self, $src, $filename) = @_;

	my $lx = Zuzu::Lexer->new(src => $src, filename => $filename);
	my $p = Zuzu::Parser::_Impl->new(lexer => $lx, filename => $filename);

	my $ast;
	eval {
		$ast = $p->parse_program;
		Zuzu::AST::Visitor::TypeCheckHints->new->apply( $ast );
		1;
	} or do {
		my $err = $@;
		die $err if ref($err) and eval { $err->isa('Zuzu::Error') };
		die Zuzu::Error->new_compile(
			code => 'E_COMPILE_INTERNAL',
			message => "Internal parser failure: $err",
			file => ( defined $filename ? $filename : '<input>' ),
			line => 1,
		);
	};

	return $ast;
}

=pod

=head1 NAME

Zuzu::Parser - entry point for parsing source text into an AST

=head1 DESCRIPTION

Converts source text into a C<Zuzu::AST::Program> by lexing and delegating to C<Zuzu::Parser::_Impl>.

=head1 INHERITANCE

Inherits from C<Moo::Object>.

=head1 ROLES

None.

=head1 METHODS

=head2 parse

Parses source text and returns a C<Zuzu::AST::Program>.

=head1 SEE ALSO

Subclasses: none in this distribution.

=cut

1;