package BVA::KALE::DBI;

$BVA::KALE::DBI::VERSION	= '1.00.000'; # 2020-08-04 bva@cruzio.com

use strict;
use warnings;
#use autodie;


## _DBI  The basic database interface
sub _DBI {
	my $obj				= shift; # $_[0];
	local *::KEY		= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };
	my %args;

	if (ref($_[0]) =~ /HASH/) {
		%args = %{ $_[0] }
	} elsif (@_>1) {
		push @_ => '' if @_ % 2;
		%args = @_;
	} else {
		%args	= ( driver => shift || '' )
	}

	unless ($args{driver}) {
		$::KEY{_db_driver}	= '';
		require BVA::KALE::DATA;
	}
	$::KEY{_db_driver}	= $args{driver} || $::KEY{_db_driver} || '';

}

## dbi
## A wrapper around the core DBI method
sub dbi ($;@) {
	my $obj				= shift;
	local *::KEY		= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

	$::KEY{_dbi}		||= $obj->_DBI(@_);
}

## dbh
## Returns the UI object's database handler
## Creates the handler if necessary, passing its args to db_connect()
## Stores the database handler in the metadata fld _dbh
sub dbh ($;@) {
	my $obj				= shift;
	local *::KEY		= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

#   	$::KEY{_dbh} 		||= $obj->dbi->dbh || $obj->db_connect(@_) || '';  # changed 2012-08-31  ||=
  	$::KEY{_dbh} 		||= $obj->dbi->dbh || $obj->dbi_connect(@_) || '';  # changed 2020-08-04 dbi_connect
}

## db_prepare
## Prepares a statement handler with the optional args.
## Defaults to 'SELECT' (select all fields of all records)
## Returns a statement handler for execution
## Also stores the statement handler in the metadata fld _sth, accessible with method ->sth()
sub db_prepare ($;@) {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

 	$::KEY{_sth} 			= @_ ? $obj->dbh->prepare(shift(@_),@_) : $obj->dbh->prepare('SELECT') || '';

	if ( $::KEY{_sth}->{NAME_lc} ) {
		my @itr_hdr			= @{ $::KEY{_sth}->{NAME_lc} };
		$::KEY{_sth}->bind_columns( \( @::KEY{ @itr_hdr } ));
	}

	return $::KEY{_sth};
}

sub db_structure ($;@) {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

 	$::KEY{_db_struct} 	= $obj->dbh->struct() || '';
}

sub db_table_info {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

	return unless $obj->dbh();

	my $driver	= $::KEY{_db_driver} || '';
	if ($driver) {
		if ($driver eq 'SQLite') {
			my $table_name		= shift;
			my $tableInfo_sth	= $obj->dbh->prepare(qq{PRAGMA table_info($table_name)});
			$tableInfo_sth->execute() or return;
			my @flds;
			my %meta;
			while (my $col = $tableInfo_sth->fetchrow_hashref()) {
				my $field	= $col->{name};
				push @flds	=> $field;
				$meta{$field}	= {
					fld		=> $field,
					label	=> join( ' ' => map { ucfirst($_) } split /[ _]/ => $field),
					type	=> $col->{type} || 'TEXT',
					size	=> 24,
					col		=> $col->{cid} || '',
					packpat	=> 'A24',
					colfmt	=> ($col->{type} =~ /INTEGER|NUMBER/ ? '%#.#s' : '%-24.24s'),
					default	=> $col->{dflt_value} || '',
					key		=> $col->{pk} || 0,
					null	=> $col->{dflt_value} || '',
				};
			}
			return {
				fields	=> [@flds],
				_flds	=> [@flds],
				_meta	=> { %meta },
			};
		} elsif ($driver eq 'KALE' ) {
			return {
				fields => [ $obj->dbh->fields ],
				_flds			=> [ $obj->dbh->fields ],
				_meta			=> $obj->dbh->meta,
				_type_RE		=> $obj->dbh->type_RE,
				_struct			=> $obj->dbh->db_struct,
			};
		} elsif ($driver eq 'DB_CSV') {

		}
	} else {
		return {
			fields => [ $obj->dbh->fields ],
			_flds			=> [ $obj->dbh->fields ],
			_meta			=> $obj->dbh->meta,
			_type_RE		=> $obj->dbh->type_RE,
			_struct			=> $obj->dbh->db_struct,
		};
	}
}

