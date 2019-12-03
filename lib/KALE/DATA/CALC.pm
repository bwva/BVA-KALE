package BVA::KALE::DATA::CALC;

## Calculations
## Used in SELECT, BROWSE, INSERT

sub _default {
	my $self	= $_[0];

	my $record	= $_[1];

	my $col		= $_[2];

	return $record->[$col] . '**';
}

sub required {
	my $self	= $_[0];

	my $record	= $_[1];

	my $col		= $_[2];

	my ($fld)	= $self->labels($self->fields($col));

	my $id		= $_[1]->[$self->{_id_col}];

	$self->{_err}->("add: Missing Data for $fld in record ID $id of $self->{FILE_NAME}.\n");

	return "";
}

sub dated {
	my $self	= $_[0];

	my $record	= $_[1];

	my $col		= $_[2];

	# Derive standard local date values/indices
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;

	$year			+= 1900;
	my $mil_hour	= $hour;
	my $AP			= $hour > 11 ? 'PM' : 'AM' ;
	$hour			= $hour % 12 || 12;
	my $season		= $isdst ? 'DST' : 'STD' ; # local savings/standard time

	my $output_time	= sprintf "%4.4d-%2.2d-%2.2d",
	$year, $mon + 1, $mday;

	return $record->[$col] . " ($output_time)";
}

sub exec_date {
	my $self	= $_[0];

	my $rec		= $_[1];

	# Derive standard local date values/indices
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;

	$year			+= 1900;
	my $mil_hour	= $hour;
	my $AP			= $hour > 11 ? 'PM' : 'AM' ;
	$hour			= $hour % 12 || 12;
	my $season		= $isdst ? 'DST' : 'STD' ; # local savings/standard time

	my $output_time	= sprintf "%4.4d-%2.2d-%2.2d",
	$year, $mon + 1, $mday;

	return $output_time;

}

sub exec_date_time {
	my $self	= $_[0];

	my $rec		= $_[1];

	# Derive standard local date values/indices
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;

	$year			+= 1900;
	my $mil_hour	= $hour;
	my $AP			= $hour > 11 ? 'PM' : 'AM' ;
	$hour			= $hour % 12 || 12;
	my $season		= $isdst ? 'DST' : 'STD' ; # local savings/standard time

	my $output_time	= sprintf "%4.4d-%2.2d-%2.2dT%2.2d:%2.2d:%2.2d",
	$year, $mon + 1, $mday, $mil_hour, $min, $sec;

	return $output_time;

}

sub exec_time {
	my $self	= $_[0];

	# Derive standard local date values/indices
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;

	$year			+= 1900;
	my $mil_hour	= $hour;
	my $AP			= $hour > 11 ? 'PM' : 'AM' ;
	$hour			= $hour % 12 || 12;
	my $season		= $isdst ? 'DST' : 'STD' ; # local savings/standard time

	my $output_time	= sprintf "%2.2d:%2.2d:%2.2d",
	$mil_hour, $min, $sec;

	return $output_time;
}


1;

