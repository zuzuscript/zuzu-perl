package Zuzu::Module::Time;

use utf8;

our $VERSION = '0.001';

use Time::Piece ();

use Zuzu::Util::NativeHelpers qw(
	native_class
	native_function
	native_object
);

sub _wrap_time {
	my ( $class_obj, $tp_or_epoch ) = @_;
	my $epoch;
	if ( ref($tp_or_epoch) ) {
		$epoch = $tp_or_epoch->epoch;
	}
	else {
		$epoch = 0 + ( defined $tp_or_epoch ? $tp_or_epoch : 0 );
	}

	return native_object(
		class => $class_obj,
		slots => {
			_epoch => $epoch,
		},
		const => {
			_epoch => 1,
		},
	);
}

sub _epoch_from_self {
	my ( $self ) = @_;

	return $self->slots->{_epoch};
}

sub IMPORT {
	my ( $class, $runtime ) = @_;

	my $time_class = native_class(
		name => 'Time',
	);
	my $parser_class = native_class(
		name => 'TimeParser',
	);

	$time_class->native_constructor( sub {
		my ( $rt, $klass, $positional ) = @_;
		my $tp;
		if ( @{ $positional // [] } ) {
			my $epoch = $positional->[0];
			$epoch = 0 + ( defined $epoch ? $epoch : 0 );
			$tp = Time::Piece::localtime( $epoch );
		}
		else {
			$tp = Time::Piece::localtime();
		}

		return _wrap_time( $klass, $tp );
	} );

	for my $name (
		qw(
			sec
			min
			hour
			day_of_month
			mon
			month
			year
			yy
			day_of_week
			day
			day_of_year
			month_last_day
			hms
			ymd
			mdy
			dmy
			date
			time
			datetime
			cdate
			epoch
			tzoffset
			is_leap_year
			week
			week_year
			julian_day
			strftime
		)
	) {
		next if not Time::Piece->can( $name );
		$time_class->methods->{$name} = native_function(
			name => $name,
			native => sub {
				my ( $self, @args ) = @_;
				my $tp = Time::Piece::localtime( _epoch_from_self( $self ) );
				return $tp->$name( @args );
			},
		);
	}

	$time_class->methods->{to_String} = native_function(
		name => 'to_String',
			native => sub {
				my ( $self ) = @_;
				my $tp = Time::Piece::localtime( _epoch_from_self( $self ) );
				return $tp->datetime;
			},
		);

	$time_class->methods->{add_seconds} = native_function(
		name => 'add_seconds',
			native => sub {
				my ( $self, $seconds ) = @_;
				my $tp = Time::Piece::localtime( _epoch_from_self( $self ) );
				my $delta = 0 + ( defined $seconds ? $seconds : 0 );
				return _wrap_time( $time_class, $tp + $delta );
			},
	);

	$time_class->methods->{add_minutes} = native_function(
		name => 'add_minutes',
			native => sub {
				my ( $self, $minutes ) = @_;
				my $tp = Time::Piece::localtime( _epoch_from_self( $self ) );
				my $delta = 60 * ( 0 + ( defined $minutes ? $minutes : 0 ) );
				return _wrap_time( $time_class, $tp + $delta );
			},
	);

	$time_class->methods->{add_hours} = native_function(
		name => 'add_hours',
			native => sub {
				my ( $self, $hours ) = @_;
				my $tp = Time::Piece::localtime( _epoch_from_self( $self ) );
				my $delta = 60 * 60 * ( 0 + ( defined $hours ? $hours : 0 ) );
				return _wrap_time( $time_class, $tp + $delta );
			},
	);

	$time_class->methods->{add_days} = native_function(
		name => 'add_days',
			native => sub {
				my ( $self, $days ) = @_;
				my $tp = Time::Piece::localtime( _epoch_from_self( $self ) );
				my $delta = 24 * 60 * 60 * ( 0 + ( defined $days ? $days : 0 ) );
				return _wrap_time( $time_class, $tp + $delta );
			},
	);

	$time_class->methods->{add_weeks} = native_function(
		name => 'add_weeks',
			native => sub {
				my ( $self, $weeks ) = @_;
				my $tp = Time::Piece::localtime( _epoch_from_self( $self ) );
				my $delta = 7 * 24 * 60 * 60 * ( 0 + ( defined $weeks ? $weeks : 0 ) );
				return _wrap_time( $time_class, $tp + $delta );
			},
	);

	if ( Time::Piece->can( 'add_months' ) ) {
		$time_class->methods->{add_months} = native_function(
			name => 'add_months',
			native => sub {
				my ( $self, $months ) = @_;
				my $tp = Time::Piece::localtime( _epoch_from_self( $self ) );
				my $delta = 0 + ( defined $months ? $months : 0 );
				return _wrap_time( $time_class, $tp->add_months( $delta ) );
			},
		);
	}

	if ( Time::Piece->can( 'add_years' ) ) {
		$time_class->methods->{add_years} = native_function(
			name => 'add_years',
			native => sub {
				my ( $self, $years ) = @_;
				my $tp = Time::Piece::localtime( _epoch_from_self( $self ) );
				my $delta = 0 + ( defined $years ? $years : 0 );
				return _wrap_time( $time_class, $tp->add_years( $delta ) );
			},
		);
	}

	$parser_class->native_constructor( sub {
		my ( $rt, $klass, $positional ) = @_;
		my $format = @{ $positional // [] } ? $positional->[0] : '%Y-%m-%d';
		$format = defined $format ? "$format" : '%Y-%m-%d';

		return native_object(
			class => $klass,
			slots => {
				_format => $format,
			},
			const => {
				_format => 1,
			},
		);
	} );

	$parser_class->methods->{parse} = native_function(
		name => 'parse',
		native => sub {
			my ( $self, $raw ) = @_;
			my $value = defined $raw ? "$raw" : '';
			my $format = $self->slots->{_format};
			my $tp = Time::Piece->strptime( $value, $format );
			return _wrap_time( $time_class, $tp );
		},
	);

	return {
		Time => $time_class,
		TimeParser => $parser_class,
	};
}

1;

=pod

=head1 NAME

Zuzu::Module::Time - std/time bindings for ZuzuScript.

=head1 DESCRIPTION

Implements the C<std/time> module, exporting C<Time> and C<TimeParser>.

=head1 CLASSES

=head2 Time

Represents an instant stored internally as epoch seconds.

The constructor accepts an optional epoch value. When omitted, the
current local time is used.

Methods include component accessors, formatting helpers, and date/time
arithmetic (seconds, minutes, hours, days, weeks, and where supported,
months and years).

=head2 TimeParser

Parses strings using a C<strptime> format.

The constructor accepts an optional format string, defaulting to
C<%Y-%m-%d>.

Method:

=over

=item * C<parse(string)>

Returns a C<Time> object.

=back

=cut