sub db_table_cols {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

	return unless $obj->dbh();

	my $driver	= $::KEY{_db_driver} || '';
	if ($driver) {
		if ($driver eq 'SQLite') {
			my $table_name		= shift;
			my $tableInfo_sth	= $obj->dbh->prepare(qq{PRAGMA table_info($table_name)});
			$tableInfo_sth->execute();
			my @flds;
			while (my $col = $tableInfo_sth->fetchrow_arrayref()) {
				push @flds => $col->[1];
			}
			return [@flds];
		} elsif ($driver eq 'KALE' ) {
			return [ $obj->dbh->fields ];
		} elsif ($driver eq 'DB_CSV') {

		}
	}
}

## sth
## Returns the current statement handler,
## or returns false with an error message if no statement handler exists.
sub sth ($;@) {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

	unless ($::KEY{_sth}) {
		$obj->charge_err( "This database handler has not prepared a statement handler." );
		return;
	}

 	$::KEY{_sth};
}

## auto_sth
## Returns the current statement handler,
## creating a new one if a) none exists, or
## b) if a statement is provided as an argument.
sub auto_sth ($;@) {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

 	$::KEY{_sth} 			= @_ ? $obj->db_prepare(shift(@_),@_) : $::KEY{_sth} ? $::KEY{_sth} : $obj->db_prepare();
}

## sth_destroy
## Deletes the current statement handler, returning it
## or returns false with an error message if no statement handler exists.
sub sth_destroy ($;@) {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

	unless ($::KEY{_sth}) {
		$obj->charge_err( "No statement handler to delete." );
		return
	}

	delete $::KEY{_sth} || '';
}


## db_cursor
## Returns a response from the statement handler's iterator, according to the
## optional arg.
## [hdr hdr_str hdr_pat_str pat rec_pat msg sel where stmt pos reset array arrayref hash hashref row str]
## Returns a hashref of the next record if no optional arg is provided.
sub db_cursor ($;$) {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

	return $::KEY{_sth}->cursor(shift) if $::KEY{_sth} && $::KEY{_sth}->{iterator};

	return;
}

## db_charge
## Charges the object's fields with data from the next record from the iterator;
## returns false if there is no statement handler, or if the
## iterator has already emitted the last record and not been reset.
## Charging is restricted to any optional args that are valid fields
## available from the iterator (ie, specified by the handler's SELECT list);
## if no args are provided, all fields available from the iterator are charged.
##
## NOTE: db_charge IMMEDIATELY clears ALL data fields associated with the database,
## not just the fields available or requested from the iterator;
## this happens even if there turns out to be no handler or no remaining record.
sub db_charge ($;@) {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

 	$obj->clear(@{ $::KEY{_dbh}->{_head} || [] });

 	return unless $::KEY{_sth};

 	my $data			= $::KEY{_sth}->fetchrow_hashref;
 	return unless $data;

 	my @itr_hdr			= @{ $::KEY{_sth}->cursor('hdr') };
 	my %itr_flds		= map { $_ => 1 } @itr_hdr;
	my @flds			= @_ ? grep( { $itr_flds{$_} } @_ ) : @itr_hdr;

 	$obj->charge_these([@flds], @$data{@flds});
}

# sub dbi_charge ($;@) {
# 	my $obj				= shift;
# 	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };
#
#  	return unless $::KEY{_sth};
#
#  	my @itr_hdr			= @{ $::KEY{_sth}->{NAME_lc} };
#
#  	#$obj->clear( [@itr_hdr] || [] );
#
#  	$::KEY{_sth}->fetch;
# #  	return unless %data;
# #
# #  	my %itr_flds		= map { $_ => 1 } @itr_hdr;
# # 	my @flds			= @_ ? grep( { $itr_flds{$_} } @_ ) : @itr_hdr;
# #
# #  	$obj->charge_these([@flds], @data{@flds});
# }



## db_clear
## clears ALL data fields associated with the database
sub db_clear ($;@) {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

 	$obj->clear(@{ $::KEY{_dbh}->{_head} });

	%::KEY
}

