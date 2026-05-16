package Zuzu::Module::Time;

use utf8;

our $VERSION = '0.001';

use DateTime ();
use DateTime::Lite ();
use DateTime::TimeZone ();
use POSIX qw( strftime );
use Time::Local qw( timegm );

use Zuzu::Error;
use Zuzu::Util::NativeHelpers qw(
	native_class
	native_function
	native_object
);

my @MONTH_ABBR = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
my @DAY_ABBR = qw( Mon Tue Wed Thu Fri Sat Sun );
my %MONTH_BY_NAME = (
	jan => 1, january => 1,
	feb => 2, february => 2,
	mar => 3, march => 3,
	apr => 4, april => 4,
	may => 5,
	jun => 6, june => 6,
	jul => 7, july => 7,
	aug => 8, august => 8,
	sep => 9, sept => 9, september => 9,
	oct => 10, october => 10,
	nov => 11, november => 11,
	dec => 12, december => 12,
);

sub _floor_epoch {
	my ( $epoch ) = @_;
	my $int = int($epoch);
	return $int - 1 if $epoch < 0 and $epoch != $int;
	return $int;
}

sub _fractional_part {
	my ( $epoch ) = @_;
	return $epoch - _floor_epoch($epoch);
}

sub _zone_name {
	my ( $value ) = @_;
	return 'UTC' if !defined $value;
	return $value->slots->{_name}
		if ref($value) and $value->can('slots')
		and exists $value->slots->{_name};
	my $name = "$value";
	return 'UTC' if $name eq '' or uc($name) eq 'Z';
	return 'UTC' if uc($name) eq 'GMT';
	return 'local' if lc($name) eq 'local';
	return $name;
}

sub _timezone {
	my ( $value ) = @_;
	my $name = _zone_name($value);
	return DateTime::TimeZone->new( name => $name );
}

sub _timezone_label {
	my ( $value ) = @_;
	return _timezone($value)->name;
}

sub _offset_to_zone {
	my ( $offset ) = @_;
	my $sign = $offset < 0 ? '-' : '+';
	$offset = abs($offset);
	return sprintf '%s%02d%02d',
		$sign,
		int( $offset / 3600 ),
		int( ( $offset % 3600 ) / 60 );
}

sub _parse_tz_offset {
	my ( $value ) = @_;
	return 0 if not defined $value or $value =~ /\A(?:UTC|GMT|Z)\z/i;
	return if $value !~ /\A([+-])(\d\d):?(\d\d)\z/;
	my ( $sign, $hours, $minutes ) = ( $1, $2, $3 );
	return if $hours > 23 or $minutes > 59;
	my $offset = $hours * 3600 + $minutes * 60;
	return $sign eq '-' ? -$offset : $offset;
}

sub _wrap_timezone {
	my ( $class_obj, $zone ) = @_;
	my $name = _timezone_label($zone);
	return native_object(
		class => $class_obj,
		slots => { _name => $name },
		const => { _name => 1 },
	);
}

