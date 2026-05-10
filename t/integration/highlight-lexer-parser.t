use Test2::V0;
use Test2::Require::AuthorTesting;

use utf8;
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
let bytes := 'abc';
let bytes2 := '''ab
cd''';
let template := ```Hello {x}```;
let yes := ⊤;
let no := ⊥;
let none := ∅;
let data := { meta: { title: "T" } };
let exists := data @? "/meta/title";
let floored := ⌊1.8⌋;
let ceiled := ⌈1.2⌉;
async function demo (value) {
	let task := spawn {
		return value;
	};
	return await {
		task;
	}
}
ZZS

my $stderr = gensym;
my $pid = open3( my $stdin, my $stdout, $stderr, $^X, $highlighter );
binmode $stdin, ':encoding(UTF-8)';
binmode $stdout, ':encoding(UTF-8)';
binmode $stderr, ':encoding(UTF-8)';
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
like $html, qr{<span class="string">'abc'</span>},
	'binary string literal is classified as string';
like $html, qr{(?s)<span class="string">'''ab\ncd'''</span>},
	'triple binary string literal is classified as string';
like $html, qr{<span class="string">```Hello \{x\}```</span>},
	'triple template literal is classified as string';
like $html, qr{<span class="boolean">⊤</span>},
	'Unicode true literal is classified as boolean';
like $html, qr{<span class="boolean">⊥</span>},
	'Unicode false literal is classified as boolean';
like $html, qr{<span class="operator">∅</span>},
	'empty set literal is classified as operator';
like $html, qr{<span class="operator">@\?</span>},
	'path-exists operator is classified as operator';
like $html, qr{<span class="operator">⌊</span><span class="number">1\.8</span><span class="operator">⌋</span>},
	'floor brackets are classified as operators around their expression';
like $html, qr{<span class="keyword">async</span>\s*<span class="keyword">function</span>},
	'async function keywords are highlighted';
like $html, qr{<span class="keyword">spawn</span>},
	'spawn keyword is highlighted';
like $html, qr{<span class="keyword">await</span>},
	'await keyword is highlighted';
like $html, qr{<span class="ident-decl">demo</span>},
	'function name identifier is highlighted as declaration';
like $html, qr{Parse check: ok},
	'parser validation succeeds for valid source';

done_testing;