## dbi_connect
## A wrapper around the dbi's connect(), allowing args to be tweaked
## before they're passed to the dbi's connect()
## Automatically infuses the database's meta-data.
sub dbi_connect ($;@) {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

	my %args;
	my $dbh;

	if (ref($_[0]) =~ /HASH/) {
		%args = %{ $_[0] }
	} elsif (@_>1) {
		push @_ => '' if @_ % 2;
		%args = @_;
	} else {
		%args	= ( file => shift )
	}
	my $driver	= $args{driver} || $::KEY{_db_driver} || '';
	if ($driver) {
		if ($driver eq 'SQLite') {
			require DBI;
			my $dns	= $args{dns} || $args{db} || $args{file} || '';
			return unless $dns;
			$dbh	= DBI->connect("dbi:SQLite:dbname=${dns}","","");
			#return unless $dbh;
			$obj->charge_err( "Connect problem: with $dns: $DBI::errstr\n")
					and return unless $dbh;
		} elsif ($driver eq 'DB_CSV') {
			require DBI;
			my $dns	= $args{dns} || $args{db_dir} || $args{f_dir} || '';
			return unless $dns;
			$dbh	= DBI->connect("dbi:CSV:", undef, undef, { f_dir => $dns });
			return unless $dbh;
		} elsif ($driver eq 'KALE') {
			require BVA::KALE::DATA;
			my $dns	= $args{dns} || $args{db} || $args{file} || '';
			return unless $dns;
			$args{input_sep}	||= "\t";
			$dbh 				= BVA::KALE::DATA->init()->connect(\%args)
				or $obj->charge_err( "Connect problem: with $dns\n")
					and return;
		}
	} else {
		if ($args{dbx}) {
			$dbh	= do $args{dbx};
		} elsif ( ($args{dbx} = $args{file} || $args{db} || '') =~ /\.dbx$/ ) {
			$dbh	= do $args{dbx};
		} else {
			$args{input_sep}	||= "\t";
			$dbh 				= BVA::KALE::DATA->init()->connect(\%args);
		}
		if ($dbh) {
			$obj->charge_db_meta($dbh)
		} else {
			$obj->charge_err( "Connect problem:" . $obj->dbh->messages('err') );
			return
		}
	}
	#$obj->charge_meta(_dbh => $dbh);
	$::KEY{_dbh}	= $dbh;
	$dbh;
}

