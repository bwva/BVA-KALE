package BVA::KALE::IN;

$BVA::KALE::IN::VERSION	= '1.080.040'; # 2020-08-21 bva@cruzio.com

use strict;
use warnings;

sub IN {
	my $obj			= $_[0];
	local *::KEY	= $obj->invert();

	my $input_env	= $::KEY{_psgi_env} ? 'psgi' : $::KEY{_env};

	my $input_sub	= \&{ '_input_' . $input_env };

	my $max_input	= $::KEY{'_in_max'}; #  * 1000

	my $input		= $input_sub->($obj, $max_input);

	$::KEY{_input}	= $input;

	return $::KEY{_input} if $input->{_input_err};

	## Aggregate preview
	$obj->checkforuploads;
	$obj->checkfordates;
	$obj->checkfortimes;

	## Now see if there are any methods named by field name.
	## Don't iterate directly on keys %{ $::KEY{_input} }
	## to avoid problems if the structure of $::KEY{_input} is changed
	my @keys		= keys %{ $::KEY{_input} };
	for my $key (@keys) {
		$obj->PREVIEW($key)
	}

	## Refresh the field list, and now scan for methods named by value.
	## Don't iterate directly on keys %{ $::KEY{_input} }
	## to avoid problems if the structure of $::KEY{_input} is changed
	@keys		= keys %{ $::KEY{_input} };
	for my $key (@keys) {
		$obj->SCAN($key)
	}

	## Now process individual input fields
	for my $name (keys %{ $::KEY{_input} }) {

		next unless length($::KEY{_input}->{$name});

		$obj->CLEAN($name);

		$obj->FILTER($name);

		$obj->VALIDATE($name);

	}

	$::KEY{_input}
}

# Preview: look at the input by key (field name) before processing it.
# Input fields and data may be added or removed;
sub PREVIEW {
	my $obj			= $_[0];
	local *::KEY	= $obj->invert();

	my ($name, $fld_name)	= ($_[1], $_[1]);
	$fld_name				=~ s/[: ]/_/;

	my $action;

	## See if there is a field-specific preview method
	if (defined(&{"$::KEY{'_in_lib'}::preview_$fld_name"})) {
		$action	= \&{"$::KEY{'_in_lib'}::preview_$fld_name"}
	} elsif (defined(&{"main::preview_$fld_name"})) {
		$action	= \&{"main::preview_$fld_name"}
	} elsif (defined(&{"preview_$fld_name"})) {
		$action	= \&{"preview_$fld_name"}
	} else {
		return
	}

	$action->(@_);
}

# Scan: look at the input by value before processing it.
# Input fields and data may be added or removed;
sub SCAN {
	my $obj			= $_[0];
	local *::KEY	= $obj->invert();

	my ($fld_name,$value)	= ($_[1], $::KEY{_input}->{$_[1]});
	$value				=~ s/[: ]/_/;

	my $action;

	## See if there is a value-specific scan method
	if (defined(&{"$::KEY{'_in_lib'}::scan_$value"})) {
		$action	= \&{"$::KEY{'_in_lib'}::scan_$value"}
	} elsif (defined(&{"main::scan_$value"})) {
		$action	= \&{"main::scan_$value"}
	} elsif (defined(&{"scan_$value"})) {
		$action	= \&{"scan_$value"}
	} else {
		return
	}

	$action->(@_);
}


