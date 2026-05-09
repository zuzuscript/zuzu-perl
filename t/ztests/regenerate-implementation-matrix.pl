#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use File::Basename qw( dirname );
use File::Spec;
use Getopt::Long qw( GetOptions );
use JSON::PP;
use List::Util qw( min );

use DateTime::Format::ISO8601;
my $iso = DateTime::Format::ISO8601->new;

my $repo_root = File::Spec->rel2abs(
	File::Spec->catdir( dirname(__FILE__), '..', '..' )
);

my $json_path = File::Spec->catfile(
	$repo_root,
	't',
	'ztests',
	'implementation-matrix.json',
);
my $browser_json_path = File::Spec->catfile(
	$repo_root,
	't',
	'ztests',
	'browser-implementation-matrix.json',
);
my $markdown_path = File::Spec->catfile(
	$repo_root,
	'docs',
	'zuzuscript-guide',
	'AE-implementation-test-status.md',
);

GetOptions(
	'matrix=s' => \$json_path,
	'browser-matrix=s' => \$browser_json_path,
	'output=s' => \$markdown_path,
) or die _usage();

my $raw_json = _slurp_utf8( $json_path );
my $matrix = JSON::PP->new->decode($raw_json);

if ( ref $matrix ne 'HASH' ) {
	die "Expected top-level object in $json_path\n";
}

if ( defined $browser_json_path and -f $browser_json_path ) {
	my $browser_raw_json = _slurp_utf8($browser_json_path);
	my $browser_matrix = JSON::PP->new->decode($browser_raw_json);
	if ( ref $browser_matrix ne 'HASH' ) {
		die "Expected top-level object in $browser_json_path\n";
	}
	_merge_matrix( $matrix, $browser_matrix );
}

my @implementations = _sorted_implementations($matrix);
my %summary_counts;
for my $impl ( @implementations ) {
	$summary_counts{$impl} = {
		pass => 0,
		soft_fail => 0,
		timeout => 0,
		hard_fail => 0,
	};
}

my @tests = sort keys %{$matrix};
my $marshal_interop_count = scalar grep {
	$_ =~ m{\At/ztests/marshall-interop/}
} @tests;
my @lines;
push @lines, '# Appendix E: Implementation Test Status';
push @lines, '';
push @lines, "The following table indicates how well each version of ZuzuScript implements the language's features and standard library.";
push @lines, '';
if ( $marshal_interop_count > 0 ) {
	push @lines, sprintf(
		'This table includes %d generated `std/marshal` interoperability result rows covering cross-runtime dump/load fixtures, reserved weak-record fixtures, and malformed-blob fixtures.',
		$marshal_interop_count,
	);
	push @lines, '';
}
push @lines, '| Test | ' . join( ' | ', @implementations ) . ' |';
push @lines, '| --- | ' . join( ' | ', map { '---' } @implementations ) . ' |';

for my $test_name ( @tests ) {
	my @row = ($test_name);
	
	for my $r ( values %{$matrix->{$test_name}} ) {
		$r->{elapsed} //= _calculate_elapsed($r);
	}
	
	my $fastest = min(
		map  { $matrix->{$test_name}{$_}{elapsed} }
		grep {
			ref $matrix->{$test_name}{$_} eq 'HASH'
				and defined $matrix->{$test_name}{$_}{status}
				and $matrix->{$test_name}{$_}{status} eq 'pass'
				and $_ ne 'JS/Browser'
		}
		@implementations
	);
	for my $impl ( @implementations ) {
		my $result = $matrix->{$test_name}{$impl};
		my $is_fastest = (
			ref $result eq 'HASH'
			and defined $fastest
			and defined $result->{elapsed}
			and $result->{elapsed} eq $fastest
			and $impl ne 'JS/Browser'
		);
		my $status_cell = _format_status_cell( $impl, $result, $is_fastest );
		push @row, $status_cell;

		my $bucket = _summary_bucket($result);
		$summary_counts{$impl}{$bucket}++;
	}

	push @lines, '| ' . join( ' | ', @row ) . ' |';
}

