package Zuzu::Tidy::CLI;

use utf8;
use strict;
use warnings;

use Getopt::Long qw(
	Configure
	GetOptionsFromArray
);

use Zuzu::Tidy;

sub run {
	my ( @argv ) = @_;
	@argv = @ARGV if not @argv;

	binmode *STDOUT, ':utf8';
	binmode *STDERR, ':utf8';

	my ( $options, $args, $error ) = _parse_options( \@argv );
	if ( defined $error ) {
		_print_usage($error);
		return 2;
	}

	my $file = shift @{ $args };
	if ( not defined $file or $file eq '' ) {
		_print_usage('Missing script path');
		return 2;
	}
	if ( @{ $args } ) {
		_print_usage('Too many arguments');
		return 2;
	}

	open my $in_fh, '<:encoding(UTF-8)', $file
		or die "Could not open '$file': $!\n";
	my $source = do { local $/; <$in_fh> };
	close $in_fh;

	my $tidied = Zuzu::Tidy->tidy( $source, filename => $file );

	if ( $options->{in_place} ) {
		open my $out_fh, '>:encoding(UTF-8)', $file
			or die "Could not write '$file': $!\n";
		print {$out_fh} $tidied;
		close $out_fh;
		return 0;
	}

	print $tidied;
	return 0;
}

sub _parse_options {
	my ( $argv ) = @_;

	my $options = {
		in_place => 0,
	};

	Configure(
		'no_ignore_case',
		'bundling',
	);
	my $ok = GetOptionsFromArray(
		$argv,
		'i|in-place' => \$options->{in_place},
		'h|help' => \$options->{help},
	);
	return ( undef, undef, undef ) if not $ok;

	if ( $options->{help} ) {
		return ( undef, undef, '' );
	}

	return ( $options, $argv, undef );
}

sub _print_usage {
	my ( $message ) = @_;

	if ( defined $message and $message ne '' ) {
		print STDERR $message, "\n";
	}
	print STDERR "Usage: zuzu-tidy.pl [--in-place] path/to/script.zzs\n";

	return;
}

=pod

=head1 NAME

Zuzu::Tidy::CLI - command-line wrapper for Zuzu::Tidy

=head1 SYNOPSIS

  zuzu-tidy.pl path/to/script.zzs
  zuzu-tidy.pl --in-place path/to/script.zzs

=head1 DESCRIPTION

Provides the executable interface for C<bin/zuzu-tidy.pl>. The command reads a
ZuzuScript file, formats it via C<Zuzu::Tidy>, and writes to STDOUT by
default or updates the file in-place with C<--in-place>.

=head1 METHODS

=head2 run

Parses CLI options, formats the target file, and returns a process exit code.

=cut

1;
