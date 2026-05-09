package Zuzu::Module::Log;

use utf8;

our $VERSION = '0.001';

use Time::HiRes qw( gettimeofday );

use Zuzu::Util::NativeHelpers qw(
	native_class
	native_function
	perl_to_zuzu
	zuzu_bool
	zuzu_to_perl
);

my %LEVELS = (
	debug => 10,
	info => 20,
	warn => 30,
	error => 40,
);

my $CURRENT_LEVEL = $LEVELS{info};
my $USE_TIMESTAMPS = 1;
my $ERROR_TO_STDERR = 1;

sub _normalize_level {
	my ( $raw ) = @_;

	my $name = lc( defined $raw ? "$raw" : 'info' );
	return exists $LEVELS{$name} ? $name : 'info';
}

sub _timestamp {
	my ( $sec, $usec ) = gettimeofday();
	my @tm = gmtime $sec;
	return sprintf(
		'%04d-%02d-%02dT%02d:%02d:%02d.%03dZ',
		$tm[5] + 1900,
		$tm[4] + 1,
		$tm[3],
		$tm[2],
		$tm[1],
		$tm[0],
		int( $usec / 1000 ),
	);
}

sub _emit {
	my ( $level, @parts ) = @_;

	my $numeric = $LEVELS{$level} // $LEVELS{info};
	return undef if $numeric < $CURRENT_LEVEL;

	my $line = join '', map { defined $_ ? "$_" : '' } @parts;
	my $prefix = uc $level;
	if ( $USE_TIMESTAMPS ) {
		$prefix = _timestamp() . ' ' . $prefix;
	}

	my $fh = ( $ERROR_TO_STDERR and $numeric >= $LEVELS{warn} )
		? *STDERR
		: *STDOUT;
	print {$fh} "$prefix $line\n";

	return undef;
}

sub IMPORT {
	my ( $class, $runtime ) = @_;

	my $log_class = native_class(
		name => 'Log',
	);

	$log_class->static_methods->{configure} = native_function(
		name => 'configure',
		native => sub {
			my ( $self, $options_raw ) = @_;
			my $options = zuzu_to_perl( $options_raw );
			if ( ref($options) eq 'HASH' ) {
				if ( exists $options->{level} ) {
					my $name = _normalize_level( $options->{level} );
					$CURRENT_LEVEL = $LEVELS{$name};
				}
				if ( exists $options->{timestamps} ) {
					$USE_TIMESTAMPS = zuzu_bool( $options->{timestamps}, 1 ) ? 1 : 0;
				}
				if ( exists $options->{stderr_for_errors} ) {
					$ERROR_TO_STDERR = zuzu_bool( $options->{stderr_for_errors}, 1 ) ? 1 : 0;
				}
			}
			return undef;
		},
	);

	$log_class->static_methods->{level} = native_function(
		name => 'level',
		native => sub {
			my ( $self ) = @_;
			for my $name ( sort CORE::keys %LEVELS ) {
				return $name if $LEVELS{$name} == $CURRENT_LEVEL;
			}
			return 'info';
		},
	);

	for my $name ( qw( debug info warn error ) ) {
		$log_class->static_methods->{$name} = native_function(
			name => $name,
			native => sub {
				my ( $self, @parts ) = @_;
				return _emit( $name, @parts );
			},
		);
	}

	$log_class->static_methods->{log} = native_function(
		name => 'log',
		native => sub {
			my ( $self, $level, @parts ) = @_;
			my $name = _normalize_level($level);
			return _emit( $name, @parts );
		},
	);

	return {
		Log => $log_class,
	};
}

1;