# Clean and untaint
sub CLEAN {
	my $obj					= $_[0];
	local *::KEY			= $obj->invert();

	my ($name, $fld_name)	= ($_[1], $_[1]);
	$fld_name				=~ s/[: ]/_/;

	# untaint and delete end spaces
	$::KEY{_input}->{$name}	=~ /^([^`]+)\s*$/ or return;
	$::KEY{_input}->{$name}	= $1;

	my $action;

	## Now see if there is a field-specific cleaning method
	if (defined(&{"$::KEY{'_in_lib'}::clean_$fld_name"})) {
		$action	= \&{"$::KEY{'_in_lib'}::clean_$fld_name"}
	} elsif (defined(&{"main::clean_$fld_name"})) {
		$action	= \&{"main::clean_$fld_name"}
	} elsif (defined(&{"clean_$fld_name"})) {
		$action	= \&{"clean_$fld_name"}
	} else {
		return
	}

	$action->(@_);
}

# Filters
sub FILTER {
	my $obj					= $_[0];

	my $fld_name			= $_[1];
	$fld_name				=~ s/[: ]/_/;

	my $action;

	## See if there is a field-specific filter method
	if (defined(&{"$::KEY{'_in_lib'}::filter_$fld_name"})) {
		$action	= \&{"$::KEY{'_in_lib'}::filter_$fld_name"}
	} elsif (defined(&{"main::filter_$fld_name"})) {
		$action	= \&{"main::filter_$fld_name"}
	} elsif (defined(&{"filter_$fld_name"})) {
		$action	= \&{"filter_$fld_name"}
	} else {
		return
	}

	$action->(@_);
}

# Validators
sub VALIDATE {
	my $obj					= $_[0];

	my $fld_name			= $_[1];
	$fld_name				=~ s/[: ]/_/;

	my $action;

	## See if there is a field-specific validate method
	if (defined(&{"$::KEY{'_in_lib'}::validate_$fld_name"})) {
		$action	= \&{"$::KEY{'_in_lib'}::validate_$fld_name"}
	} elsif (defined(&{"main::validate_$fld_name"})) {
		$action	= \&{"main::validate_$fld_name"}
	} elsif (defined(&{"validate_$fld_name"})) {
		$action	= \&{"validate_$fld_name"}
	} else {
		return
	}

	$action->(@_);
}


## GET INPUT for UI OBJECTS

## Marked Input
## Checks all input for fields bearing the current UI Object's mark ("KEY").
## Input fields may be marked these ways: KEY:fieldname, KEY_fieldname, fieldname_KEY.
## For fields found, the marks are removed from the field names,
## and the field=>value pairs are stored in field named for the mark ($::KEY{KEY}),
## with a reference in the object's meta field _vals (e.g.,  $obj->data('_vals').
## The field=>value pairs are returned.

sub get_marked_input ($;@) {
	my $obj		= shift();
	local *::KEY	= $obj->invert(); # *{ $obj };

	my $mark	= shift || $::KEY{_mark};
	return {} unless $mark;
	my $testsub	= shift || sub {length $_[0]};

	for my $k (keys %{ $::KEY{_input} } ) {
		my $fld	= '';
		if ($k =~ /^(.+)_${mark}$/) {
			$fld	= $1;
		} elsif ($k =~ /^${mark}[:_](.+)$/) {
			$fld	= $1;
		}
		if ($testsub->($fld)) {
			$::KEY{$mark}->{$fld}	= $::KEY{_input}->{$k};
		}
	}

	$obj->charge_meta(_vals => $::KEY{$mark});
	return $::KEY{$mark}
}

## Required Input
## get_required_input() uses any $::KEY{_required_sub} defined for KEY, and also
## checks $::KEY{_expected} for fields required due to specific input values

sub get_required_input ($;@) {
	my $obj		= shift();
	local *::KEY	= $obj->invert(); # *{ $obj };
	my $req			= shift() || '';
	my $list_name	= shift() || '';
	my $response	= shift() || $::KEY{_required_sub}
									|| sub {
											my $self	= shift;
											return unless @{ $_[0] };
											wantarray ? @_ :
												$self->ask( join(" \n" => "\nMissing:",
																@{ $_[0] },
																"\nSupplied:",
																@{ $_[1] }),
												"Required Input:" )
											};
	my $marked_only	= shift() || 0;
	my $mark		= shift() || $::KEY{_mark};

	my @required	= $obj->required($req, $list_name);

	# Now, let's see what we got:
	my (@supplied, @missing);
	for (@required) {
		if (!$marked_only && $::KEY{_input}->{$_}
			or $::KEY{_input}->{"$mark:$_"}
				or $::KEY{_input}->{"${mark}_$_"}
					or $::KEY{_input}->{"${_}_$mark"}
						or '' )
		{
			push @supplied => $_
		} else {
			push @missing => $_
		}
	}

	# Respond
 	$obj->$response(\@missing, \@supplied);
}

## Required Marked Input
## get_required_marked_input() uses any $::KEY{_required_sub} defined for KEY, and also
## checks $::KEY{_expected} for fields required due to specific input values.
## Only looks at marked input, but the mark may be changed from the object's own ('KEY')
sub get_required_marked_input ($;@) {
	my $obj		= shift();
	local *::KEY	= $obj->invert(); # *{ $obj };
	my $req			= shift() || '';
	my $list_name	= shift() || '';
	my $response	= shift() || $::KEY{_required_sub}
									|| sub {
											my $self	= shift;
											return unless @{ $_[0] };
											wantarray ? @_ :
												$self->ask( join(" \n" => "\nMissing:",
																@{ $_[0] },
																"\nSupplied:",
																@{ $_[1] }),
												"Required Input:" )
											};

	my $mark		= shift() || $::KEY{_mark};

	my @required	= $obj->required($req, $list_name);

	# Now, let's see what we got:
	my (@supplied, @missing);
	for (@required) {
		if ($::KEY{_input}->{"${mark}_$_"}
				or $::KEY{_input}->{"${mark}_$_"}
					or $::KEY{_input}->{"${_}_$mark"}
						or '' )
		{
			push @supplied => $_
		} else {
			push @missing => $_
		}
	}

	# Respond
 	$obj->$response( \@missing, \@supplied );
}

## Boolean input
sub get_boolean ($;@) {
	my $obj			= shift;
	local *::KEY	= $obj->invert();

	my $req			= shift() || '';
	my $list_name	= shift() || '';
	my $marked_only	= shift() || 0;
	my $mark		= shift() || $::KEY{_mark};

	$req			||= exists $::KEY{_lists}->{$list_name} ? $::KEY{_lists}->{$list_name} :
						  exists $::KEY{_boolean} ? $::KEY{_boolean} :
					   	    exists $::KEY{_lists}->{boolean} ? $::KEY{_lists}->{boolean} :
						      [];

	my $req_ref		= ref($req) || '';
	my @boolean	= ! $req_ref	? split( /\s*,\s*/ => $req )
		: $req_ref =~ /ARRAY/i	? @{ $req }
		: $req_ref =~ /HASH/i	? keys %{ $req }
		: $req_ref =~ /CODE/i	? ( &$req )
		: $req_ref =~ /SCALAR/i	? split( /\s*,\s*/ => $$req )
		: $req_ref =~ /GLOB/i	? map { chomp; $_ } <$req>
		: ();

	# Input 'boolean' field supplements, does not replace, internal boolean lists
	if ($::KEY{_vals}->{boolean}) {
		push @boolean => split( /\s*,\s*/ => delete $::KEY{_vals}->{boolean} );
	}

	my %seen;
	@boolean		= map { exists $seen{$_} ? () : ++$seen{$_} && $_ } @boolean;
	my %booleans;
	foreach (@boolean) {
		if ($::KEY{_input}->{$_}) {
			$booleans{$_} = 1;
			next
		}

		if (($::KEY{_input}->{"$mark:$_"}
				and $booleans{"$mark:$_"} = 1)
					or ($::KEY{_input}->{"${mark}_$_"}
						and $booleans{"${mark}_$_"} = 1)
							or ($::KEY{_input}->{"${_}_$mark"}
								and $booleans{"${_}_$mark"} = 1)
		) {
		next
		}

		$::KEY{_input}->{$_}	= 0;
		$booleans{$_}		= 0;
		if (/^(.+)_$mark$/ or /^${mark}[:_](.+)$/) {
			$::KEY{_vals}->{$1}	= 0;
		} else {
			$::KEY{_vals}->{$_}	= 0;
		}
	}

	\%booleans;
}

sub is_required {
	my $obj			= shift;
	local *::KEY	= $obj->invert();
	my $fld			= shift;

	(grep { $fld eq $_ } $obj->required) ? 1 : 0;
}

sub required {
	my $obj			= shift;
	local *::KEY	= $obj->invert();
	my $req			= shift() || '';
	my $list_name	= shift() || '';

	$req			||= exists $::KEY{_lists}->{$list_name} ? $::KEY{_lists}->{$list_name} :
						  exists $::KEY{_required} ? $::KEY{_required} :
					   	    exists $::KEY{_lists}->{required} ? $::KEY{_lists}->{required} :
						      [];

	my $req_ref		= ref($req) || '';
	my @required	= ! $req_ref	? split( /\s*,\s*/ => $req )
		: $req_ref =~ /ARRAY/i	? @{ $req }
		: $req_ref =~ /HASH/i	? keys %{ $req }
		: $req_ref =~ /CODE/i	? ( &$req )
		: $req_ref =~ /SCALAR/i	? split( /\s*,\s*/ => $$req )
		: $req_ref =~ /GLOB/i	? map { chomp; $_ } <$req>
		: ();

	# Input 'required' field supplements, does not replace, internal required lists
	if ($::KEY{_vals}->{required}) {
		push @required => split( /\s*,\s*/ => $::KEY{_vals}->{required} )
	}

	## Expected: what other fields to require if a given field has a specified value
	if ($::KEY{_expected}) {
		for my $key (keys %{$::KEY{_expected}}) {
			next unless $::KEY{_vals}->{$key} and $::KEY{_expected}->{$key}->{ $::KEY{_vals}->{$key} };
			push @required => @{ $::KEY{_expected}->{$key}->{ $::KEY{_vals}->{$key} } }
		}
	}

	# Example of $::KEY{_expected}
	# 		{
	# 			contact		=> {
	# 				Telephone	=> [qw/phone/],
	# 				Email		=> [qw/email/],
	# 				'US Mail'	=> [qw/address city state zip/],
	# 			},
	# 			nonreturn	=> {
	# 				1			=> [qw/copyright_ok/],
	# 			},
	# 		}

	my %seen;

	map { exists $seen{$_} ? () : ++$seen{$_} && $_ } @required;
}


sub set_required ($;@) {
	my $obj				= shift;
	local *::KEY		= $obj->invert();
	my @required		= ref($_[0]) ? @{ $_[0] } : @_;
	return unless @required;
	$obj->list_items('required', @required);
	$obj->charge_meta( _required	=> { map {
		$::KEY{_meta}{$_}{required} = 1;
		$_ => 1
	} @required } ); #

}


sub is_missing {
	my $obj			= shift;
	local *::KEY	= $obj->invert();
	my $fld			= shift;

	(grep /$fld/ => $obj->missing) ? 1 : 0
}

sub missing {
	my $obj			= shift;
	local *::KEY	= $obj->invert();
	my $req			= shift() || '';
	my $list_name	= shift() || '';

	$req			||= exists $::KEY{_lists}->{$list_name} ? $::KEY{_lists}->{$list_name} :
						  exists $::KEY{_missing} ? $::KEY{_missing} :
					   	    exists $::KEY{_lists}->{missing} ? $::KEY{_lists}->{missing} :
						      [];

	my $req_ref		= ref($req) || '';
	my @missing	= ! $req_ref	? split( /\s*,\s*/ => $req )
		: $req_ref =~ /ARRAY/i	? @{ $req }
		: $req_ref =~ /HASH/i	? keys %{ $req }
		: $req_ref =~ /CODE/i	? ( &$req )
		: $req_ref =~ /SCALAR/i	? split( /\s*,\s*/ => $$req )
		: $req_ref =~ /GLOB/i	? map { chomp; $_ } <$req>
		: ();

	my %seen;

	map { exists $seen{$_} ? () : ++$seen{$_} && $_ } @missing;
}

## Get Search
## Assembles search criteria from input and stores it
## in a format allowing recreation of the input form with the criteria
sub get_search ($;@) {
	my $obj				= shift;
	local *::KEY		= $obj->invert();
	# ...
}



## Checkfordates
## Assembles dates from input parts composed of fields
## ending in _year, _yr, _month, _mon, _day
## Adds assembled dates to input data ($::KEY{_input}).

sub checkfordates ($;@) {
	my $obj				= shift;
	local *::KEY		= $obj->invert();
	my %dates;
	my %make_dates;
	my %found_dates;
	for (keys %{ $::KEY{_input} }) {
	    if ( m{^(.*)_(y(?:ea)?r|mon(?:th)?|day)(_\w+)?$} ) {
	    	my $fld			= $1;
	    	my $date_part	= $2;
	    	$date_part		=~ s/y(?:ea)?r/yr/;
	    	$date_part		=~ s/mon(?:th)?/mon/;
	    	$make_dates{$fld}->{$date_part} = $::KEY{_input}->{$_};
	    }
	}

	for (keys %make_dates) {
		$dates{$_} = sprintf qq{%4.4d-%2.2d-%2.2d},

		( ($make_dates{$_}->{yr} and $make_dates{$_}->{yr} =~ m{year}i) ? '0000' :
			($make_dates{$_}->{yr} || '0000')),

		( $make_dates{$_}->{mon} and (
			$make_dates{$_}->{mon} =~ m{month}i ? '00' :
				$make_dates{$_}->{mon} =~ m{^\d+$} ? $make_dates{$_}->{mon} :
					$obj->month_num_lookup($make_dates{$_}->{mon}) || '00') or '00'),

		( ($make_dates{$_}->{day} and $make_dates{$_}->{day} =~ m{day}i) ?
			'00' : $make_dates{$_}->{day} || '00');
	}
	for (keys %dates) {
		$dates{$_} = ($dates{$_} eq '0000-00-00'? '' : $dates{$_})
	}
	$obj->charge_meta(_input => { %{ $::KEY{_input} }, %dates } );
	\%dates
}

## Checkfortimes
## Assembles clock times from input parts composed of fields
## ending in _hr, _min, _sec, _ap
## Adds assembled times to input data ($::KEY{_input}).

sub checkfortimes ($;@) {
	my $obj				= shift;
	local *::KEY		= $obj->invert();
	my %times;
	my %make_times;
	my %found_times;
	for (keys %{ $::KEY{_input} }) {
	    if ( m{^(.*)_(h(?:ou)?r|min(?:ute)?|sec(?:ond)?|ap)s?(_\w+)?$} ) {
	    	my $fld			= $1;
	    	my $time_part	= $2;
	    	$time_part		=~ s/h(?:ou)?r/hr/;
	    	$time_part		=~ s/min(?:ute)?/min/;
	    	$time_part		=~ s/sec(?:ond)?/sec/;
	    	$time_part		=~ s/sec(?:ond)?/sec/;

	    	$make_times{$fld}->{$time_part} = $::KEY{_input}->{$_};
	    }
	}

	for (keys %make_times) {

		my $hr				= ( ($make_times{$_}->{hr} and $make_times{$_}->{hr} =~ m{hour}i) ? '00' :
									($make_times{$_}->{hr} || '00'));

		my $min				= ( ($make_times{$_}->{min} and $make_times{$_}->{min} =~ m{minutes}i) ? '00' :
									($make_times{$_}->{min} || '00'));

		my $sec				= ( ($make_times{$_}->{sec} and $make_times{$_}->{sec} =~ m{seconds}i) ? '00' :
									($make_times{$_}->{sec} || '00'));

		my $ap				= ( ($make_times{$_}->{ap} and $make_times{$_}->{ap} =~ m{AM-PM}i) ? '' :
									($make_times{$_}->{ap} || ''));

		if ($hr == 0) {
			if ($ap) {
				 if ($ap =~/A/i) {$hr = '00'; $sec = '01';}
			}
		} elsif ($hr < 12) {
			if ($ap) {
				$hr += 12 if $ap =~/P/i;
			}
		} elsif ($hr == 12) {
			if ($ap) {
				 if ($ap =~/A/i) {$hr = '00'; $sec = '01';}
			}
		}

# 		$hr += 12 if ($ap and $ap =~/P/i and $hr < 12);
# 		$hr = 0 if ($ap and $ap =~/A/i and $hr == 12);

		$times{$_} = sprintf qq{%2.2d:%2.2d:%2.2d},$hr,$min,$sec;
	}

# 	for (keys %times) {
# 		$times{$_} = ($times{$_} =~ /^00:00:00/ ? '' : $times{$_})
# 	}

	$obj->charge_meta(_input => { %{ $::KEY{_input} }, %times } );
	\%times
}

sub checkforuploads {
	my $obj	= shift();

	local *::KEY		= $obj->invert();

	my $req		= $obj->request;
	my @uploads	= ();
	my $num_uploads	= 0;
	my %new_uploads;

	if ($obj->data('_psgi_env')) {
		@uploads	= keys %{ $req->uploads() };
		for my $upf (@uploads) {
			my $this_up	= $obj->get_upload_by_fld($upf);
			# Assumes only ONE upload per name field
			$new_uploads{$this_up->{'fldname'}}	= $this_up;
			$num_uploads++;
		}
		$::KEY{_input}->{_num_uploads}	= $num_uploads;
	} elsif ($obj->data('_env') eq 'htm') {
		@uploads	= $req->upload;
		for my $upf (@uploads) {
			my $this_up	= $obj->get_upload_by_file($upf);
			# Assumes only ONE upload per file name
			$new_uploads{$this_up->{'fldname'}}	= $this_up;
			$num_uploads++;
		}
		$::KEY{_input}->{_num_uploads}	= $num_uploads;
	}

	$::KEY{_uploads}	= \%new_uploads;

	return $::KEY{_uploads};
}

sub get_upload_by_fld {
	my $obj	= shift();
	my $uploadfldname	= shift();

	return unless $uploadfldname;

 	my $req		= $obj->request;

	my ($upload, $upload_fh, $file_orig, $file_size, $mime_type, $upload_err);

	# Assumes only ONE upload per name field

	if ($obj->data('_psgi_env')) {
		$upload		= $req->uploads->{"$uploadfldname"} || '';
		return unless $upload;

		$file_orig			= $upload->filename;
		$file_size			= $upload->size;
		$mime_type			= $upload->content_type;
		if ($file_size > $obj->data('_in_max') * 1000) {
			$upload_err		= "File not uploaded: size exceeds limit ($file_orig).";
		} else {
			open($upload_fh, "<", $upload->path)
				or $obj->charge_err("Couldn't open uploaded comparison file: $!");
			$upload_err		= '';
		}

	} else {
		$upload		= $req->param($uploadfldname) || '';
		return unless $upload;

		$file_orig			= $upload;
		$file_size			= $req->upload_info($upload,'size');
		$mime_type			= $req->upload_info($upload,'mime');
		if ($file_size > $obj->data('_in_max') * 1000) {
			$upload_err		= "File not uploaded: size exceeds limit ($file_orig).";
		} else {
			$upload_fh		= $req->upload($upload);
			$upload_err		= '';
		}
	}

	return {up_err => $upload_err, up_fh => $upload_fh, fname => $file_orig, fsize => $file_size, ftype => $mime_type, fldname => $uploadfldname };
}

sub get_upload_by_file {
	my $obj	= shift();
	my $uploadfilename	= shift();

	return unless $uploadfilename;

	my $req		= $obj->request;

	# Assumes only ONE upload per file name

	if ($obj->data('_psgi_env')) {
		foreach my $up ( keys %{ $req->uploads } ) {
			if ($up->filename eq $uploadfilename) {
				return $obj->get_upload_by_fld($up);
			}
		}
	} else {
		foreach my $param ( $req->param ) {
			if ($req->param($param) eq $uploadfilename) {
				return $obj->get_upload_by_fld($param);
			}
		}
	}

	return;
}

## Internal Input Subs
## Used by IN() to obtain and organize input

sub _input_htm {
	my $obj	= shift();
	my $input_max	= shift || 10000;

	require CGI::Simple;
	$CGI::Simple::POST_MAX = 1024 * $input_max * 3;  # 3 times max size of posts
	$CGI::Simple::DISABLE_UPLOADS = 0;

	my $req	= CGI::Simple->new;
 	$obj->charge_meta(_request => $req);

	my @params		= $req->param();

	my $err			= $req->cgi_error() || '';

	$err			.= " HEAD Request." if $ENV{REQUEST_METHOD} eq 'HEAD';

	return {_input_err => $err} if $err;

	my $input		= { map {

		my $name = $_;

		## Turn multiple values into (*sorted) de-duped lists
		my ($val, @vals)	= $req->param($name);
		if (@vals and (1 == 1)) { # <-- extension spot #
			my %seen;
			$val = join( ',' => map { split "," } grep {
				if (exists $seen{$_}) { 0 } else { ++$seen{$_}  }
			} $val, @vals); # *sort <-- make this an option
		}

		$val	= ($val ? $val : ( !$val && length($val) ) ? '0' : '' );

		$name => $val
	} @params };

	$input->{_input_err}	= $err;
	$input->{_path_info}	= substr(($req->path_info() || ' '), 1,13);
	$input->{_path_info}	= $input->{_path_info} =~ /^([^`]+)$/ ? $1 : '';

	$input
}

