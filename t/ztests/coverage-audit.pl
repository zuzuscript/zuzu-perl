use strict;
use warnings;
use utf8;

use File::Find qw( find );
use File::Spec;

my $repo_root = File::Spec->rel2abs( File::Spec->catdir( File::Spec->curdir ) );
my $ztests_dir = File::Spec->catdir( $repo_root, 't', 'ztests' );
my $ref_doc = File::Spec->catfile(
	$repo_root,
	'docs',
	'zuzuscript-guide',
	'07-operator-and-syntax-reference.md',
);

my @expected_operator_files = (
	't/ztests/lang/operators/numeric.zzs',
	't/ztests/lang/operators/numeric-unary.zzs',
	't/ztests/lang/operators/numeric-comparison.zzs',
	't/ztests/lang/operators/string.zzs',
	't/ztests/lang/operators/boolean.zzs',
	't/ztests/lang/operators/equality.zzs',
	't/ztests/lang/operators/collection-operators.zzs',
	't/ztests/lang/operators/assignment.zzs',
	't/ztests/lang/operators/regex-and-ternary.zzs',
);

my @expected_keyword_files = (
	't/ztests/lang/keywords/declarations.zzs',
	't/ztests/lang/keywords/flow.zzs',
	't/ztests/lang/keywords/loop-control.zzs',
	't/ztests/lang/keywords/errors.zzs',
	't/ztests/lang/keywords/modules.zzs',
	't/ztests/lang/keywords/runtime-debug.zzs',
	't/ztests/lang/keywords/static.zzs',
);

my @expected_control_files = (
	't/ztests/lang/control/conditions.zzs',
	't/ztests/lang/control/loops.zzs',
	't/ztests/lang/control/switch.zzs',
);

my @expected_function_files = (
	't/ztests/lang/functions/signatures.zzs',
	't/ztests/lang/functions/lambdas.zzs',
);

my @expected_oop_files = (
	't/ztests/lang/oop/classes-basic.zzs',
	't/ztests/lang/oop/inheritance.zzs',
	't/ztests/lang/oop/traits.zzs',
	't/ztests/lang/oop/super-and-static.zzs',
	't/ztests/lang/oop/dynamic-member-call.zzs',
	't/ztests/lang/oop/nested-classes.zzs',
	't/ztests/lang/oop/type-checks.zzs',
	't/ztests/lang/oop/builtin-subclassing.zzs',
);

my @operator_tokens = (
	qw(
		+ - * × / ÷ ** mod
		abs sqrt √ floor ceil round int
		⌊ ⌈
		= != ≠ < > <= ≤ >= ≥ <=> ≶ ≷
		== ≡ ≢
		_ eq ne gt ge lt le cmp
		eqi nei gti gei lti lei cmpi
		~
		and or xor nand
		not ¬ ⋀ ⋁ ⊻ ⊼
		in ∈ ∉ union ⋃ intersection ⋂ \\ ∖ subsetof ⊂ supersetof ⊃ equivalentof ⊂⊃
		+= -= *= ×= /= ÷= **= _= ?:=
	),
);

my @keyword_tokens = qw(
	let const function method class trait static
	if else unless while for switch case default return next continue last
	new self super extends with but typeof instanceof does can
	from import as try catch throw die do
	warn say print debug assert
);

my $docs_text = _slurp_utf8( $ref_doc );
my @doc_missing_ops = _missing_in_text( \@operator_tokens, $docs_text );
my @doc_missing_keywords = _missing_in_text( \@keyword_tokens, $docs_text );

my @zzs_files = _all_zzs_files( $ztests_dir );
my $native_text = join "\n", map { _slurp_utf8($_) } @zzs_files;
my @native_missing_ops = _missing_in_text( \@operator_tokens, $native_text );
my @native_missing_keywords = _missing_in_text( \@keyword_tokens, $native_text );

my @missing_operator_files = grep {
	my $abs = File::Spec->catfile( $repo_root, split m{/}, $_ );
	not -f $abs;
} @expected_operator_files;

my @missing_keyword_files = grep {
	my $abs = File::Spec->catfile( $repo_root, split m{/}, $_ );
	not -f $abs;
} @expected_keyword_files;

my @missing_control_files = grep {
	my $abs = File::Spec->catfile( $repo_root, split m{/}, $_ );
	not -f $abs;
} @expected_control_files;

my @missing_function_files = grep {
	my $abs = File::Spec->catfile( $repo_root, split m{/}, $_ );
	not -f $abs;
} @expected_function_files;

my @missing_oop_files = grep {
	my $abs = File::Spec->catfile( $repo_root, split m{/}, $_ );
	not -f $abs;
} @expected_oop_files;

print "ztests coverage audit\n";
print "====================\n";
print "reference doc: docs/zuzuscript-guide/07-operator-and-syntax-reference.md\n";
print "ztests scanned: " . scalar(@zzs_files) . "\n\n";

_print_section( 'missing expected operator ztest files', \@missing_operator_files );
_print_section( 'missing expected keyword ztest files', \@missing_keyword_files );
_print_section( 'missing expected control ztest files', \@missing_control_files );
_print_section( 'missing expected function ztest files', \@missing_function_files );
_print_section( 'missing expected oop ztest files', \@missing_oop_files );
_print_section( 'operator tokens missing from docs reference', \@doc_missing_ops );
_print_section( 'keyword tokens missing from docs reference', \@doc_missing_keywords );
_print_section( 'operator tokens missing from native ztests', \@native_missing_ops );
_print_section( 'keyword tokens missing from native ztests', \@native_missing_keywords );

exit 0;

sub _all_zzs_files {
	my ($root) = @_;
	my @files;
	find(
		{
			no_chdir => 1,
			wanted => sub {
				return if -d $_;
				return if $_ !~ /\.zzs\z/;
				push @files, $File::Find::name;
			},
		},
		$root,
	);

	return sort @files;
}

sub _missing_in_text {
	my ( $tokens, $text ) = @_;
	my @missing;

	for my $token ( @{$tokens} ) {
		if ( index( $text, $token ) < 0 ) {
			push @missing, $token;
		}
	}

	return @missing;
}

sub _print_section {
	my ( $title, $items ) = @_;
	print "$title:\n";
	if ( not @{$items} ) {
		print "  - none\n\n";
		return;
	}

	for my $item ( @{$items} ) {
		print "  - $item\n";
	}
	print "\n";
}

sub _slurp_utf8 {
	my ($path) = @_;
	open my $fh, '<:encoding(UTF-8)', $path
		or die "Could not open $path: $!";
	local $/;
	my $text = <$fh>;
	close $fh;

	return $text;
}
