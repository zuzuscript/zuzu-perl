#!/usr/bin/env perl
use strict;
use warnings;
use utf8::all;

use File::Basename qw( dirname );
use File::Find qw( find );
use File::Spec;
use File::Temp qw( tempdir );
use Getopt::Long qw( GetOptions );
use IO::Select;
use IPC::Open3 qw( open3 );
use JSON::PP;
use POSIX qw( strftime );
use Symbol qw( gensym );
use TAP::Parser;
use Path::Tiny;
use Time::HiRes qw( time );

my $repo_root = File::Spec->rel2abs(
	File::Spec->catdir( dirname(__FILE__), '..', '..' )
);
my $ztests_dir = File::Spec->catdir( $repo_root, 't', 'ztests' );
my $default_output_path = File::Spec->catfile(
	$ztests_dir,
	'implementation-matrix.json',
);

my $timeout_seconds = 60;
my $output_path = $default_output_path;
my $perl_command     = "./bin/zuzu -It/modules";
my $rust_command     = './extras/zuzu-rust/target/release/zuzu-rust -It/modules';
my $js_command       = './extras/zuzu-js/bin/zuzu-js -It/modules';
my $electron_js_command =
	'./extras/zuzu-js/node_modules/.bin/electron ' .
	'extras/zuzu-js/bin/zuzu-js-electron -It/modules';
my $only_test_pattern;
my $jobs = 4;
my $include_marshal_interop = 1;
my $_marshal_weak_fixtures;
my $_marshal_malformed_fixtures;

$| = 1;

GetOptions(
	'timeout=i' => \$timeout_seconds,
	'output=s' => \$output_path,
	'perl-cmd=s' => \$perl_command,
	'rust-cmd=s' => \$rust_command,
	'js-cmd=s' => \$js_command,
	'electron-js-cmd=s' => \$electron_js_command,
	'only=s' => \$only_test_pattern,
	'jobs=i' => \$jobs,
	'marshal-interoperability!' => \$include_marshal_interop,
) or die _usage();

if ( defined $only_test_pattern and $only_test_pattern eq '' ) {
	die "--only requires a non-empty pattern\n";
}
if ( not defined $jobs or $jobs < 1 ) {
	die "--jobs requires an integer >= 1\n";
}

my @ztest_files = _discover_ztest_files($ztests_dir);
if ( defined $only_test_pattern ) {
	@ztest_files = grep {
		my $rel = File::Spec->abs2rel( $_, $repo_root );
		$rel =~ s{\\}{/}g;
		$rel =~ /$only_test_pattern/;
	} @ztest_files;
}
@ztest_files = _prioritize_ztest_files(
	ztest_files => \@ztest_files,
	repo_root => $repo_root,
	matrix_path => $default_output_path,
);

if ( scalar @ztest_files == 0 ) {
	my $interop_selected = $include_marshal_interop
		&& _marshal_interop_selected($only_test_pattern);
	die "No ztest files selected.\n" if not $interop_selected;
}

my %matrix;
if ( scalar @ztest_files > 0 ) {
	%matrix = _build_matrix_parallel(
		repo_root => $repo_root,
		timeout_seconds => $timeout_seconds,
		perl_command => $perl_command,
		rust_command => $rust_command,
		js_command => $js_command,
		electron_js_command => $electron_js_command,
		ztest_files => \@ztest_files,
		jobs => $jobs,
	);
}

if ($include_marshal_interop) {
	my %marshal_matrix = _build_marshal_interop_matrix(
		repo_root => $repo_root,
		timeout_seconds => $timeout_seconds,
		perl_command => $perl_command,
		rust_command => $rust_command,
		js_command => $js_command,
		electron_js_command => $electron_js_command,
		only_test_pattern => $only_test_pattern,
	);
	%matrix = ( %matrix, %marshal_matrix );
}

my $json = JSON::PP
	->new
	->utf8
	->pretty
	->canonical
	->encode( \%matrix );

_write_utf8( $output_path, $json );
print "Wrote $output_path\n";

exit 0;

sub _usage {
	return <<'USAGE';
Usage: perl t/ztests/generate-implementation-matrix-json.pl [options]

Options:
  --timeout <seconds>      Per-test timeout for each implementation.
  --output <path>          Output JSON file path.
  --perl-cmd <command>     Perl implementation command prefix.
  --rust-cmd <command>     Rust implementation command prefix.
  --js-cmd <command>       JavaScript command prefix.
  --electron-js-cmd <cmd>  Electron JavaScript command prefix.
  --only <regex>           Include only test paths matching regex.
  --jobs <N>               Number of worker processes (default 4).
  --no-marshal-interoperability
                            Skip synthetic std/marshal interop checks.
USAGE
}

