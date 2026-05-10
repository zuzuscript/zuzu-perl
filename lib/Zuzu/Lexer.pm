package Zuzu::Lexer;

use utf8;

our $VERSION = '0.001';

use Zuzu::Token ();
use Zuzu::Util ();

use Moo;

has 'src' => ( is => 'rw', default => sub { '' } );
has 'filename' => ( is => 'rw' );
has 'pos' => ( is => 'rw', default => sub { 0 } );
has 'line' => ( is => 'rw', default => sub { 1 } );
has 'col' => ( is => 'rw', default => sub { 1 } );
has 'last_token' => ( is => 'rw' );

around BUILDARGS => sub {
	my ($orig, $class, @args) = @_;

	my $args = $class->$orig(@args);
	$args->{src} = Zuzu::Util::nfc($args->{src} // '');

	return $args;
};

sub _peek {
	my ($self, $n) = @_;

	$n //= 1;

	return substr($self->src, $self->pos, $n);
}

sub _eof { $_[0]->pos >= length($_[0]->src) }

sub _adv {
	my ($self, $n) = @_;

	$n //= 1;
	for (1..$n) {
		my $ch = substr($self->src, $self->pos, 1);
		$self->pos( $self->pos + 1 );
		if ( $ch eq "\n" ) {
			$self->line( $self->line + 1 );
			$self->col(1);
		}
		else {
			$self->col( $self->col + 1 );
		}
	}
}

sub _mk {
	my ($self, $type, $value, $line, $col) = @_;

	return Zuzu::Token->new(
		type => $type,
		value => $value,
		file => $self->filename,
		line => $line,
		col  => $col,
	);
}

sub _emit {
	my ( $self, $type, $value, $line, $col ) = @_;
	my $tok = $self->_mk( $type, $value, $line, $col );
	$self->last_token($tok) if $type ne 'EOF';

	return $tok;
}

sub _can_start_regexp {
	my ( $self ) = @_;
	my $prev = $self->last_token;

	return 1 if !defined $prev;
	return 0 if $prev->is_NUMBER || $prev->is_STRING || $prev->is_type('BINARY_STRING') || $prev->is_type('TEMPLATE') || $prev->is_BOOL || $prev->is_NULL || $prev->is_IDENT || $prev->is_REGEXP || $prev->is_EMPTY_SET;
	if ( $prev->is_KW ) {
		my $kw = $prev->value // '';
		return 0 if $kw eq 'self' || $kw eq 'super' || $kw eq 'true' || $kw eq 'false' || $kw eq 'null';
	}
	if ( $prev->is_OP ) {
		my $op = $prev->value // '';
		return 0 if $op eq ')' || $op eq ']' || $op eq '}';
		return 0 if $op eq '++' || $op eq '--';
	}

	return 1;
}

sub _read_regexp_literal {
	my ( $self, $line, $col ) = @_;

	$self->_adv(1); # leading /
	my $pattern = '';
	my $escaped = 0;

	while ( !$self->_eof ) {
		my $c = $self->_peek(1);
		if ( !$escaped and $c eq '/' ) {
			$self->_adv(1);
			my $flags = '';
			while ( !$self->_eof ) {
				my $flag = $self->_peek(1);
				last if $flag ne 'i' and $flag ne 'g';
				last if index( $flags, $flag ) >= 0;
				$flags .= $flag;
				$self->_adv(1);
			}

			return $self->_emit( 'REGEXP', { pattern => $pattern, flags => $flags }, $line, $col );
		}
		$pattern .= $c;
		$escaped = ( !$escaped and $c eq "\\" ) ? 1 : 0;
		$escaped = 0 if $escaped and $c ne "\\";
		$self->_adv(1);
	}

	die "Unterminated regexp literal at line $line, col $col";
}


sub _skip_shebang_line {
	my ( $self ) = @_;

	return 0 if $self->pos != 0;
	return 0 if $self->line != 1;
	return 0 if $self->col != 1;
	return 0 if $self->_peek(2) ne '#!';

	while ( !$self->_eof and $self->_peek(1) ne "\n" ) {
		$self->_adv(1);
	}
	$self->_adv(1) if !$self->_eof and $self->_peek(1) eq "\n";

	return 1;
}

sub _skip_pod_section {
	my ( $self ) = @_;

	return 0 if $self->col != 1;
	return 0 if $self->_peek(1) ne '=';

	my $rest = substr( $self->src, $self->pos );
	return 0 if $rest !~ /\A=(\w+)/u;

	my $word = $1;
	return 0 if $word eq 'cut';

	while ( !$self->_eof and $self->_peek(1) ne "\n" ) {
		$self->_adv(1);
	}
	$self->_adv(1) if !$self->_eof and $self->_peek(1) eq "\n";

	while ( !$self->_eof ) {
		my $line = substr( $self->src, $self->pos );
		if ( $self->col == 1 and $line =~ /\A=cut(?:\r?\n|\z)/ ) {
			$self->_adv(4);
			$self->_adv(1) if !$self->_eof and $self->_peek(1) eq "\r";
			$self->_adv(1) if !$self->_eof and $self->_peek(1) eq "\n";

			last;
		}

		$self->_adv(1);
	}

	return 1;
}

sub next_token {
	my ($self) = @_;

	while (!$self->_eof) {
		if ( $self->_skip_shebang_line ) {
			next;
		}

		if ( $self->_skip_pod_section ) {
			next;
		}

		my $ch = $self->_peek(1);

		# whitespace
		if ($ch =~ /\s/u) { $self->_adv(1); next; }

		# // comment
		if ($self->_peek(2) eq '//') {
			while (!$self->_eof && $self->_peek(1) ne "\n") { $self->_adv(1); }
			next;
		}

		# /* ... */ comment
		if ($self->_peek(2) eq '/*') {
			$self->_adv(2);
			while (!$self->_eof) {
				last if $self->_peek(2) eq '*/';
				$self->_adv(1);
			}
			$self->_adv(2) if !$self->_eof;
			next;
		}

		my ($line, $col) = ($self->line, $self->col);

		if ( $ch eq '/' and $self->_can_start_regexp ) {
			return $self->_read_regexp_literal( $line, $col );
		}
		if ( $self->_peek(2) eq '_=' ) {
			$self->_adv(2);

			return $self->_emit( 'OP', '_=', $line, $col );
		}

		if ( $ch eq '⊤' ) {
			$self->_adv(1);

			return $self->_emit('BOOL', 1, $line, $col);
		}
		if ( $ch eq '⊥' ) {
			$self->_adv(1);

			return $self->_emit('BOOL', 0, $line, $col);
		}

		# numbers: int/float
		if ($ch =~ /[0-9]/) {
			my $rest = substr($self->src, $self->pos);
			if ($rest =~ /\A([0-9]+(?:\.[0-9]+)?)/) {
				my $num = $1;
				$self->_adv(length($num));

				return $self->_emit('NUMBER', $num, $line, $col);
			}
		}

			# string "..." and """..."""
			if ($ch eq '"') {
				if ($self->_peek(3) eq '"""') {
					$self->_adv(3);
					my $start = $self->pos;
					while (!$self->_eof && $self->_peek(3) ne '"""') { $self->_adv(1); }
					my $val = substr($self->src, $start, $self->pos - $start);
					$self->_adv(3) if !$self->_eof;

					return $self->_emit('STRING', $val, $line, $col);
				}
				else {
					$self->_adv(1);
					my $out = '';
					while (!$self->_eof) {
						my $c = $self->_peek(1);
						last if $c eq '"';
						if ($c eq "\\") {
							$self->_adv(1);
							my $e = $self->_peek(1);
							my %m = ( n => "\n", t => "\t", r => "\r", '"' => '"', '\\' => '\\' );
							if ( $e eq 'x' ) {
								my $hex = $self->_peek(3);
								if ( $hex !~ /\Ax([0-9A-Fa-f]{2})\z/ ) {
									die "Invalid string escape at line $line, col $col";
								}
								$out .= chr( hex($1) );
								$self->_adv(3);
								next;
							}
							$out .= ($m{$e} // $e);
							$self->_adv(1);
							next;
						}
						$out .= $c;
						$self->_adv(1);
					}
					$self->_adv(1) if !$self->_eof;

					return $self->_emit('STRING', $out, $line, $col);
				}
			}
			if ( $ch eq "'" ) {
				if ( $self->_peek(3) eq "'''" ) {
					$self->_adv(3);
					my $start = $self->pos;
					while ( !$self->_eof and $self->_peek(3) ne "'''" ) {
						$self->_adv(1);
					}
					die "Unterminated binary string literal at line $line, col $col" if $self->_eof;
					my $val = substr( $self->src, $start, $self->pos - $start );
					$self->_adv(3);

					return $self->_emit( 'BINARY_STRING', $val, $line, $col );
				}
				$self->_adv(1);
				my $out = '';
				while ( !$self->_eof ) {
					my $c = $self->_peek(1);
					last if $c eq "'";
					if ( $c eq "\\" ) {
						$self->_adv(1);
						die "Unterminated binary string literal at line $line, col $col" if $self->_eof;
						my $e = $self->_peek(1);
						my %m = (
							n => "\n",
							t => "\t",
							r => "\r",
							"'" => "'",
							'\\' => '\\',
						);
						if ( $e eq 'x' ) {
							my $hex = $self->_peek(3);
							if ( $hex !~ /\Ax([0-9A-Fa-f]{2})\z/ ) {
								die "Invalid binary escape at line $line, col $col";
							}
							$out .= chr( hex($1) );
							$self->_adv(3);
							next;
						}
						$out .= ( $m{$e} // $e );
						$self->_adv(1);
						next;
					}
					$out .= $c;
					$self->_adv(1);
				}
				die "Unterminated binary string literal at line $line, col $col" if $self->_eof;
				$self->_adv(1);

				return $self->_emit( 'BINARY_STRING', $out, $line, $col );
			}
			if ( $ch eq '`' ) {
				if ( $self->_peek(3) eq '```' ) {
					$self->_adv(3);
					my $out = '';
					while ( !$self->_eof ) {
						last if $self->_peek(3) eq '```';
						my $c = $self->_peek(1);
						if ( $c eq "\\" ) {
							$self->_adv(1);
							last if $self->_eof;
							my $e = $self->_peek(1);
							my %m = (
								n => "\n",
								t => "\t",
								r => "\r",
								'`' => '`',
								'\\' => '\\',
							);
							if ( $e eq 'x' ) {
								my $hex = $self->_peek(3);
								if ( $hex !~ /\Ax([0-9A-Fa-f]{2})\z/ ) {
									die "Invalid template escape at line $line, col $col";
								}
								$out .= chr( hex($1) );
								$self->_adv(3);
								next;
							}
							$out .= ( $m{$e} // $e );
							$self->_adv(1);
							next;
						}
						$out .= $c;
						$self->_adv(1);
					}
					die "Unterminated template literal at line $line, col $col" if $self->_eof;
					$self->_adv(3);

					return $self->_emit( 'TEMPLATE', $out, $line, $col );
				}
				$self->_adv(1);
				my $out = '';
				while ( !$self->_eof ) {
					my $c = $self->_peek(1);
					last if $c eq '`';
					if ( $c eq "\\" ) {
						$self->_adv(1);
						last if $self->_eof;
						my $e = $self->_peek(1);
						my %m = (
							n => "\n",
							t => "\t",
							r => "\r",
							'`' => '`',
							'\\' => '\\',
						);
						if ( $e eq 'x' ) {
							my $hex = $self->_peek(3);
							if ( $hex !~ /\Ax([0-9A-Fa-f]{2})\z/ ) {
								die "Invalid template escape at line $line, col $col";
							}
							$out .= chr( hex($1) );
							$self->_adv(3);
							next;
						}
						$out .= ( $m{$e} // $e );
						$self->_adv(1);
						next;
					}
					$out .= $c;
					$self->_adv(1);
				}
				die "Unterminated template literal at line $line, col $col" if $self->_eof;
				$self->_adv(1);

				return $self->_emit( 'TEMPLATE', $out, $line, $col );
			}

		# identifiers/keywords (unicode)
		{
			my $rest = substr($self->src, $self->pos);
			if ($rest =~ /\A(?:([\p{XID_Start}][\p{XID_Continue}_]*)|(_[\p{XID_Continue}_]+))/u) {
				my $id = defined($1) ? $1 : $2;
				$self->_adv(length($id));
				$id = Zuzu::Util::nfc($id);
				if ($id eq 'true' || $id eq '⊤') { return $self->_emit('BOOL', 1, $line, $col); }
				if ($id eq 'false' || $id eq '⊥') { return $self->_emit('BOOL', 0, $line, $col); }
				if ($id eq 'null') { return $self->_emit('NULL', undef, $line, $col); }

				return $self->_emit('KW', $id, $line, $col) if Zuzu::Util::is_keyword($id);

				return $self->_emit('IDENT', $id, $line, $col);
			}
		}

		if ( $ch eq '∅' ) {
			$self->_adv(1);

			return $self->_emit('EMPTY_SET', '∅', $line, $col);
		}

		# operators / punct (try longest first)
		my @ops = (
			'<<<', '>>>',
			'{{', '}}',
			'<=>', '**', '==', '!=', '<=', '>=', ':=', '~=', '+=', '-=', '*=', '/=',
			'×=', '÷=', '**=', '_=', '?:=', '@@', '@?', '++', '--', '->', '→', '?:', '...',
			'⊂⊃',
			'<<', '>>', '«', '»',
			'{', '}', '(', ')', '[', ']', ',', ';', ':', '.', '?', '_', '@',
			'+', '-', '*', '/', '<', '>', '=', '!', '~', '&', '|', '^',
			'⌊', '⌋', '⌈', '⌉',
		);
		# plus unicode aliases you mentioned (not exhaustive)
		push @ops, qw( × ÷ ≠ ≤ ≥ ≡ ≢ ≶ ≷ ⋀ ⋁ ⊻ ⊼ ¬ ∈ ∉ ⋃ ⋂ ⊂ ⊃ ∖ \ );
		# sort by length desc for greedy match
		@ops = sort { length($b) <=> length($a) } @ops;

		for my $op (@ops) {
			if ($self->_peek(length($op)) eq $op) {
				$self->_adv(length($op));

				return $self->_emit('OP', $op, $line, $col);
			}
		}

		# single char fallback punct/op
		$self->_adv(1);

		return $self->_emit('OP', $ch, $line, $col);
	}

	return Zuzu::Token->new(type => 'EOF', value => undef, file => $self->filename, line => $self->line, col => $self->col);
}

=pod

=head1 NAME

Zuzu::Lexer - lexer that tokenizes ZuzuScript source text

=head1 DESCRIPTION

Scans normalized source text and emits C<Zuzu::Token> objects with source location metadata.

=head1 INHERITANCE

Inherits from C<Moo::Object>.

=head1 ROLES

None.

=head1 ATTRIBUTES

=head2 src

Type: B<Str>.

Unicode-normalized source text being lexed.

=head2 filename

Type: B<Maybe[Str]>.

Filename attached to generated tokens and parser errors.

=head2 pos

Type: B<Int>.

Current character offset in C<src>.

=head2 line

Type: B<Int>.

1-based source line number used for diagnostics.

=head2 col

Type: B<Int>.

1-based source column number used for diagnostics.

=head1 METHODS

=head2 new

Constructs and returns a new instance of this class.

=head2 next_token

Consumes input and returns the next C<Zuzu::Token>.

=head1 SEE ALSO

Subclasses: none in this distribution.

=cut

1;
