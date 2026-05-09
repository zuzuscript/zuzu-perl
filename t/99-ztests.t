use Test2::V0;

use File::Find qw( find );
use File::Spec;
use TAP::Parser;

use Zuzu::Parser;
use Zuzu::Runtime;
use Zuzu::Test::ZPathFacelessPortDiagnostics qw(
	format_summary_lines
	summarize_failed_queries
);

my $repo_root = File::Spec->rel2abs( File::Spec->catdir( File::Spec->curdir ) );
my $ztests_dir = File::Spec->catdir( $repo_root, 't', 'ztests' );
my @runtime_lib = (
	File::Spec->catdir( $repo_root, 't', 'modules' ),
	File::Spec->catdir( $repo_root, 'modules' ),
);

my @zzs_files;
find(
	{
		no_chdir => 1,
		wanted => sub {
			return if -d $_;
			return if $_ !~ /\.zzs\z/;
			push @zzs_files, $File::Find::name;
		},
	},
	$ztests_dir,
);
@zzs_files = sort @zzs_files;

ok scalar @zzs_files > 0, 'found at least one ztest script';

my $parser = Zuzu::Parser->new;

for my $ztest_path ( @zzs_files ) {
	my $display_name = File::Spec->abs2rel( $ztest_path, $repo_root );

	subtest $display_name => sub {
		my $source = _slurp_utf8( $ztest_path );
		ok defined $source, 'loaded ztest source';

		my $ast = eval { $parser->parse( $source, $ztest_path ) };
		if ( not defined $ast ) {
			fail 'parsed ztest source';
			diag $@;
			return;
		}
		pass 'parsed ztest source';

		my $runtime = Zuzu::Runtime->new( lib => [ @runtime_lib ] );
		my $tap_out = '';
		my $stderr_out = '';

		my $ran_ok = eval {
			local *STDOUT;
			local *STDERR;
			open STDOUT, '>:encoding(UTF-8)', \$tap_out
				or die "Could not capture STDOUT for $display_name: $!";
			open STDERR, '>:encoding(UTF-8)', \$stderr_out
				or die "Could not capture STDERR for $display_name: $!";
			$runtime->evaluate($ast);
			1;
		};

		if ( not $ran_ok ) {
			fail 'executed ztest script';
			diag $@;
			if ( length $stderr_out ) {
				diag "stderr from $display_name:";
				diag $stderr_out;
			}
			_emit_faceless_port_diagnostics(
				$display_name,
				{
					failed_queries => _failed_queries_from_tap_text( $tap_out ),
				},
			);
			return;
		}
		pass 'executed ztest script';

		if ( length $stderr_out ) {
			note "stderr from $display_name:";
			note $stderr_out;
		}

		my $tap_summary = _assert_valid_tap( $display_name, $tap_out );
		_emit_faceless_port_diagnostics( $display_name, $tap_summary );
	};
}

sub _assert_valid_tap {
	my ( $display_name, $tap_out ) = @_;

	my $tap_parser = TAP::Parser->new( { source => \$tap_out } );
	my $tests_seen = 0;
	my $skip_all = 0;
	my $skip_reason = '';
	my @failed_queries;

	while ( my $result = $tap_parser->next ) {
		if ( $result->is_test ) {
			$tests_seen++;
			my $desc = $result->description;
			$desc = "test " . $result->number if not defined $desc or $desc eq '';
			ok $result->is_ok, $desc;
			if ( not $result->is_ok and $desc =~ /\AQuery:\s*(.+)\z/ ) {
				push @failed_queries, $1;
			}
		}
		elsif ( $result->is_comment ) {
			if ( $result->as_string =~ /\A#\s*SKIP:\s*(.*)\z/ ) {
				$skip_reason = $1;
			}
			note $result->as_string;
		}
		elsif ( $result->is_plan ) {
			if (
				$result->can('tests_planned')
				and $result->tests_planned == 0
				and $result->can('directive')
				and defined $result->directive
				and $result->directive eq 'SKIP'
			) {
				$skip_all = 1;
				if (
					$skip_reason eq ''
					and $result->can('explanation')
					and defined $result->explanation
				) {
					$skip_reason = $result->explanation;
				}
			}
		}
		elsif ( $result->is_bailout ) {
			BAIL_OUT( "ztest bailed out ($display_name): " . $result->as_string );
		}
	}

	if ( $tests_seen == 0 and $skip_all and $skip_reason ne '' ) {
		SKIP: {
			skip "ztest skipped: $skip_reason", 1;
		}
	}
	else {
		ok( $tests_seen > 0, 'ztest produced TAP tests' );
	}
	ok( $tap_parser->is_good_plan, 'ztest TAP plan is valid' );
	my $has_problems = $tap_parser->has_problems ? 1 : 0;
	ok( $has_problems == 0, 'ztest TAP stream has no parser problems' );

	return {
		tests_seen => $tests_seen,
		failed_queries => \@failed_queries,
		has_problems => $has_problems,
		skip_all => $skip_all,
	};
}

sub _emit_faceless_port_diagnostics {
	my ( $display_name, $tap_summary ) = @_;

	return if $display_name ne 't/ztests/std/zpath-faceless-port.zzs';
	return if not defined $tap_summary;

	my $failed_queries = $tap_summary->{failed_queries};
	$failed_queries = [] if not defined $failed_queries;
	return if scalar @{ $failed_queries } == 0;

	diag 'zpath-faceless-port diagnostics:';
	diag 'failed query count: ' . scalar @{ $failed_queries };

	my $summary = summarize_failed_queries( $failed_queries );
	my $lines = format_summary_lines( $summary );
	for my $line ( @{ $lines } ) {
		diag '  ' . $line;
	}
}

sub _failed_queries_from_tap_text {
	my ( $tap_out ) = @_;

	return [] if not defined $tap_out or $tap_out eq '';

	my @failed_queries = ( $tap_out =~ /^not ok \d+ - Query:\s*(.+)$/mg );

	return \@failed_queries;
}

sub _slurp_utf8 {
	my ( $path ) = @_;

	open my $fh, '<:encoding(UTF-8)', $path
		or die "Could not open $path: $!";
	local $/;
	my $content = <$fh>;
	close $fh;

	return $content;
}

done_testing;
