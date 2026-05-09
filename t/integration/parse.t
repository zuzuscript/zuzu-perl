use Test2::V0;
use Data::Dumper;

use Zuzu::Parser;

my $p = Zuzu::Parser->new;
my $ast = $p->parse(<<'SRC', "test.zzs");
function add_nums () {
	return 1 + 2;
}
SRC

# diag Dumper( $ast );
ok 1, 'base parse still succeeds';

my $ast_ops = $p->parse(<<'SRC', 'operators.zzs');
let a := not false;
let b := true xor false;
let c := true nand true;
let d := "A" eqi "a";
let e := 3 <=> 2;
let f := 1 ≶ 2;
SRC

ok $ast_ops, 'parser accepts new operator features';

my $ast_classes = $p->parse(<<'SRC', 'classes.zzs');
class Animal {
	let name;
	method get_name () {
		return name;
	}
	static method kingdom () {
		return "animalia";
	}
}
class Dog extends Animal;
let dog := new Dog( name: "Bluey" );
dog.get_name();
SRC

ok $ast_classes, 'parser accepts class and new features';

my $ast_traits = $p->parse(<<'SRC', 'traits.zzs');
trait Runner {
	method run () {
		return "ok";
	}
}
class Dog with Runner;
SRC

ok $ast_traits, 'parser accepts trait and class composition features';

my $ast_collections = $p->parse(<<'SRC', 'collections.zzs');
let arr := [ 1, 2, 3 ];
arr[1:2] := [ 9 ];
let dict := { key: 1, in: 2 };
dict{key} := 2;
dict{in} := 3;
let set := << 1, 2, 2 >>;
let bag := <<< 1, 2, 2 >>>;
let empty := ∅;
let subset := ( set subsetof << 1, 2, 3 >> );
let both := ( set union << 5 >> ) intersection << 2, 5 >>;
SRC

ok $ast_collections, 'parser accepts collection literals and lvalue forms';

my $ast_for_reuse = $p->parse(<<'SRC', 'for-reuse.zzs');
let i := 0;
for ( i in [ 1, 2, 3 ] ) {
	i += 1;
}
SRC

ok $ast_for_reuse, 'parser accepts for loops that reuse declared variables';

my $ast_for_const = $p->parse(<<'SRC', 'for-const.zzs');
for ( const item in [ 1, 2, 3 ] ) {
	item;
}
SRC

ok $ast_for_const, 'parser accepts for loops with const loop variables';

my $ast_regex = $p->parse(<<'SRC', 'regex.zzs');
let ratio := 6 / 3;
let text := "FoObAr";
let m := text ~ /(foo)(bar)/i;
if ( let cond := text ~ /foo/i ) {
	cond[0];
}
if ( m := text ~ /(foo)/i ) {
	m[1];
}
SRC

ok $ast_regex, 'parser accepts regexp literals, ~ operator, and condition let/assignment';

my $ast_path_ops = $p->parse(<<'SRC', 'path-operators-phase2.zzs');
let source := {};
let a := 1;
let b := 2;
let lhs := source @ "items[0]";
let exists := source @? "items[1]";
let many := source @@ "items[*]";
let tight1 := a@@b;
let tight2 := a@?b;
let writable := source @ "items[0]";
writable := 1;
source @ "items[0]" := 2;
source @ "items[0]" += 3;
source @? "items[1]" := 4;
source @? "items[1]" += 5;
source @@ "items[*]" := [ 3, 4 ];
source @@ "items[*]" += 6;
\( source @ "items[0]" );
\( source @@ "items[*]" );
\( source @? "items[1]" );
++( source @ "items[0]" );
( source @@ "items[*]" )++;
SRC

ok $ast_path_ops, 'parser accepts @, @?, @@ tokenization and assignment targets';

my $ast_pod = $p->parse(<<'SRC', 'pod-sections.zzs');
let before := 1;
=pod
This line is ignored by the parser.
=head1 A heading is still pod.
=cut
let after := before + 1;
SRC

ok $ast_pod, 'parser ignores pod sections that begin at start of line';

my $ast_pod_to_eof = $p->parse(<<'SRC', 'pod-to-eof.zzs');
let value := 41;
=pod
Pod may continue until end of file.
No explicit cut marker is required.
SRC

ok $ast_pod_to_eof, 'parser ignores pod sections through end of file';

my $ast_shebang = $p->parse(<<'SRC', 'shebang.zzs');
#!/usr/bin/env zuzu
let shebang_value := 7;
function shebang_result () {
	return shebang_value;
}
SRC

ok $ast_shebang, 'parser ignores leading shebang line';

my $ast_block_separator = $p->parse(<<'SRC', 'block-separator.zzs');
function block_separator_demo () {
	let x := 1;
	let y := 2
}
SRC

ok $ast_block_separator, 'parser treats semicolon as separator in blocks';

my $ast_eof_separator = $p->parse(<<'SRC', 'eof-separator.zzs');
let value := 41
SRC

ok $ast_eof_separator, 'parser allows final statement at EOF without semicolon';

my $ast_eof_return = $p->parse(<<'SRC', 'eof-return.zzs');
function eof_return () {
	return
}
SRC

ok $ast_eof_return, 'parser allows return without semicolon before block close';

my $ast_if_trailing_semicolon = $p->parse(<<'SRC', 'if-trailing-semicolon.zzs');
if ( true ) {
	say "ok";
};
SRC

ok $ast_if_trailing_semicolon, 'parser allows trailing semicolon after if block';

my $ast_extra_semicolons = $p->parse(<<'SRC', 'extra-semicolons.zzs');
say "ok"; ; ;
say "done";;;
SRC

ok $ast_extra_semicolons, 'parser treats standalone semicolons as no-op separators';

done_testing;