sub _wrap_duration {
	my ( $class_obj, %parts ) = @_;
	return native_object(
		class => $class_obj,
		slots => {
			_years => 0 + ( $parts{years} // 0 ),
			_months => 0 + ( $parts{months} // 0 ),
			_weeks => 0 + ( $parts{weeks} // 0 ),
			_days => 0 + ( $parts{days} // 0 ),
			_hours => 0 + ( $parts{hours} // 0 ),
			_minutes => 0 + ( $parts{minutes} // 0 ),
			_seconds => 0 + ( $parts{seconds} // 0 ),
		},
		const => {
			_years => 1,
			_months => 1,
			_weeks => 1,
			_days => 1,
			_hours => 1,
			_minutes => 1,
			_seconds => 1,
		},
	);
}

sub _wrap_format {
	my ( $class_obj, %parts ) = @_;
	return native_object(
		class => $class_obj,
		slots => {
			_kind => $parts{kind} // 'strftime',
			_pattern => $parts{pattern} // '',
			_timezone => $parts{timezone},
		},
		const => {
			_kind => 1,
			_pattern => 1,
			_timezone => 1,
		},
	);
}

sub _wrap_time {
	my ( $class_obj, $epoch, $zone ) = @_;
	$epoch = $epoch->epoch + 0 if ref($epoch) and $epoch->can('epoch');
	return native_object(
		class => $class_obj,
		slots => {
			_epoch => 0 + ( defined $epoch ? $epoch : 0 ),
			_timezone => _timezone_label($zone),
		},
		const => {
			_epoch => 1,
			_timezone => 1,
		},
	);
}

sub _epoch_from_self { $_[0]->slots->{_epoch} }
sub _zone_from_self { $_[0]->slots->{_timezone} // 'UTC' }

sub _datetime_from_epoch {
	my ( $epoch, $zone ) = @_;
	return DateTime->from_epoch(
		epoch => $epoch,
		time_zone => _timezone($zone),
	);
}

sub _datetime_from_self {
	my ( $self ) = @_;
	return _datetime_from_epoch( _epoch_from_self($self), _zone_from_self($self) );
}

sub _same_wall_epoch {
	my ( $zone, %parts ) = @_;
	my $tz = _timezone($zone);
	my $frac = delete $parts{fraction} // 0;

	for my $minute_shift ( 0 .. 180 ) {
		my %try = %parts;
		if ( $minute_shift ) {
			my $base = timegm(
				$parts{second}, $parts{minute}, $parts{hour},
				$parts{day}, $parts{month} - 1, $parts{year}
			);
			my @utc = gmtime( $base + $minute_shift * 60 );
			@try{qw( second minute hour day month year )} =
				( $utc[0], $utc[1], $utc[2], $utc[3], $utc[4] + 1, $utc[5] + 1900 );
		}

		my $naive = timegm(
			$try{second}, $try{minute}, $try{hour},
			$try{day}, $try{month} - 1, $try{year}
		);
		my %offsets;
		for my $probe ( -172800, -86400, -3600, 0, 3600, 86400, 172800 ) {
			$offsets{ $tz->offset_for_datetime(
				DateTime->from_epoch( epoch => $naive + $probe, time_zone => 'UTC' )
			) } = 1;
		}
		my @epochs;
		for my $offset ( keys %offsets ) {
			my $candidate = $naive - $offset;
			my $dt = DateTime->from_epoch( epoch => $candidate, time_zone => $tz );
			push @epochs, $candidate
				if $dt->year == $try{year}
				and $dt->month == $try{month}
				and $dt->day == $try{day}
				and $dt->hour == $try{hour}
				and $dt->minute == $try{minute}
				and $dt->second == $try{second};
		}
		return ( sort { $a <=> $b } @epochs )[0] + $frac if @epochs;
	}

	my $dt = DateTime->new( %parts, time_zone => $tz );
	return $dt->epoch + $frac;
}

sub _calendar_add {
	my ( $class_obj, $self, %delta ) = @_;
	my $epoch = _epoch_from_self($self);
	my $dt = _datetime_from_self($self)->clone;
	$dt->add(%delta);
	my %parts = (
		year => $dt->year,
		month => $dt->month,
		day => $dt->day,
		hour => $dt->hour,
		minute => $dt->minute,
		second => $dt->second,
		fraction => _fractional_part($epoch),
	);
	return _wrap_time(
		$class_obj,
		_same_wall_epoch( _zone_from_self($self), %parts ),
		_zone_from_self($self),
	);
}

sub _duration_parts {
	my ( $duration, $sign ) = @_;
	$sign //= 1;
	return (
		years => $sign * ( $duration->slots->{_years} // 0 ),
		months => $sign * ( $duration->slots->{_months} // 0 ),
		weeks => $sign * ( $duration->slots->{_weeks} // 0 ),
		days => $sign * ( $duration->slots->{_days} // 0 ),
		hours => $sign * ( $duration->slots->{_hours} // 0 ),
		minutes => $sign * ( $duration->slots->{_minutes} // 0 ),
		seconds => $sign * ( $duration->slots->{_seconds} // 0 ),
	);
}

sub _duration_seconds {
	my ( %parts ) = @_;
	return $parts{seconds} + $parts{minutes} * 60 + $parts{hours} * 3600;
}

sub _add_duration {
	my ( $class_obj, $self, $duration, $sign ) = @_;
	my %parts = _duration_parts( $duration, $sign );
	my $out = $self;
	$out = _wrap_time(
		$class_obj,
		_epoch_from_self($out) + _duration_seconds(%parts),
		_zone_from_self($out),
	);
	$out = _calendar_add(
		$class_obj,
		$out,
		years => $parts{years},
		months => $parts{months},
		weeks => $parts{weeks},
		days => $parts{days},
	);
	return $out;
}

sub _format_rfc3339 {
	my ( $dt ) = @_;
	return $dt->strftime('%Y-%m-%dT%H:%M:%S%z') =~ s/([+-]\d\d)(\d\d)\z/$1:$2/r;
}

sub _format_rfc5322 {
	my ( $dt, $include_weekday ) = @_;
	my $format = $include_weekday ? '%a, %d %b %Y %H:%M:%S %z' : '%d %b %Y %H:%M:%S %z';
	return $dt->strftime($format);
}

sub _parse_rfc3339_or_iso {
	my ( $value, $default_zone, $need_zone ) = @_;
	if ( $value =~ /\A
		(\d{4})-(\d\d)-(\d\d)
		(?:[Tt ](\d\d):(\d\d)(?::(\d\d)(?:\.\d+)?)?)?
		(?:\s*(Z|[+-]\d\d:?\d\d))?
	\z/x ) {
		my ( $year, $month, $day, $hour, $minute, $second, $offset ) =
			( $1, $2, $3, $4 // 0, $5 // 0, $6 // 0, $7 );
		_runtime_error("Time.parse() requires a timezone")
			if $need_zone and !defined $offset and !defined $default_zone;
		my $zone = defined $offset ? _offset_to_zone( _parse_tz_offset($offset) ) : $default_zone;
		my $epoch = _same_wall_epoch(
			$zone,
			year => 0 + $year,
			month => 0 + $month,
			day => 0 + $day,
			hour => 0 + $hour,
			minute => 0 + $minute,
			second => 0 + $second,
		);
		return ( $epoch, $zone );
	}
	return;
}

sub _parse_rfc5322 {
	my ( $value ) = @_;
	if ( $value =~ /\A
		(?:[A-Za-z]{3},\s*)?
		(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})
		\s+(\d\d):(\d\d)(?::(\d\d))?
		\s+(Z|[+-]\d\d:?\d\d|UT|UTC|GMT)
	\z/xi ) {
		my ( $day, $mon, $year, $hour, $minute, $second, $zone ) =
			( $1, $2, $3, $4, $5, $6 // 0, $7 );
		my $month = $MONTH_BY_NAME{ lc $mon } or die "Error parsing time\n";
		my $offset = _parse_tz_offset($zone);
		$offset = 0 if defined $zone and $zone =~ /\A(?:UT|UTC|GMT)\z/i;
		die "Error parsing time\n" if !defined $offset;
		my $zone_name = _offset_to_zone($offset);
		my $epoch = _same_wall_epoch(
			$zone_name,
			year => 0 + $year,
			month => $month,
			day => 0 + $day,
			hour => 0 + $hour,
			minute => 0 + $minute,
			second => 0 + $second,
		);
		return ( $epoch, $zone_name );
	}
	return;
}

sub _parse_time_value {
	my ( $value, $zone, $require_zone ) = @_;
	my @parsed = _parse_rfc3339_or_iso( $value, $zone, $require_zone );
	return @parsed if @parsed;
	@parsed = _parse_rfc5322($value);
	return @parsed if @parsed;
	die "Error parsing time\n";
}

sub _runtime_error {
	my ( $message ) = @_;
	die Zuzu::Error->new_runtime(
		message => $message,
		file => '<std/time>',
		line => 0,
	);
}

sub _parse_legacy_strptime {
	my ( $value, $format ) = @_;
	if ( $value =~ /\A(?:[A-Za-z]+\.?\s+)?(\d{1,2})(?:st|nd|rd|th)\s+([A-Za-z]{3}),\s+(\d{4})\z/i ) {
		my ( $day, $mon, $year ) = ( $1, lc $2, $3 );
		my $month = $MONTH_BY_NAME{$mon} or die "Exception: unable to parse month\n";
		return _same_wall_epoch(
			'UTC',
			year => 0 + $year,
			month => $month,
			day => 0 + $day,
			hour => 0,
			minute => 0,
			second => 0,
		);
	}
	my @parsed = _parse_rfc3339_or_iso( $value, 'UTC', 0 );
	return $parsed[0] if @parsed;
	die "Exception: unable to parse time string\n";
}

sub IMPORT {
	my ( $class, $runtime ) = @_;

	my $time_class = native_class( name => 'Time' );
	my $zone_class = native_class( name => 'TimeZone' );
	my $duration_class = native_class( name => 'Duration' );
	my $format_class = native_class( name => 'TimeFormat' );
	my $parser_class = native_class( name => 'TimeParser' );

	$zone_class->native_constructor( sub {
		my ( $rt, $klass, $positional, $named ) = @_;
		my $name = @{ $positional // [] } ? $positional->[0] : $named->{name};
		return _wrap_timezone( $klass, _zone_name($name) );
	} );

	$duration_class->native_constructor( sub {
		my ( $rt, $klass, $positional, $named ) = @_;
		return _wrap_duration(
			$klass,
			years => $named->{years},
			months => $named->{months},
			weeks => $named->{weeks},
			days => $named->{days},
			hours => $named->{hours},
			minutes => $named->{minutes},
			seconds => @{ $positional // [] } ? $positional->[0] : $named->{seconds},
		);
	} );

	$format_class->native_constructor( sub {
		my ( $rt, $klass, $positional, $named ) = @_;
		my $pattern = @{ $positional // [] } ? $positional->[0] : $named->{pattern};
		return _wrap_format(
			$klass,
			kind => $named->{kind} // 'strftime',
			pattern => defined $pattern ? "$pattern" : '',
			timezone => defined $named->{timezone} ? _timezone_label( $named->{timezone} ) : undef,
		);
	} );

	$time_class->native_constructor( sub {
		my ( $rt, $klass, $positional, $named ) = @_;
		my $epoch = @{ $positional // [] } ? $positional->[0] : $named->{epoch};
		$epoch = time if !defined $epoch;
		my $zone = exists $named->{timezone} ? $named->{timezone} : 'local';
		return _wrap_time( $klass, $epoch, $zone );
	} );

	$time_class->static_methods->{parse} = native_function(
		name => 'parse',
		accepts_named => 1,
		native => sub {
			my ( $klass, $raw, @rest ) = @_;
			my $named = ref( $rest[-2] ) eq 'HASH' ? $rest[-2] : {};
			my $value = defined $raw ? "$raw" : '';
			my $zone = exists $named->{timezone} ? _timezone_label( $named->{timezone} ) : undef;
			my ( $epoch, $parsed_zone ) = _parse_time_value( $value, $zone, 1 );
			return _wrap_time( $time_class, $epoch, $zone // $parsed_zone );
		},
	);

	$zone_class->static_methods->{utc} = native_function(
		name => 'utc',
		native => sub { _wrap_timezone( $zone_class, 'UTC' ) },
	);
	$zone_class->static_methods->{local} = native_function(
		name => 'local',
		native => sub { _wrap_timezone( $zone_class, 'local' ) },
	);
	$zone_class->static_methods->{named} = native_function(
		name => 'named',
		native => sub { _wrap_timezone( $zone_class, $_[1] ) },
	);
	$zone_class->static_methods->{offset} = native_function(
		name => 'offset',
		native => sub { _wrap_timezone( $zone_class, _offset_to_zone( 0 + ( $_[1] // 0 ) ) ) },
	);

	for my $part ( qw( seconds minutes hours days weeks months years ) ) {
		$duration_class->static_methods->{$part} = native_function(
			name => $part,
			native => sub { _wrap_duration( $duration_class, $part => $_[1] // 0 ) },
		);
	}

	$format_class->static_methods->{iso8601} = native_function(
		name => 'iso8601',
		native => sub { _wrap_format( $format_class, kind => 'iso8601' ) },
	);
	$format_class->static_methods->{rfc3339} = native_function(
		name => 'rfc3339',
		native => sub { _wrap_format( $format_class, kind => 'rfc3339' ) },
	);
	$format_class->static_methods->{rfc5322} = native_function(
		name => 'rfc5322',
		native => sub { _wrap_format( $format_class, kind => 'rfc5322' ) },
	);
	$format_class->static_methods->{strftime} = native_function(
		name => 'strftime',
		accepts_named => 1,
		native => sub {
			my ( $klass, $pattern, @rest ) = @_;
			my $named = ref( $rest[-2] ) eq 'HASH' ? $rest[-2] : {};
			return _wrap_format(
				$format_class,
				kind => 'strftime',
				pattern => defined $pattern ? "$pattern" : '',
				timezone => exists $named->{timezone} ? _timezone_label( $named->{timezone} ) : undef,
			);
		},
	);

	my %zone_methods = (
		name => sub { $_[0]->slots->{_name} },
		to_String => sub { $_[0]->slots->{_name} },
	);
	for my $name ( keys %zone_methods ) {
		$zone_class->methods->{$name} = native_function(
			name => $name,
			native => $zone_methods{$name},
		);
	}

	my %duration_methods = map {
		my $slot = "_$_";
		$_ => sub { $_[0]->slots->{$slot} // 0 }
	} qw( years months weeks days hours minutes seconds );
	for my $name ( keys %duration_methods ) {
		$duration_class->methods->{$name} = native_function(
			name => $name,
			native => $duration_methods{$name},
		);
	}

	my %methods = (
		sec => sub { _datetime_from_self( $_[0] )->second },
		min => sub { _datetime_from_self( $_[0] )->minute },
		hour => sub { _datetime_from_self( $_[0] )->hour },
		day_of_month => sub { _datetime_from_self( $_[0] )->day_of_month },
		mon => sub { _datetime_from_self( $_[0] )->month },
		month => sub { $MONTH_ABBR[ _datetime_from_self( $_[0] )->month - 1 ] },
		year => sub { _datetime_from_self( $_[0] )->year },
		yy => sub { sprintf '%02d', _datetime_from_self( $_[0] )->year % 100 },
		day_of_week => sub { _datetime_from_self( $_[0] )->day_of_week },
		day => sub { $DAY_ABBR[ _datetime_from_self( $_[0] )->day_of_week - 1 ] },
		day_of_year => sub { _datetime_from_self( $_[0] )->day_of_year - 1 },
		month_last_day => sub { _datetime_from_self( $_[0] )->month_length },
		hms => sub { _datetime_from_self( $_[0] )->hms( @_ > 1 ? $_[1] : ':' ) },
		ymd => sub { _datetime_from_self( $_[0] )->ymd( @_ > 1 ? $_[1] : '-' ) },
		mdy => sub { _datetime_from_self( $_[0] )->mdy( @_ > 1 ? $_[1] : '-' ) },
		dmy => sub { _datetime_from_self( $_[0] )->dmy( @_ > 1 ? $_[1] : '-' ) },
		date => sub { _datetime_from_self( $_[0] )->ymd },
		time => sub { _datetime_from_self( $_[0] )->hms },
		datetime => sub { _datetime_from_self( $_[0] )->datetime },
		to_String => sub { _datetime_from_self( $_[0] )->datetime },
		cdate => sub { _datetime_from_self( $_[0] )->strftime('%a %b %e %H:%M:%S %Y') },
		epoch => sub { _epoch_from_self( $_[0] ) },
		tzoffset => sub { _datetime_from_self( $_[0] )->offset },
		is_leap_year => sub { _datetime_from_self( $_[0] )->is_leap_year ? 1 : 0 },
		week => sub { _datetime_from_self( $_[0] )->week_number },
		week_year => sub { _datetime_from_self( $_[0] )->week_year },
		julian_day => sub { _datetime_from_self( $_[0] )->jd },
		timezone => sub { _wrap_timezone( $zone_class, _zone_from_self( $_[0] ) ) },
		as_utc => sub { _wrap_time( $time_class, _epoch_from_self( $_[0] ), 'UTC' ) },
		as_local => sub { _wrap_time( $time_class, _epoch_from_self( $_[0] ), 'local' ) },
		to_iso8601 => sub { _format_rfc3339( _datetime_from_self( $_[0] ) ) },
		to_rfc3339 => sub { _format_rfc3339( _datetime_from_self( $_[0] ) ) },
	);

	for my $name ( sort keys %methods ) {
		$time_class->methods->{$name} = native_function(
			name => $name,
			native => $methods{$name},
		);
	}

	$time_class->methods->{to_rfc5322} = native_function(
		name => 'to_rfc5322',
		accepts_named => 1,
		native => sub {
			my ( $self, @rest ) = @_;
			my $named = ref( $rest[-2] ) eq 'HASH' ? $rest[-2] : {};
			my $include = exists $named->{include_weekday} ? $named->{include_weekday} : 1;
			return _format_rfc5322( _datetime_from_self($self), $include );
		},
	);

	$time_class->methods->{strftime} = native_function(
		name => 'strftime',
		native => sub {
			my ( $self, $format ) = @_;
			return _datetime_from_self($self)->strftime( defined $format ? "$format" : '' );
		},
	);

	$time_class->methods->{with_timezone} = native_function(
		name => 'with_timezone',
		native => sub {
			my ( $self, $zone ) = @_;
			return _wrap_time( $time_class, _epoch_from_self($self), $zone );
		},
	);

	$time_class->methods->{reinterpret_timezone} = native_function(
		name => 'reinterpret_timezone',
		native => sub {
			my ( $self, $zone ) = @_;
			my $dt = _datetime_from_self($self);
			my $new_zone = _timezone_label($zone);
			my $epoch = _same_wall_epoch(
				$new_zone,
				year => $dt->year,
				month => $dt->month,
				day => $dt->day,
				hour => $dt->hour,
				minute => $dt->minute,
				second => $dt->second,
				fraction => _fractional_part( _epoch_from_self($self) ),
			);
			return _wrap_time( $time_class, $epoch, $new_zone );
		},
	);

	for my $unit ( qw( seconds minutes hours ) ) {
		my $seconds = $unit eq 'seconds' ? 1 : $unit eq 'minutes' ? 60 : 3600;
		$time_class->methods->{"add_$unit"} = native_function(
			name => "add_$unit",
			native => sub {
				my ( $self, $count ) = @_;
				return _wrap_time(
					$time_class,
					_epoch_from_self($self) + ( 0 + ( $count // 0 ) ) * $seconds,
					_zone_from_self($self),
				);
			},
		);
		$time_class->methods->{"subtract_$unit"} = native_function(
			name => "subtract_$unit",
			native => sub {
				my ( $self, $count ) = @_;
				return $time_class->methods->{"add_$unit"}->{_native}->( $self, -( 0 + ( $count // 0 ) ) );
			},
		);
	}

	for my $unit ( qw( days weeks months years ) ) {
		$time_class->methods->{"add_$unit"} = native_function(
			name => "add_$unit",
			native => sub {
				my ( $self, $count ) = @_;
				return _calendar_add( $time_class, $self, $unit => 0 + ( $count // 0 ) );
			},
		);
		$time_class->methods->{"subtract_$unit"} = native_function(
			name => "subtract_$unit",
			native => sub {
				my ( $self, $count ) = @_;
				return _calendar_add( $time_class, $self, $unit => -( 0 + ( $count // 0 ) ) );
			},
		);
	}

	$time_class->methods->{add} = native_function(
		name => 'add',
		native => sub { _add_duration( $time_class, $_[0], $_[1], 1 ) },
	);
	$time_class->methods->{subtract} = native_function(
		name => 'subtract',
		native => sub { _add_duration( $time_class, $_[0], $_[1], -1 ) },
	);
	$time_class->methods->{elapsed_seconds_until} = native_function(
		name => 'elapsed_seconds_until',
		native => sub { _epoch_from_self( $_[1] ) - _epoch_from_self( $_[0] ) },
	);
	$time_class->methods->{compare} = native_function(
		name => 'compare',
		native => sub { _epoch_from_self( $_[0] ) <=> _epoch_from_self( $_[1] ) },
	);
	$time_class->methods->{is_before} = native_function(
		name => 'is_before',
		native => sub { _epoch_from_self( $_[0] ) < _epoch_from_self( $_[1] ) ? 1 : 0 },
	);
	$time_class->methods->{is_after} = native_function(
		name => 'is_after',
		native => sub { _epoch_from_self( $_[0] ) > _epoch_from_self( $_[1] ) ? 1 : 0 },
	);
	$time_class->methods->{format} = native_function(
		name => 'format',
		native => sub {
			my ( $self, $format ) = @_;
			my $zone = $format->slots->{_timezone} // _zone_from_self($self);
			my $dt = _datetime_from_epoch( _epoch_from_self($self), $zone );
			my $kind = $format->slots->{_kind};
			return _format_rfc3339($dt) if $kind eq 'iso8601' or $kind eq 'rfc3339';
			return _format_rfc5322( $dt, 1 ) if $kind eq 'rfc5322';
			return $dt->strftime( $format->slots->{_pattern} // '' );
		},
	);

	$format_class->methods->{format} = native_function(
		name => 'format',
		native => sub { $time_class->methods->{format}->{_native}->( $_[1], $_[0] ) },
	);
	$format_class->methods->{parse} = native_function(
		name => 'parse',
		accepts_named => 1,
		native => sub {
			my ( $self, $raw, @rest ) = @_;
			my $named = ref( $rest[-2] ) eq 'HASH' ? $rest[-2] : {};
			my $zone = $self->slots->{_timezone};
			$zone = _timezone_label( $named->{timezone} ) if exists $named->{timezone};
			my ( $epoch, $parsed_zone ) = _parse_time_value( "$raw", $zone, 1 );
			return _wrap_time( $time_class, $epoch, $zone // $parsed_zone );
		},
	);

	$parser_class->native_constructor( sub {
		my ( $rt, $klass, $positional, $named ) = @_;
		my $format = @{ $positional // [] } ? $positional->[0] : $named->{format};
		$format = '%Y-%m-%d' if !defined $format;
		return native_object(
			class => $klass,
			slots => { _format => "$format" },
			const => { _format => 1 },
		);
	} );

	$parser_class->methods->{parse} = native_function(
		name => 'parse',
		native => sub {
			my ( $self, $raw ) = @_;
			my $epoch = _parse_legacy_strptime( defined $raw ? "$raw" : '', $self->slots->{_format} );
			return _wrap_time( $time_class, $epoch, 'UTC' );
		},
	);

	return {
		Time => $time_class,
		TimeZone => $zone_class,
		Duration => $duration_class,
		TimeFormat => $format_class,
		TimeParser => $parser_class,
	};
}

1;

=pod

=head1 NAME

Zuzu::Module::Time - std/time bindings for ZuzuScript.

=head1 DESCRIPTION

Implements the C<std/time> module, exporting immutable C<Time> objects and
timezone, duration, and formatting helpers. The original C<Time> and
C<TimeParser> API remains available.

=cut
