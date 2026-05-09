use Test2::V0;
use Test2::Require::AuthorTesting;

use File::Spec;
use IPC::Open3 qw( open3 );
use Symbol qw( gensym );

my $repo_root = File::Spec->rel2abs( File::Spec->catdir( File::Spec->curdir ) );
my $highlighter = File::Spec->catfile(
	$repo_root, 'bin', 'zuzu-highlight'
);

ok -f $highlighter, 'highlighter script exists';

my $source = <<'ZZS';
let x := 10 / 2;
let rx := /ab+c/i;
function demo (value) {
	return value;
}
ZZS

my $stderr = gensym;
my $pid = open3( my $stdin, my $stdout, $stderr, $^X, $highlighter );
print {$stdin} $source;
close $stdin;

my $html = do { local $/ = undef; <$stdout> // '' };
my $err = do { local $/ = undef; <$stderr> // '' };
close $stdout;
close $stderr;
waitpid $pid, 0;
my $exit = $? >> 8;
is $exit, 0, 'highlighter exits successfully';
is $err, '', 'highlighter does not write to stderr';
like $html, qr{<span class="operator">/</span>\s*<span class="number">2</span>},
	'division slash is classified as operator';
like $html, qr{<span class="regexp">/ab\+c/i</span>},
	'regexp literal is classified as regexp';
like $html, qr{<span class="ident-decl">demo</span>},
	'function name identifier is highlighted as declaration';
like $html, qr{Parse check: ok},
	'parser validation succeeds for valid source';

done_testing;