sub _discover_ztest_files {
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

sub _prioritize_ztest_files {
	my (%args) = @_;
	my @ztest_files = @{ $args{ztest_files} };
	my $repo_root = $args{repo_root};
	my $matrix_path = $args{matrix_path};

	my $matrix = _load_existing_matrix($matrix_path);
	return @ztest_files if not defined $matrix;

	my @slow;
	my @fast;

	for my $test_path ( @ztest_files ) {
		my $rel_test_path = File::Spec->abs2rel( $test_path, $repo_root );
		$rel_test_path =~ s{\\}{/}g;

		if ( _test_is_priority( $matrix->{$rel_test_path} ) ) {
			push @slow, $test_path;
			next;
		}

		push @fast, $test_path;
	}

	return ( @slow, @fast );
}

sub _load_existing_matrix {
	my ($matrix_path) = @_;
	return if not defined $matrix_path;
	return if not -f $matrix_path;

	my $matrix_json = eval { _read_utf8($matrix_path) };
	return if not defined $matrix_json;

	my $matrix = eval { JSON::PP->new->decode($matrix_json) };
	return if not defined $matrix;
	return if ref($matrix) ne 'HASH';

	return $matrix;
}

sub _test_is_priority {
	my ($test_result) = @_;
	return 0 if ref($test_result) ne 'HASH';

	for my $impl_result ( values %{$test_result} ) {
		next if ref($impl_result) ne 'HASH';
		return 1 if _impl_result_is_priority($impl_result);
	}

	return 0;
}

sub _impl_result_is_priority {
	my ($impl_result) = @_;

	if (
		defined $impl_result->{status}
		and $impl_result->{status} eq 'hard_fail'
	) {
		return 1;
	}

	if (
		defined $impl_result->{elapsed}
		and $impl_result->{elapsed} =~ /\A[0-9]+(?:\.[0-9]+)?\z/
		and $impl_result->{elapsed} > 10
	) {
		return 1;
	}

	return 0;
}

sub _evaluate_impl {
	my ( $repo_root, $timeout_seconds, $command_prefix, $test_path, $name, $worker_ix ) = @_;
	my @cmd = ( 'bash', '-lc', $command_prefix . ' ' . _shell_quote($test_path) . ' 2>&1' );

	my $result = _run_with_timeout( 
		cmd => \@cmd,
		cwd => $repo_root,
		timeout_seconds => $timeout_seconds,
	);

	if ( $result->{timed_out} ) {
		return {
			status => 'hard_fail',
			reason => "timeout >${timeout_seconds}s",
			output => $result->{stdout},
		};
	}

	my $tap_assessment = _assess_tap( $result->{stdout} );
	my $status = $tap_assessment->{status};
	my $reason = $tap_assessment->{reason};

	if ( $result->{exit_code} != 0 ) {
		$status = 'hard_fail';
		$reason = 'exit ' . $result->{exit_code};
	}
	
	my %emoji = (
		pass      => '✅',
		soft_fail => '🟡',
		hard_fail => '❌',
	);

	my $test_path_clean = Path::Tiny->new($test_path)->realpath->relative;
	printf "[%02d] %-12s %s  %-48s (%s; %0.3fs)\n", $worker_ix + 1, $name, $emoji{$status}, $test_path_clean, $reason, $result->{elapsed};

	return {
		status   => $status,
		reason   => $reason,
		output   => $result->{stdout},
		started  => $result->{started},
		finished => $result->{finished},
		elapsed  => $result->{elapsed},
	};
}

sub _build_matrix_parallel {
	my (%args) = @_;
	my $repo_root = $args{repo_root};
	my $timeout_seconds = $args{timeout_seconds};
	my $perl_command = $args{perl_command};
	my $rust_command = $args{rust_command};
	my $js_command = $args{js_command};
	my $electron_js_command = $args{electron_js_command};
	my @ztest_files = @{ $args{ztest_files} };
	my $jobs = $args{jobs};

	my $worker_count = $jobs;
	if ( $worker_count > scalar @ztest_files ) {
		$worker_count = scalar @ztest_files;
	}

	my $tmp_dir = tempdir( 'matrix-workers-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
	my @worker_pids;
	my @task_writers;
	my @ready_readers;
	my %worker_by_fileno;

	for my $worker_index ( 0 .. $worker_count - 1 ) {
		pipe( my $task_reader, my $task_writer )
			or die "task pipe for worker $worker_index: $!";
		pipe( my $ready_reader, my $ready_writer )
			or die "ready pipe for worker $worker_index: $!";

		my $pid = fork();
		defined $pid or die "Could not fork worker $worker_index: $!";

		if ( $pid == 0 ) {
			# Child
			close $task_writer;
			close $ready_reader;
			my %worker_matrix;

			{
				my $old_sel = select($ready_writer);
				$| = 1;
				select($old_sel);
			}

			while (1) {
				print {$ready_writer} "READY\n"
					or die "Could not notify parent from worker $worker_index: $!";

				my $test_path = <$task_reader>;
				last if not defined $test_path;
				chomp $test_path;
				next if not defined $test_path or $test_path eq '';

				my $rel_test_path = File::Spec->abs2rel( $test_path, $repo_root );
				$rel_test_path =~ s{\\}{/}g;

				my %test_results = (
					'Perl' => _evaluate_impl(
						$repo_root,
						$timeout_seconds,
						$perl_command,
						$test_path,
						'Perl',
						$worker_index,
					),
					'Rust' => _evaluate_impl(
						$repo_root,
						$timeout_seconds,
						$rust_command,
						$test_path,
						'Rust',
						$worker_index,
					),
					'JS/Node' => _evaluate_impl(
						$repo_root,
						$timeout_seconds,
						$js_command,
						$test_path,
						'JS/Node',
						$worker_index,
					),
					'JS/Electron' => _evaluate_impl(
						$repo_root,
						$timeout_seconds,
						$electron_js_command,
						$test_path,
						'JS/Electron',
						$worker_index,
					),
				);
				$worker_matrix{$rel_test_path} = \%test_results;
			}

			close $task_reader;
			close $ready_writer;

			my $worker_path = File::Spec->catfile( $tmp_dir, "worker-$worker_index.json" );
			my $worker_json = JSON::PP
				->new
				->utf8
				->canonical
				->encode( \%worker_matrix );
			_write_utf8( $worker_path, $worker_json );
			exit 0;
		}

		push @worker_pids, $pid;
		push @task_writers, $task_writer;
		push @ready_readers, $ready_reader;
		$worker_by_fileno{ fileno($ready_reader) } = $worker_index;

		close $task_reader;
		close $ready_writer;

		{
			my $old_sel = select($task_writer);
			$| = 1;
			select($old_sel);
		}
	}

	my $ready_select = IO::Select->new(@ready_readers);
	my @pending_tests = @ztest_files;
	my %worker_closed;

	while ( $ready_select->count ) {
		for my $fh ( $ready_select->can_read ) {
			my $worker_index = $worker_by_fileno{ fileno($fh) };
			my $message = <$fh>;

			if ( not defined $message ) {
				$ready_select->remove($fh);
				close $fh;
				next;
			}

			chomp $message;
			next if $message ne 'READY';

			if ( @pending_tests ) {
				my $test_path = shift @pending_tests;
				print { $task_writers[$worker_index] } $test_path, "\n"
					or die "Could not send work to worker $worker_index: $!";
				next;
			}

			next if $worker_closed{$worker_index}++;
			close $task_writers[$worker_index];
			$ready_select->remove($fh);
			close $fh;
		}
	}

	for my $pid ( @worker_pids ) {
		my $waited = waitpid( $pid, 0 );
		if ( $waited <= 0 ) {
			die "waitpid failed for worker pid $pid: $!";
		}
		my $exit_code = $? >> 8;
		if ( $exit_code != 0 ) {
			die "worker pid $pid exited with status $exit_code";
		}
	}

	my %matrix;
	for my $worker_index ( 0 .. $worker_count - 1 ) {
		my $worker_path = File::Spec->catfile( $tmp_dir, "worker-$worker_index.json" );
		my $worker_json = _read_utf8($worker_path);
		my $worker_data = JSON::PP->new->decode($worker_json);
		%matrix = ( %matrix, %{$worker_data} );
	}

	return %matrix;
}

sub _marshal_interop_selected {
	my ($only_test_pattern) = @_;
	return 1 if not defined $only_test_pattern;

	for my $name ( _marshal_interop_test_names() ) {
		return 1 if $name =~ /$only_test_pattern/;
	}

	return 0;
}

sub _marshal_interop_test_names {
	my @names;

	for my $dump_impl (qw( perl rust js-node )) {
		for my $fixture ( _marshal_positive_fixture_names() ) {
			push @names,
				"t/ztests/marshall-interop/$dump_impl-dump/$fixture.zzs";
		}
	}

	for my $fixture ( @{ _marshal_weak_fixtures()->{fixtures} || [] } ) {
		next if ref($fixture) ne 'HASH';
		next if not defined $fixture->{name};
		push @names,
			"t/ztests/marshall-interop/weak-records/$fixture->{name}.zzs";
	}

	for my $fixture ( @{ _marshal_malformed_fixtures() } ) {
		push @names,
			"t/ztests/marshall-interop/malformed/$fixture->{name}.zzs";
	}

	return @names;
}

sub _marshal_positive_fixture_names {
	return qw(
		scalar-null
		array-cycle
		dict-pairlist
		time-path
		function
		class
		trait
		object-instance
		worker-payload-plain
		worker-payload-result
	);
}

sub _build_marshal_interop_matrix {
	my (%args) = @_;
	my $repo_root = $args{repo_root};
	my $timeout_seconds = $args{timeout_seconds};
	my $only_test_pattern = $args{only_test_pattern};
	my %dump_commands = (
		'perl' => {
			display => 'Perl',
			command => $args{perl_command},
		},
		'rust' => {
			display => 'Rust',
			command => $args{rust_command},
		},
		'js-node' => {
			display => 'JS/Node',
			command => $args{js_command},
		},
	);
	my %load_commands = (
		'Perl' => $args{perl_command},
		'Rust' => $args{rust_command},
		'JS/Node' => $args{js_command},
		'JS/Electron' => $args{electron_js_command},
	);
	my $tmp_dir = tempdir( 'marshal-interop-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
	my %matrix;

	for my $dump_slug (qw( perl rust js-node )) {
		for my $fixture_name ( _marshal_positive_fixture_names() ) {
			my $test_name =
				"t/ztests/marshall-interop/$dump_slug-dump/$fixture_name.zzs";
			next if defined $only_test_pattern and $test_name !~ /$only_test_pattern/;

			my $blob_result = $dump_slug eq 'perl'
				&& _marshal_fixture_has_golden($fixture_name)
				? _marshal_golden_blob( $repo_root, $fixture_name )
				: _marshal_generate_blob(
					repo_root => $repo_root,
					timeout_seconds => $timeout_seconds,
					command_prefix => $dump_commands{$dump_slug}{command},
					fixture_name => $fixture_name,
					tmp_dir => $tmp_dir,
				);

			my %results;
			for my $loader (qw( Perl Rust JS/Node JS/Electron )) {
				if ( $blob_result->{status} ne 'pass' ) {
					$results{$loader} = {
						status => 'hard_fail',
						reason => "$dump_commands{$dump_slug}{display} dump failed",
						output => $blob_result->{output} // '',
						started => $blob_result->{started},
						finished => $blob_result->{finished},
						elapsed => $blob_result->{elapsed} // 0,
					};
					next;
				}

				$results{$loader} = _evaluate_marshal_source(
					repo_root => $repo_root,
					timeout_seconds => $timeout_seconds,
					command_prefix => $load_commands{$loader},
					source => _marshal_positive_load_source(
						$fixture_name,
						$blob_result->{blob},
					),
					name => "$dump_commands{$dump_slug}{display} dump -> $loader load",
					test_name => $test_name,
					tmp_dir => $tmp_dir,
				);
			}
			$results{'JS/Browser'} = _marshal_browser_skip_result();

			$matrix{$test_name} = \%results;
		}
	}

	for my $fixture ( @{ _marshal_weak_fixtures()->{fixtures} || [] } ) {
		next if ref($fixture) ne 'HASH';
		next if not defined $fixture->{name};

		my $test_name =
			"t/ztests/marshall-interop/weak-records/$fixture->{name}.zzs";
		next if defined $only_test_pattern and $test_name !~ /$only_test_pattern/;

		my %results;
		for my $loader (qw( Perl Rust JS/Node JS/Electron )) {
			$results{$loader} = _evaluate_marshal_source(
				repo_root => $repo_root,
				timeout_seconds => $timeout_seconds,
				command_prefix => $load_commands{$loader},
				source => _marshal_weak_load_source($fixture),
				name => "weak fixture -> $loader load",
				test_name => $test_name,
				tmp_dir => $tmp_dir,
			);
		}
		$results{'JS/Browser'} = _marshal_browser_skip_result();
		$matrix{$test_name} = \%results;
	}

	for my $fixture ( @{ _marshal_malformed_fixtures() } ) {
		my $test_name =
			"t/ztests/marshall-interop/malformed/$fixture->{name}.zzs";
		next if defined $only_test_pattern and $test_name !~ /$only_test_pattern/;

		my %results;
		for my $loader (qw( Perl Rust JS/Node JS/Electron )) {
			$results{$loader} = _evaluate_marshal_source(
				repo_root => $repo_root,
				timeout_seconds => $timeout_seconds,
				command_prefix => $load_commands{$loader},
				source => _marshal_malformed_load_source($fixture),
				name => "malformed fixture -> $loader load",
				test_name => $test_name,
				tmp_dir => $tmp_dir,
			);
		}
		$results{'JS/Browser'} = _marshal_browser_skip_result();
		$matrix{$test_name} = \%results;
	}

	return %matrix;
}

sub _marshal_browser_skip_result {
	my $now = _iso8601_utc_now();
	return {
		status => 'soft_fail',
		reason => 'skip: marshal interoperability is covered by CLI runtimes',
		output => "1..0 # SKIP marshal interoperability is covered by CLI runtimes\n",
		started => $now,
		finished => $now,
		elapsed => 0,
	};
}

sub _marshal_golden_blob {
	my ( $repo_root, $fixture_name ) = @_;
	my $path = File::Spec->catfile(
		$repo_root,
		't',
		'fixtures',
		'marshal',
		'golden',
		"$fixture_name.b64",
	);
	my $started = _iso8601_utc_now();
	my $started_ts = time();
	my $blob = eval { _read_utf8($path) };
	if ( not defined $blob ) {
		return {
			status => 'hard_fail',
			reason => "missing golden fixture $fixture_name",
			output => $@ || '',
			started => $started,
			finished => _iso8601_utc_now(),
			elapsed => time() - $started_ts,
		};
	}
	$blob =~ s/\s+\z//;
	return {
		status => 'pass',
		blob => $blob,
		output => "$blob\n",
		started => $started,
		finished => _iso8601_utc_now(),
		elapsed => time() - $started_ts,
	};
}

sub _marshal_generate_blob {
	my (%args) = @_;
	my $fixture_name = $args{fixture_name};
	my $body = _marshal_fixture_body($fixture_name);
	my $source = <<~"ZUZU";
		from std/marshal import dump;
		from std/string/base64 import encode;
		$body
		say( encode( dump(fixture_value) ) );
		ZUZU

	my $result = _run_marshal_source(
		repo_root => $args{repo_root},
		timeout_seconds => $args{timeout_seconds},
		command_prefix => $args{command_prefix},
		source => $source,
		tmp_dir => $args{tmp_dir},
		name => "$fixture_name-dump",
	);
	my $blob = $result->{stdout};
	$blob =~ s/\s+\z// if defined $blob;
	if (
		$result->{exit_code} != 0
		or not defined $blob
		or $blob !~ /\A[A-Za-z0-9+\/=]+\z/
	) {
		return {
			status => 'hard_fail',
			reason => $result->{timed_out}
				? "timeout >$args{timeout_seconds}s"
				: 'dump did not emit base64',
			output => $result->{stdout},
			started => $result->{started},
			finished => $result->{finished},
			elapsed => $result->{elapsed},
		};
	}

	return {
		status => 'pass',
		blob => $blob,
		output => $result->{stdout},
		started => $result->{started},
		finished => $result->{finished},
		elapsed => $result->{elapsed},
	};
}

sub _marshal_fixture_has_golden {
	my ($fixture_name) = @_;
	my %golden = map { $_ => 1 } qw(
		scalar-null
		array-cycle
		dict-pairlist
		time-path
		function
		class
		trait
		object-instance
	);
	return $golden{$fixture_name} ? 1 : 0;
}

sub _marshal_fixture_body {
	my ($fixture_name) = @_;
	my %bodies = (
		'scalar-null' => q{
			let fixture_value := null;
		},
		'array-cycle' => q{
			let fixture_value := [];
			fixture_value.push(fixture_value);
		},
		'dict-pairlist' => q{
			let fixture_value := [
				{ beta: 2, alpha: 1 },
				{{ foo: 1, bar: 2, foo: 3 }},
			];
		},
		'time-path' => q{
			from std/time import Time;
			from std/io import Path;
			let fixture_value := [
				new Time(12345),
				new Path("tmp/../file.txt"),
			];
		},
		'function' => q{
			function add_one (x) {
				return x + 1;
			}
			let fixture_value := add_one;
		},
		'class' => q{
			const offset := 40;
			class GoldenPoint {
				let Number x := 1;

				method total (Number y) -> Number {
					return x + y + offset;
				}
			}
			let fixture_value := GoldenPoint;
		},
		'trait' => q{
			const prefix := "label:";
			trait GoldenLabelled {
				method label () -> String {
					return prefix _ self.get_name();
				}
			}
			let fixture_value := GoldenLabelled;
		},
		'object-instance' => q{
			class GoldenBox {
				let String name with get, set := "unset";
				const kind := "box";

				method label () {
					return name _ ":" _ kind;
				}
			}
			let fixture_value := new GoldenBox( name: "Ada" );
		},
		'worker-payload-plain' => q{
			function marshal_worker_add ( x, y ) {
				return x + y;
			}

			trait MarshalWorkerLabelled {
				method label () {
					return "box:" _ self.get_name();
				}
			}

			class MarshalWorkerBox with MarshalWorkerLabelled {
				let String name with get, set := "unset";
			}

			let fixture_value := {
				callable: marshal_worker_add,
				args: [ 20, 22 ],
				returned: {
					scalar: "plain",
					collection: [ 1, { name: "Ada" } ],
					object: new MarshalWorkerBox( name: "Ada" ),
					class: MarshalWorkerBox,
					trait: MarshalWorkerLabelled,
				},
			};
		},
		'worker-payload-result' => q{
			from std/result import Result;

			let fixture_value := {
				ok: Result.ok(42),
				err: Result.err("worker-boom"),
			};
		},
	);
	die "Unknown marshal fixture '$fixture_name'\n"
		if not exists $bodies{$fixture_name};
	return $bodies{$fixture_name};
}

sub _marshal_positive_load_source {
	my ( $fixture_name, $blob ) = @_;
	my %checks = (
		'scalar-null' => [
			'v == null',
			'null root loads',
		],
		'array-cycle' => [
			'typeof v == "Array"',
			'Array root loads',
			'ref_id(v) == ref_id(v[0])',
			'Array cycle is preserved',
		],
		'dict-pairlist' => [
			'v[0]{alpha} == 1',
			'Dict item loads',
			'v[1].get_all("foo") == [ 1, 3 ]',
			'PairList duplicate keys load',
		],
		'time-path' => [
			'v[0].epoch() == 12345',
			'Time item loads',
			'v[1].to_String() == "tmp/../file.txt"',
			'Path item loads',
		],
		'function' => [
			'typeof v == "Function"',
			'Function root loads',
			'v(41) == 42',
			'Function executes after load',
		],
		'class' => [
			'typeof v == "Class"',
			'Class root loads',
			'( new v( x: 1 ) ).total(1) == 42',
			'Class method executes after load',
		],
		'trait' => [
			'v != null',
			'Trait root loads as a usable value',
			'( new MarshalInteropTraitUser() ).label() == "label:Bea"',
			'Trait method composes after load',
		],
		'object-instance' => [
			'typeof v == "GoldenBox"',
			'Object instance root loads',
			'v.label() == "Ada:box"',
			'Object instance method executes after load',
		],
		'worker-payload-plain' => [
			'v{callable}( v{args}[0], v{args}[1] ) == 42',
			'Worker callable payload executes after load',
			'v{returned}{scalar} == "plain"',
			'Worker scalar return payload loads',
			'v{returned}{collection}[1]{name} == "Ada"',
			'Worker collection return payload loads',
			'typeof v{returned}{object} == "MarshalWorkerBox"',
			'Worker object return payload loads',
			'v{returned}{object}.label() == "box:Ada"',
			'Worker object method executes after load',
			'typeof v{returned}{class} == "Class"',
			'Worker class return payload loads',
			'( new v{returned}{class}( name: "Bea" ) ).label() == "box:Bea"',
			'Worker class payload constructs usable objects',
			'v{returned}{trait} != null',
			'Worker trait return payload loads',
		],
		'worker-payload-result' => [
			'typeof v{ok} == "Result"',
			'Result.ok worker payload loads',
			'v{ok}.unwrap() == 42',
			'Result.ok worker payload unwraps',
			'typeof v{err} == "Result"',
			'Result.err worker payload loads',
			'v{err}.unwrap_err() == "worker-boom"',
			'Result.err worker payload unwrap_err works',
		],
	);
	my @pairs = @{ $checks{$fixture_name} };
	my $plan = @pairs / 2;
	my $trait_setup = $fixture_name eq 'trait'
		? <<'ZUZU'
class MarshalInteropTraitUser with v {
	let String name with get := "Bea";
}
ZUZU
		: '';
	my @test_lines;
	for ( my $i = 0; $i < @pairs; $i += 2 ) {
		my $number = ( $i / 2 ) + 1;
		my $expr = $pairs[$i];
		my $label = $pairs[ $i + 1 ];
		push @test_lines,
			qq{if ( $expr ) { say("ok $number - $label"); }\n}
			. qq{else { say("not ok $number - $label"); }};
	}
	my $tests = join "\n", @test_lines;

	return <<~"ZUZU";
		from std/marshal import load;
		from std/string/base64 import decode;
		from std/internals import ref_id;

		let v := load( decode("$blob") );
		$trait_setup
		say("1..$plan");
		$tests
		ZUZU
}

sub _marshal_weak_fixtures {
	return $_marshal_weak_fixtures if defined $_marshal_weak_fixtures;

	my $path = File::Spec->catfile(
		$repo_root,
		't',
		'fixtures',
		'marshal',
		'weak-records.json',
	);
	$_marshal_weak_fixtures = JSON::PP->new->decode( _read_utf8($path) );
	return $_marshal_weak_fixtures;
}

sub _marshal_weak_load_source {
	my ($fixture) = @_;
	my $name = $fixture->{name};
	my $blob = $fixture->{base64};
	my $expect = $fixture->{expect} || 'reject';

	if ( $expect eq 'loads' ) {
		return <<~"ZUZU";
			from std/marshal import load;
			from std/string/base64 import decode;

			load( decode("$blob") );
			say("1..1");
			say("ok 1 - $name loads");
			ZUZU
	}

	return <<~"ZUZU";
		from std/marshal import load, UnmarshallingException;
		from std/string/base64 import decode;

		say("1..1");
		try {
			load( decode("$blob") );
			say("not ok 1 - $name rejects reserved weak storage");
		}
		catch ( UnmarshallingException e ) {
			say("ok 1 - $name rejects reserved weak storage");
		}
		ZUZU
}

sub _marshal_malformed_fixtures {
	return $_marshal_malformed_fixtures
		if defined $_marshal_malformed_fixtures;

	$_marshal_malformed_fixtures = [
		{
			name => 'invalid-cbor-trailing-bytes',
			base64 => '9gA=',
			description => 'CBOR null followed by trailing bytes.',
		},
		{
			name => 'wrong-envelope-magic',
			base64 => '2dn3hnBOT1QtWlVaVS1NQVJTSEFMAaD2gIA=',
			description => 'Envelope magic string is not ZUZU-MARSHAL.',
		},
		{
			name => 'wrong-envelope-arity',
			base64 => '2dn3hWxaVVpVLU1BUlNIQUwBoPaA',
			description => 'Envelope array has the wrong number of fields.',
		},
		{
			name => 'wrong-envelope-options',
			base64 => '2dn3hmxaVVpVLU1BUlNIQUwBgPaAgA==',
			description => 'Envelope options field is not a map.',
		},
		{
			name => 'wrong-version',
			base64 => '2dn3hmxaVVpVLU1BUlNIQUwCoPaAgA==',
			description => 'Envelope uses unsupported version 2.',
		},
		{
			name => 'invalid-object-reference',
			base64 => '2dn3hmxaVVpVLU1BUlNIQUwBoIIAAYGCAoCA',
			description => 'Root references an object id outside the table.',
		},
		{
			name => 'unsupported-object-kind',
			base64 => '2dn3hmxaVVpVLU1BUlNIQUwBoIIAAIGCGGOAgA==',
			description => 'Object table contains unsupported kind 99.',
		},
		{
			name => 'duplicate-dict-keys',
			base64 => '2dn3hmxaVVpVLU1BUlNIQUwBoIIAAIGCA4KCY2R1cAGCY2R1cAKA',
			description => 'Dict payload contains duplicate string keys.',
		},
		{
			name => 'duplicate-slot-names',
			base64 => '2dn3hmxaVVpVLU1BUlNIQUwBoIIAAIKCB4KCAAGCgmF4AYJheAKCCYEAgYUCbU1hcnNoYWxCYWRCb3h4P2NsYXNzIE1hcnNoYWxCYWRCb3ggeyBsZXQgeDsgbWV0aG9kIGxhYmVsICgpIHsgcmV0dXJuICJvayI7IH0gfYCA',
			description => 'Object instance payload contains duplicate slots.',
		},
		{
			name => 'invalid-code-reference',
			base64 => '2dn3hmxaVVpVLU1BUlNIQUwBoIIAAIGCCIEBgA==',
			description => 'Function object references a missing code id.',
		},
		{
			name => 'unsupported-code-kind',
			base64 => '2dn3hmxaVVpVLU1BUlNIQUwBoPaAgYUYY25tYXJzaGFsX2JhZF9mbngZZnVuY3Rpb24gKCkgeyByZXR1cm4gMTsgfYCA',
			description => 'Code table contains unsupported kind 99.',
		},
		{
			name => 'invalid-code-dependency',
			base64 => '2dn3hmxaVVpVLU1BUlNIQUwBoPaAgYUCbU1hcnNoYWxCYWRCb3h4P2NsYXNzIE1hcnNoYWxCYWRCb3ggeyBsZXQgeDsgbWV0aG9kIGxhYmVsICgpIHsgcmV0dXJuICJvayI7IH0gfYCBggAB',
			description => 'Code table contains an invalid internal dependency.',
		},
		{
			name => 'malformed-code-capture',
			base64 => '2dn3hmxaVVpVLU1BUlNIQUwBoIIAAIGCCIEAgYUBbm1hcnNoYWxfYmFkX2ZueBlmdW5jdGlvbiAoKSB7IHJldHVybiAxOyB9gYNjY2FwAQKA',
			description => 'Code table contains a malformed capture record.',
		},
	];
	return $_marshal_malformed_fixtures;
}

sub _marshal_malformed_load_source {
	my ($fixture) = @_;
	my $name = $fixture->{name};
	my $blob = $fixture->{base64};

	return <<~"ZUZU";
		from std/marshal import load, UnmarshallingException;
		from std/string/base64 import decode;

		say("1..1");
		try {
			load( decode("$blob") );
			say("not ok 1 - $name rejects malformed marshal blob");
		}
		catch ( UnmarshallingException e ) {
			say("ok 1 - $name rejects malformed marshal blob");
		}
		ZUZU
}

sub _evaluate_marshal_source {
	my (%args) = @_;
	my $result = _run_marshal_source(%args);

	if ( $result->{timed_out} ) {
		return {
			status => 'hard_fail',
			reason => "timeout >$args{timeout_seconds}s",
			output => $result->{stdout},
			started => $result->{started},
			finished => $result->{finished},
			elapsed => $result->{elapsed},
		};
	}

	my $tap_assessment = _assess_tap( $result->{stdout} );
	my $status = $tap_assessment->{status};
	my $reason = $tap_assessment->{reason};

	if ( $result->{exit_code} != 0 ) {
		$status = 'hard_fail';
		$reason = 'exit ' . $result->{exit_code};
	}

	my %emoji = (
		pass      => '✅',
		soft_fail => '🟡',
		hard_fail => '❌',
	);
	printf "[marshal] %-32s %s  %-72s (%s; %0.3fs)\n",
		$args{name},
		$emoji{$status},
		$args{test_name},
		$reason,
		$result->{elapsed};

	return {
		status   => $status,
		reason   => $reason,
		output   => $result->{stdout},
		started  => $result->{started},
		finished => $result->{finished},
		elapsed  => $result->{elapsed},
	};
}

sub _run_marshal_source {
	my (%args) = @_;
	my $tmp_dir = $args{tmp_dir};
	my $name = $args{name} || 'marshal-interoperability';
	my $safe_name = $name;
	$safe_name =~ s{[^A-Za-z0-9_.-]+}{-}g;
	my $path = File::Spec->catfile(
		$tmp_dir,
		$safe_name . '-' . int( rand(1_000_000_000) ) . '.zzs',
	);
	_write_utf8( $path, $args{source} );

	my @cmd = (
		'bash',
		'-lc',
		$args{command_prefix} . ' ' . _shell_quote($path) . ' 2>&1',
	);
	return _run_with_timeout(
		cmd => \@cmd,
		cwd => $args{repo_root},
		timeout_seconds => $args{timeout_seconds},
	);
}

sub _assess_tap {
	my ($stdout) = @_;

	if ( not defined $stdout or $stdout eq '' ) {
		return {
			status => 'hard_fail',
			reason => 'no TAP tests',
		};
	}

	my $tap_parser = eval {
		TAP::Parser->new( { source => \$stdout } );
	};
	if ( not defined $tap_parser ) {
		return {
			status => 'hard_fail',
			reason => 'invalid TAP',
		};
	}
	my @not_ok;
	my $tests_seen = 0;
	my $skip_all = 0;
	my $skip_reason = '';

	while ( my $result = $tap_parser->next ) {
		if ( $result->is_test ) {
			$tests_seen++;
			next if $result->is_ok;
			push @not_ok, $result;
			next;
		}
		if (
			$result->is_plan
			and $result->can('tests_planned')
			and $result->tests_planned == 0
			and $result->can('directive')
			and defined $result->directive
			and $result->directive eq 'SKIP'
		) {
			$skip_all = 1;
			if (
				$result->can('explanation')
				and defined $result->explanation
				and $result->explanation ne ''
			) {
				$skip_reason = $result->explanation;
			}
		}
	}

	if ( $tests_seen == 0 ) {
		if ($skip_all) {
			return {
				status => 'soft_fail',
				reason => $skip_reason ne '' ? "skip: $skip_reason" : 'skip',
			};
		}
		return {
			status => 'soft_fail',
			reason => 'no tests',
		};
	}

	if ( not $tap_parser->is_good_plan or $tap_parser->has_problems ) {
		return {
			status => 'hard_fail',
			reason => 'invalid TAP',
		};
	}

	if ( scalar @not_ok == 0 ) {
		return {
			status => 'pass',
			reason => 'ok',
		};
	}

	my $todo_or_skip_only = 1;
	for my $result ( @not_ok ) {
		my $directive = $result->directive;
		if ( not defined $directive ) {
			$todo_or_skip_only = 0;
			last;
		}
		if ( $directive ne 'TODO' and $directive ne 'SKIP' ) {
			$todo_or_skip_only = 0;
			last;
		}
	}

	if ($todo_or_skip_only) {
		return {
			status => 'soft_fail',
			reason => 'todo/skip in TAP',
		};
	}

	return {
		status => 'hard_fail',
		reason => 'not ok in TAP',
	};
}

sub _run_with_timeout {
	my (%args) = @_;
	my $cmd = $args{cmd};
	my $cwd = $args{cwd};
	my $timeout_seconds = $args{timeout_seconds};

	my $stdout = '';
	my $timed_out = 0;
	my $exit_code;
	my $old_cwd = File::Spec->rel2abs( File::Spec->curdir );

	if ( defined $cwd and $cwd ne '' ) {
		chdir $cwd or die "Could not chdir to $cwd: $!";
	}

	my $started = _iso8601_utc_now();
	my $started_ts = time();

	my $stderr = gensym;
	my $pid = open3( undef, my $stdout_fh, $stderr, @{$cmd} );

	eval {
		local $SIG{ALRM} = sub {
			die "TIMEOUT\n";
		};
		alarm $timeout_seconds;
		$stdout = do {
			local $/;
			<$stdout_fh>;
		};
		waitpid( $pid, 0 );
		alarm 0;
		1;
	} or do {
		my $error = $@;
		if ( defined $error and $error =~ /TIMEOUT/ ) {
			$timed_out = 1;
			kill 'TERM', $pid;
			waitpid( $pid, 0 );
		}
		else {
			die $error;
		}
	};

	if ( not $timed_out ) {
		$exit_code = $? >> 8;
	}
	else {
		$exit_code = 124;
	}

	chdir $old_cwd or die "Could not restore cwd to $old_cwd: $!";

	return {
		started   => $started,
		finished  => _iso8601_utc_now(),
		elapsed   => ( time() - $started_ts ),
		timed_out => $timed_out,
		exit_code => $exit_code,
		stdout    => defined $stdout ? $stdout : '',
	};
}

sub _iso8601_utc_now {
	return strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime );
}

sub _shell_quote {
	my ($value) = @_;
	$value =~ s/'/'"'"'/g;
	return "'$value'";
}

sub _write_utf8 {
	my ( $path, $content ) = @_;

	open my $fh, '>:encoding(UTF-8)', $path
		or die "Could not write $path: $!";
	print {$fh} $content;
	close $fh;

	return;
}

sub _read_utf8 {
	my ($path) = @_;

	open my $fh, '<:encoding(UTF-8)', $path
		or die "Could not read $path: $!";
	my $content = do {
		local $/;
		<$fh>;
	};
	close $fh;

	return $content;
}