sub _input_xhr {
	my $obj	= shift();
	my $input_max	= shift || 1000;

	require CGI::Simple;
	$CGI::Simple::POST_MAX=1024 * $input_max * 3;  # 3 times max size of posts
	$CGI::Simple::DISABLE_UPLOADS = 0;

	my $req	= CGI::Simple->new;
 	$obj->charge_meta(_request => $req);

	my @params		= $req->param();

	my $err			= $req->cgi_error() || '';

	$err			.= " HEAD Request." if $ENV{REQUEST_METHOD} eq 'HEAD';

	return {_input_err => $err} if $err;

	my $input		= { map {
		my $name = $_;

		## Turn multiple values into (*sorted) de-duped lists
		my ($val, @vals)	= $req->param($name);
		if (@vals and (1 == 1)) { # <-- extension spot #
			my %seen;
			$val = join( ',' => map { split "," } grep {
				if (exists $seen{$_}) { 0 } else { ++$seen{$_}  }
			} $val, @vals); # *sort <-- make this an option
		}

		$val	= ($val ? $val : ( !$val && length($val) ) ? '0' : '' );

		$name => $val
	} @params };

	$input->{_input_err}	= $err;
	$input->{_path_info}	= substr(($req->path_info() || ' '), 1,13);
	$input->{_path_info}	= $input->{_path_info} =~ /^([^`]+)$/ ? $1 : '';

	$input
}

sub _input_psgi {
	my $obj	= shift();

	require Plack::Request;
 	my $env	= $obj->data('_psgi_env');

 	my $request	= Plack::Request->new($env);
 	$obj->charge_meta(_request => $request);

	my $params = $request->parameters->mixed;
	my $input	= { map {
		my $name = $_;

		## Turn multiple values into (*sorted) de-duped lists
		my ($val, @vals)	= $request->param($name);
		if (@vals and (1 == 1)) { # <-- extension spot #
			my %seen;
			$val = join( ',' => map { split "," } grep {
				if (exists $seen{$_}) { 0 } else { ++$seen{$_}  }
			} $val, @vals); # *sort <-- make this an option
		}

		$val	= ($val ? $val : ( !$val && length($val) ) ? '0' : '' );

		$name => $val
	} keys %$params };

	$input->{_path_info}	= substr(($request->path_info() || ' '), 1,13);
	$input->{_path_info}	= $input->{_path_info} =~ /^([^`]+)$/ ? $1 : '';
	$input->{REMOTE_ADDR}	= $request->address();
	$input->{REMOTE_ADDR}	= $input->{REMOTE_ADDR} =~ /^([^`]+)$/ ? $1 : '';

	$input
}

sub _input_term {
	my $obj	= shift();

	my $input	= { map {
		my @t = split /&|=/ => $_, 2;
		$t[0] => ($t[1] ? $t[1] : length( $t[1] ) ? 0 : '')
	} @ARGV };

 	$obj->charge_meta(_request => [ @ARGV ]);

	$input
}

sub _input_edit {
	my $obj	= shift();

	my $input	= { map {split /&|=/} @ARGV };

 	$obj->charge_meta(_request => [ @ARGV ]);

	$input
}

sub _input_std {
	my $obj	= shift();

	my $stdin = <STDIN> || '';
	chomp $stdin;
	my $input	= { split /\s*[,=|]\s*/ => $stdin };

 	$obj->charge_meta(_request => $stdin);

	$input
}

1;