sub make_table {
	my $obj		= shift;
	return unless $obj->data('_dbh');
	my $table_name	= shift || 'temp';
	my @flds		= @_;
	my @cols		= ref($flds[0]) ? @{ $flds[0] } : @flds;
	@cols			= map { $_ =~ s/^\s*|\s*$//g; $_ || () } @cols;
	$obj->dbh->do( qq{DROP TABLE IF EXISTS $table_name;} )
		or $obj->hey(DBI::errstr() . "\n");
	my $ifnot	= '';
	if ($obj->data('_db_driver') eq 'DB_CSV') {
		$obj->form(	qq{	[:fieldname] CHAR (64)});
	} else {
		$obj->form(	qq{	'[:fieldname]'	[:fieldtype]	DEFAULT [:fielddef] });
	}
	my $type_flag;
	for (0..$#cols) {
		if ($cols[$_] =~ /^:(INT|TEXT|NUM|BLOB|BOOL|CLEAR)$/) {
			$type_flag	= $1;
			if ($type_flag eq 'CLEAR') {
				$type_flag = '';
			} else {
				$obj->charge_these(['fieldtype', 'fielddef'],
					$type_flag eq 'TEXT' ? ('TEXT', "''")
					: $type_flag eq 'INT' ? ('INT', '0')
					: $type_flag eq 'NUM' ? ('NUM', '0')
					: $type_flag eq 'BOOL' ? ('INT', '0')
					: $type_flag eq 'BLOB' ? ('BLOB', '0')
					: ('TEXT', "''")
				);
			}
			next;
		}
		if ($cols[$_] =~ /(^num_|num$|count$|sum$)/i) {
			$obj->charge_these(['fieldtype', 'fielddef'],('INT', '0')) unless $type_flag;
		} elsif ($cols[$_] =~ /(^pct_|_pct$|Pct$|^avg_|_avg$|Avg$)/i) {
			$obj->charge_these(['fieldtype', 'fielddef'],('NUM', '0.0')) unless $type_flag;
		} elsif ($cols[$_] =~ /^(.*?):INT$/i) {
			$cols[$_]	= $1;
			$obj->charge_these(['fieldtype', 'fielddef'],('INT', '0')) unless $type_flag;
		} elsif ($cols[$_] =~ /^(.*?):BOOL$/i) {
			$cols[$_]	= $1;
			$obj->charge_these(['fieldtype', 'fielddef'],('INT', '0')) unless $type_flag;
		} elsif ($cols[$_] =~ /^(.*?):NUM$/i) {
			$cols[$_]	= $1;
			$obj->charge_these(['fieldtype', 'fielddef'],('NUM', '0.0')) unless $type_flag;
		} elsif ($cols[$_] =~ /^(.*?):BLOB$/i) {
			$cols[$_]	= $1;
			$obj->charge_these(['fieldtype', 'fielddef'],('BLOB', "''")) unless $type_flag;
		}   elsif ($cols[$_] =~ /^(.*?):TEXT$/i) {
			$cols[$_]	= $1;
			$obj->charge_these(['fieldtype', 'fielddef'],('TEXT', "''")) unless $type_flag;
		} else {
			$obj->charge_these(['fieldtype', 'fielddef'],('TEXT', "''")) unless $type_flag;
		}
		$obj->charge(fieldname => $cols[$_]);
		$obj->buffer_resolved();
	}
	my $sql	= <<TBL;
CREATE TABLE $ifnot $table_name (
${ \join(",\n" => $obj->flush) }
);
TBL

#	my $sql	= qq{CREATE TABLE $table_name (${ \join(", " => $obj->flush) })};

	$obj->dbh->do($sql);

	return $sql;
}

sub db_create_table {
	my $obj		= shift;
	return unless $obj->data('_dbh');
	my $table_name	= shift || 'temp';
	my %args		= ref($_[0]) ? %{ shift() } : (drop_existing => 0);
	if ($args{drop_existing}) {
		$obj->dbh->do( qq{DROP TABLE IF EXISTS $table_name;} )
			or $obj->hey(DBI::errstr() . "\n");
	}
	if ($obj->db_table_cols($table_name)->[0]) {
		return wantarray ? @{$obj->db_table_cols($table_name)} : $obj->db_table_cols($table_name);
	}

	my @cols			= map { $_ =~ /^\s*(.*?)\s*$/; $1 || () } @_;

	if ($obj->data('_db_driver') eq 'DB_CSV') {
		$obj->form(	qq{	[:fieldname] CHAR (64)});
	} else {
		$obj->form(	qq{	'[:fieldname]'	[:fieldtype]	DEFAULT [:fielddef] });
	}
	my $type_flag;
	for (0..$#cols) {
		if ($cols[$_] =~ /^:(INT|TEXT|NUM|BLOB|BOOL|CLEAR)$/) {
			$type_flag	= $1;
			if ($type_flag eq 'CLEAR') {
				$type_flag = '';
			} else {
				$obj->charge_these(['fieldtype', 'fielddef'],
					$type_flag eq 'TEXT' ? ('TEXT', "''")
					: $type_flag eq 'INT' ? ('INT', '0')
					: $type_flag eq 'NUM' ? ('NUM', '0')
					: $type_flag eq 'BOOL' ? ('INT', '0')
					: $type_flag eq 'BLOB' ? ('BLOB', '0')
					: ('TEXT', "''")
				);
			}
			next;
		}
		my ($type,$def)	= ('','');
		if ($cols[$_] =~ /(^num_|num$|count$|sum$)/i) {
			($type,$def)	= ('INT', '0');
		} elsif ($cols[$_] =~ /(^pct_|_pct$|Pct$|^avg_|_avg$|Avg$)/i) {
			($type,$def)	= ('NUM', '0.0');
		} elsif ($cols[$_] =~ /^(.*?):INT$/i) {
			$cols[$_]	= $1;
			($type,$def)	= ('INT', '0');
		} elsif ($cols[$_] =~ /^(.*?):BOOL$/i) {
			$cols[$_]	= $1;
			($type,$def)	= ('INT', '0');
		} elsif ($cols[$_] =~ /^(.*?):NUM$/i) {
			$cols[$_]	= $1;
			($type,$def)	= ('NUM', '0.0');
		} elsif ($cols[$_] =~ /^(.*?):BLOB$/i) {
			$cols[$_]	= $1;
			($type,$def)	= ('BLOB', "''");
		} elsif ($cols[$_] =~ /^(.*?):PRI$/i) {
			$cols[$_]	= $1;
			($type,$def)	= ('TEXT PRIMARY KEY', "''");
		} elsif ($cols[$_] =~ /^(.*?):PKI$/i) {
			$cols[$_]	= $1;
			($type,$def)	= ('INTEGER PRIMARY KEY', "''");
		} elsif ($cols[$_] =~ /^(.*?):PKT$/i) {
			$cols[$_]	= $1;
			($type,$def)	= ('TEXT PRIMARY KEY', "''");
		} elsif ($cols[$_] =~ /^(.*?):TEXT$/i) {
			$cols[$_]	= $1;
			($type,$def)	= ('TEXT', "''");
		} else {
			($type,$def)	= ('TEXT', "''");
		}
		$obj->charge_these(['fieldtype', 'fielddef'],$type, $def) unless $type_flag;
		$obj->charge(fieldname => $cols[$_]);
		$obj->buffer_resolved();
	}
	my $sql	= <<TBL;
CREATE TABLE $table_name (
${ \join(",\n" => $obj->flush) }
);
TBL

	$obj->dbh->do($sql);

	return wantarray ? @cols : [@cols];
}



## db_connect
## A wrapper around the dbi's connect(), allowing args to be tweaked
## before they're passed to the dbi's connect()
## Automatically infuses the database's meta-data.
sub db_connect ($;@) {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

	my %args;
	my $dbh;

	if (ref($_[0]) =~ /HASH/) {
		%args = %{ $_[0] }
	} elsif (@_>1) {
		push @_ => '' if @_ % 2;
		%args = @_;
	} else {
		%args	= ( file => shift )
	}

	if ($args{dbx}) {
		$dbh	= do $args{dbx};
	} elsif ( ($args{dbx} = $args{file} || $args{db} || '') =~ /\.dbx$/ ) {
		$dbh	= do $args{dbx};
	} else {
		$args{input_sep}	||= "\t";
		$dbh 				= $obj->dbi()->connect(\%args);
	}

	if ($dbh) {
		$obj->charge_db_meta($dbh)
	} else {
# 		warnings::warnif('io', "Connect problem:" . $dbi->messages('err'));
		$obj->charge_err( "Connect problem:" . $obj->dbi()->messages('err') );
		return
	}
}

## dbx_connect
## A wrapper around the dbi's connect(), allowing args to be tweaked
## before they're passed to the dbi's connect()
## Automatically infuses the database's meta-data.
## dbx_connect uses a dbx initialization cache for quicker repeat connects.
## Will use an existing dbx cache if the filename is given with the arg 'dbx'
## or if the filename of the  'file' or 'db' arg ends in '.dbx'.
## Otherwise, checks for an existing dbx cache, and creates
## one if none exists.
## Always creates a new cache if arg 'refresh' has a TRUE value.
sub dbx_connect ($;@) {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

	my (%args,$dbh,$dbx);

	if (ref($_[0]) =~ /HASH/) {
		%args = %{ $_[0] };
	} elsif (@_>1) {
		push @_ => '' if @_ % 2;
		%args = @_;
	} else {
		%args	= ( file => shift );
	}
	$args{input_sep}	||= "\t";

	if ($args{refresh}) {
		my $tmp_dbh	= $obj->dbi()->connect(\%args)
					or $obj->charge_err( "Connect problem:" . $obj->dbi()->messages('err') ) and return;
		$dbx	= $tmp_dbh->save_connection()
					or $obj->charge_err( "Save Connect problem:" . $obj->dbi()->messages('err') ) and return;
	} elsif ($args{dbx}) {
		$dbx	= $args{dbx};
	} elsif ( ($args{dbx} = $args{file} || $args{db} || '') =~ /\.dbx$/ ) {
		$dbx	= $args{dbx};
	} elsif ( ($args{dbx} = $args{file} || $args{db} || '') =~ s/^(.*)\.txt$/"$1.dbx"/e  ) {
		if (-e $args{dbx}) {
			$dbx	= $args{dbx};
		}
	}

	unless ($dbx) {
		my $new_dbh = $obj->dbi()->connect(\%args)
			or $obj->charge_err( "Connect problem:" . $obj->dbi()->messages('err') ) and return;
		$dbx	= $new_dbh->save_connection();
	}

	$dbh	= do $dbx;
	if ($dbh) {
		$obj->charge_db_meta($dbh)
	} else {
# 		warnings::warnif('io', "Connect problem:" . $dbi->messages('err'));
		$obj->charge_err( "Connect problem:" . $obj->dbi()->messages('err') );
		return
	}
}

## charge_db_meta
## Automatically infuses meta-data from the database handler.
## Creates the handler if necessary, passing its args to db_connect().
sub charge_db_meta ($;@) {
	my $obj				= shift;
	local *::KEY			= $obj->invert(); # ref($obj) eq __PACKAGE__ ? $obj : *{ $obj };

	my $dbh				= $_[0] || $obj->db_connect(@_)
		or return '';

	## Give the KALE object the database handler
	## and get the meta-data from the database
	$obj->charge_meta({
 		_dbh			=> $dbh,
		_flds			=> [ $dbh->fields ],
		_meta			=> $dbh->meta,
		_type_RE		=> $dbh->type_RE,
		_struct			=> $dbh->db_struct,
	});

	$obj->list_items($dbh->db_base_name() . '_fld_list', $dbh->fields);
	$obj->list_items($dbh->db_base_name() . '_label_list', $dbh->labels);

}


1;