sub _calculate_elapsed {
	my $r = shift;
	$r->{started} and $r->{finished} or return 300;
	my $s = $iso->parse_datetime($r->{started});
	my $f = $iso->parse_datetime($r->{finished});
	my $duration = $f->subtract_datetime($s);
	return $duration->in_units('seconds');
}

push @lines, '';
push @lines, '## Summary counts';
push @lines, '';
push @lines, '| Implementation | Pass | Soft fail | Timeout | Hard fail |';
push @lines, '| --- | ---: | ---: | ---: | ---: |';

for my $impl ( @implementations ) {
	my $counts = $summary_counts{$impl};
	push @lines, sprintf(
		'| %s | %d | %d | %d | %d |',
		$impl,
		$counts->{pass},
		$counts->{soft_fail},
		$counts->{timeout},
		$counts->{hard_fail},
	);
}

my $markdown = join( "\n", @lines ) . "\n";
_write_utf8( $markdown_path, $markdown );

print "Wrote $markdown_path\n";

sub _sorted_implementations {
	return qw( Perl Rust JS/Node JS/Electron JS/Browser );
}

sub _merge_matrix {
	my ( $matrix, $extra_matrix ) = @_;

	for my $test_name ( keys %{$extra_matrix} ) {
		next if ref $extra_matrix->{$test_name} ne 'HASH';
		$matrix->{$test_name} //= {};
		for my $impl ( keys %{ $extra_matrix->{$test_name} } ) {
			$matrix->{$test_name}{$impl} = $extra_matrix->{$test_name}{$impl};
		}
	}

	return;
}

sub _format_status_cell {
	my ($impl, $result, $is_fastest) = @_;

	if ( ref $result ne 'HASH' ) {
		return qq{<span class="badge text-bg-danger" title="missing result">missing</span>};
	}

	my $status = $result->{status};
	my $reason = $result->{reason};

	$reason = 'no reason provided' if not defined $reason or $reason eq '';

	if ( defined $status and $status eq 'pass' ) {
		my $dot = sprintf(
			' <small title="%0.2f s">%s</small>',
			$result->{elapsed},
			$is_fastest ? '🔵' : '⚪',
		);
		$dot = '' if $impl eq 'JS/Browser';
		return qq{<span class="badge text-bg-success" title="$reason">pass$dot</span>};
	}

	if ( defined $status and $status eq 'soft_fail' ) {
		return qq{<span class="badge text-bg-warning" title="$reason">skip</span>};
	}
	
	if ( defined $reason and $reason =~ /^timeout/ ) {
		return qq{<span class="badge text-bg-info" title="$reason">time out</span>};
	}

	if ( defined $status and $status eq 'hard_fail' ) {
		return qq{<span class="badge text-bg-danger" title="$reason">fail</span>};
	}

	my $display_status = defined $status ? $status : 'unknown';
	return qq{<span class="badge text-bg-danger" title="unknown status: $display_status">fail</span>};
}

sub _summary_bucket {
	my ($result) = @_;

	return 'hard_fail' if ref $result ne 'HASH';

	my $status = $result->{status};
	return 'pass' if defined $status and $status eq 'pass';
	return 'soft_fail' if defined $status and $status eq 'soft_fail';
	return 'timeout' if defined $result->{reason} and $result->{reason} =~ /^timeout/;
	return 'hard_fail';
}

sub _usage {
	return <<'USAGE';
Usage: perl t/ztests/regenerate-implementation-matrix.pl [options]

Options:
  --matrix <path>          Main implementation matrix JSON.
  --browser-matrix <path>  Browser implementation matrix JSON to merge.
  --output <path>          Markdown output path.
USAGE
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

sub _write_utf8 {
	my ( $path, $content ) = @_;

	open my $fh, '>:encoding(UTF-8)', $path
		or die "Could not write $path: $!";
	print {$fh} $content;
	close $fh;

	return;
}
