package BVA::KALE::DATA::PROC;
## Procedures
## Used in SELECT to modify return values with NO change to db record
## Used in SELECT, BROWSE, INDEX, COUNT to collect, summarize, & count data with NO change to db record
## Used in UPDATE to modify db record as it is updated

@BVA::KALE::DATA::PROC::tracks	= qw/COUNTS DUPES UNIQUE SUMS RECORDS TOTALS BYTES REDUCE IF DATES/;

sub printout {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	my $line	= sprintf "%8d: " . join(' ' =>
					map { ($self->col_formats($_))[0] || '%24s' } @flds),
					($self->{monitor_count}++ || 0) + 1,
					map {
						exists $self->{CURRENT}{ROW}->{$_} ? $self->{CURRENT}{ROW}->{$_} : ''
							|| ($_ =~ /^#(.*)$/ ? $self->{CURRENT}{$1} || '' : '')
								|| $_
					} @flds;
	print STDOUT $line, "\n";
}

sub monitor {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? grep( { $self->{_hd_nums}->{$_} } @_[1..$#_] ) : @{ $self->{_head} }[$self->{id_col} || 0];

	my $line	= sprintf "%8d Record%s OK: " . join(' ', $self->col_formats(@flds)) . "\r",
					($self->{monitor_count}++ || 0) + 1,
					($self->{monitor_count} == 1 ? ' ' : 's'),
					@{ $self->{CURRENT}{ROW} }{@flds};
	print STDOUT $line;
}

sub trim0 {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	for my $K (@flds) {
		$self->{CURRENT}{ROW}->{$K} =~ s/^0+(.*)/$1/
	}
}

sub trunc_right {
	my $self	= $_[0];
	my @flds	= @_ > 2 ? @_[2..$#_] : @{ $self->{_head} };
	my $width	= $_[1] =~ /^\d+$/ ? $_[1] : 0;
	for my $K (@flds) {
		my $w	= $width || $self->size($K);
		$_[0]->{CURRENT}{ROW}->{$K} =~ s/^(.{$w}).*$/$1/e;
	}
}

sub trunc_dt_to_date {
	my $self	= $_[0];
	my @flds	= @_ > 2 ? @_[2..$#_] : @{ $self->{_head} };
	for my $K (@flds) {
		$_[0]->{CURRENT}{ROW}->{$K} =~ s/^(\d\d\d\d-\d\d-\d\d).*$/$1/e;
	}
}

sub zero_pad {
	my $self	= $_[0];
	my @flds	= @_ > 2 ? @_[2..$#_] : @{ $self->{_head} };
	my $width	= $_[1] =~ /^\d+$/ ? $_[1] : 0;
	for my $K (@flds) {
		my $w	= $width || $self->size($K);
		$_[0]->{CURRENT}{ROW}->{$K} =~ s/^(\d+)(.*)$/ $w -= length($2);sprintf(qq{%0.${w}d%s}, $1, $2)/e;
	}
}			#

sub upcase {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	for my $K (@flds) {
		$_[0]->{CURRENT}{ROW}->{$K} = uc ${ $self->{CURRENT}{ROW} }{$K}
	}
}

sub lowcase {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	for my $K (@flds) {
		$_[0]->{CURRENT}{ROW}->{$K} = lc ${ $self->{CURRENT}{ROW} }{$K}
	}
}

sub track {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	for my $fld (@flds) {
		$_[0]->{TRACK}->{$fld}	= $self->{CURRENT}{ROW}->{$fld};
	}
}

sub break {
	my $self		= $_[0];
	my @flds		= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	my @fld_cols	= sort { $a <=> $b } $self->columns(@flds);
	my %pat_cols	= map { $_ => 1 } @flds;
	my $sep			= $self->{_input_sep};
	my $end			= $self->{_record_sep};
	my $break_pat	= join '' => map {	$pat_cols{$_} ?
							qr{\s*$self->{CURRENT}{ROW}->{$_}\s*(?:$sep.*|)$end?} :
							qr{[^$sep]*$sep}
					} @{ $self->{_head} }[ 0..$fld_cols[-1] ];
	push @{ $_[0]->{BREAK} } => sub { $_[1] !~ /^$break_pat/ };
}

sub next {
	my $self		= $_[0];
	my @flds		= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	my @fld_cols	= sort { $a <=> $b } $self->columns(@flds);
	my %pat_cols	= map { $_ => 1 } @flds;
	my $sep			= $self->{_input_sep};
	my $end			= $self->{_record_sep};
	my $next_pat	= join qr{$sep} => map {	$pat_cols{$_} ?
										qr{ *$self->{CURRENT}{ROW}->{$_} *} :
										qr{[^$sep]*}
								} @{ $self->{_head} }[ 0..$fld_cols[-1] ];
	$_[0]->{NEXT}->[0] = sub { $_[1] =~ /^$next_pat/ };
}

sub unique {
	my $self		= $_[0];
	my @flds		= @_ > 1 ? @_[1..$#_] : ($self->{id_fld});
	my @fld_cols	= sort { $a <=> $b } $self->columns(@flds);
	unless (@fld_cols) {
		$_[0]->{NEXT}->[0] = sub { 0 };
		return;
	}
	my @sorted_flds	= $self->fields(@fld_cols);
	my $key			= join '-' => @sorted_flds;
	$_[0]->{UNIQUE}->{$key}->{ join '-' => map { $self->{CURRENT}{ROW}->{$_} } @sorted_flds }++;
	my $sep			= $self->{_input_sep};
	my $end			= $self->{_record_sep};
	my %pat_cols	= map { $_ => 1 } @flds;
	my $umulti_pat	= join '' => map {
		$pat_cols{$_} ? qr{ *([^$sep]*) *(?:$sep|$end)} : qr{[^$sep]*$sep}
	} $self->fields(0..$fld_cols[-1]);

	$_[0]->{NEXT}->[0] = sub {
		my @matches = $_[1] =~ /^$umulti_pat/;
		@matches && $_[0]->{UNIQUE}->{$key}->{ join '-' => @matches };
	};
}

sub count_true {
	my $self		= $_[0];
	my @flds		= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	for my $fld (@flds) {
		$_[0]->{COUNTS}->{$fld}++ if $self->{CURRENT}{ROW}->{$fld}
	}
}

sub count_if {
	my $self			= $_[0];
	my $unique			= @_ > 1 ? $_[1] : $self->{_head}->[$self->{_id_col}];
	my @flds			= @_ > 2 ? @_[2..$#_] : @{ $self->{_head} };
	if ($self->{CURRENT}{ROW}->{$unique}) {
		$_[0]->{IF}->{$unique}->{ 'Total' }++;
		$_[0]->{IF}->{$unique}->{ $_ } += $self->{CURRENT}{ROW}->{$_} for @flds;
	}
}

sub count_binary {
	my $self		= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : grep { $self->{_types}{$_} eq 'b' } @{ $self->{_head} };
	for my $fld (@flds) {
		$_[0]->{COUNTS}->{$fld}++ if $self->{CURRENT}{ROW}->{$fld}
	}
}

sub count_binary_bc {
	my $self		= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : grep { $self->{_types}{$_} =~ /b|c/ } @{ $self->{_head} };
	for my $fld (@flds) {
		$_[0]->{COUNTS}->{$fld}++ if $self->{CURRENT}{ROW}->{$fld}
	}
}

sub count_unique {
	my $self		= $_[0];
	my @flds		= @_ > 1 ? grep( { $self->{_hd_nums}->{$_} } @_[1..$#_] ) : @{ $self->{_head} };
	for my $fld (@flds) {
		$_[0]->{COUNTS}->{$fld}->{ $self->{CURRENT}{ROW}->{$fld} }++
	}
}

sub count_unique_by_date {
	my $self		= $_[0];
	my @flds		= @_ > 1 ? grep( { $self->{_hd_nums}->{$_} } @_[1..$#_] ) : @{ $self->{_head} };
	for my $fld (@flds) {
		$_[0]->{DATES}->{$fld}->{ $self->{CURRENT}{ROW}->{$fld} }++
	}
}

sub count_unique_multi {
	my $self		= $_[0];
	my @flds		= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	my $isep		= $self->{_item_sep};
	for my $fld (@flds) {
		my @actuals	= split /\s*(?:$isep)\s*/ => $self->{CURRENT}{ROW}->{$fld};
		for (@actuals) {
			$_[0]->{COUNTS}->{$fld}->{ $_ }++
		}
	}
}

sub cross_tab {
	my $self		= $_[0];
	my @flds		= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };

	# Binary Fields
	my @binary_flds	= grep { $self->{_types}{$_} and $self->{_types}{$_} eq 'b' } @flds;

	# Value Fields (for now, just recognized fields not type 'b')
	my @value_flds	= grep { $self->{_types}{$_} and $self->{_types}{$_} ne 'b' } @flds;

	for my $fld (@binary_flds) {
		next unless $self->{CURRENT}{ROW}->{$fld};
		$_[0]->{COUNTS}->{$fld}++;

		for my $cross_fld (@binary_flds) {
			next if $fld eq $cross_fld;
			next unless $self->{CURRENT}{ROW}->{$cross_fld};
			$_[0]->{COUNTS}->{CROSS}->{ $cross_fld }->{ $fld }++;
		}

		for my $cross_fld (@value_flds) {
			next unless $self->{CURRENT}{ROW}->{$cross_fld};
			$_[0]->{COUNTS}->{CROSS}->{ $self->{CURRENT}{ROW}->{$cross_fld} }->{ $fld }++;
		}
	}

	for my $fld (@value_flds) {
		next unless $self->{CURRENT}{ROW}->{$fld};
# 		$_[0]->{COUNTS}->{$fld}++;
		$_[0]->{COUNTS}->{ $self->{CURRENT}{ROW}->{$fld} }++;
		$_[0]->{COUNTS}->{"$fld:$self->{CURRENT}{ROW}->{$fld}"}++;

		for my $cross_fld (@binary_flds) {
			next unless $self->{CURRENT}{ROW}->{$cross_fld};
			$_[0]->{COUNTS}->{CROSS}->{ $cross_fld }->{ $self->{CURRENT}{ROW}->{$fld} }++;
			#$_[0]->{COUNTS}->{CROSS}->{ $self->{CURRENT}{ROW}->{$cross_fld} || "*No $cross_fld" }->{ $self->{CURRENT}{ROW}->{$fld} }++;
		}

		for my $cross_fld (@value_flds) {
			next unless $self->{CURRENT}{ROW}->{$cross_fld};
			next if $fld eq $cross_fld;
			$_[0]->{COUNTS}->{CROSS}->{ $self->{CURRENT}{ROW}->{$cross_fld} }->{ $self->{CURRENT}{ROW}->{$fld} }++;
		}
	}
}

sub cross_tab_reduce {
	my $self		= $_[0];
	my @flds		= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };

	my $reduce_fld	= shift @flds;
	my $reduction	= $self->{CURRENT}{ROW}->{$reduce_fld};

	$_[0]->{COUNTS}->{REDUCE}->{ $reduce_fld }->{num}++ ;

	unless ( $_[0]->{UNIQUE}->{ $reduction }++) {
		$_[0]->{COUNTS}->{REDUCE}->{ $reduce_fld }->{loc}++ ;
	}

	# Binary Fields
	my @binary_flds	= grep { $self->{_types}{$_} eq 'b' } @flds;

	# Value Fields (for now, just recognized fields not type 'b')
	my @value_flds	= grep { $self->{_types}{$_} ne 'b' } @flds;

	for my $bin_fld (@binary_flds) {
		next unless $self->{CURRENT}{ROW}->{$bin_fld};
		$_[0]->{REDUCE}->{$bin_fld}->{num}++;
		unless ($_[0]->{UNIQUE}->{ $bin_fld . $reduction }++) {
			$_[0]->{REDUCE}->{ $bin_fld }->{loc}++ ;
		}

		for my $cross_bin_fld (@binary_flds) {
			next if $bin_fld eq $cross_bin_fld;
			next unless $self->{CURRENT}{ROW}->{$cross_bin_fld};
			$_[0]->{REDUCE}->{CROSS}->{ $cross_bin_fld }->{ $bin_fld }->{num}++;
			unless ($_[0]->{UNIQUE}->{  $cross_bin_fld . $bin_fld . $reduction }++) {
				$_[0]->{REDUCE}->{CROSS}->{ $cross_bin_fld }->{ $bin_fld }->{loc}++ ;
			}
		}

		for my $cross_val_fld (@value_flds) {
			$_[0]->{REDUCE}->{CROSS}->{ $self->{CURRENT}{ROW}->{$cross_val_fld} }->{ $bin_fld }->{num}++;
			unless ($_[0]->{UNIQUE}->{ $self->{CURRENT}{ROW}->{$cross_val_fld} . $bin_fld . $reduction }++) {
				$_[0]->{REDUCE}->{CROSS}->{ $self->{CURRENT}{ROW}->{$cross_val_fld} }->{ $bin_fld }->{loc}++ ;
			}
		}
	}

	for my $val_fld (@value_flds) {
		next unless $self->{CURRENT}{ROW}->{$val_fld};
		$_[0]->{REDUCE}->{$val_fld}->{num}++;
		$_[0]->{REDUCE}->{ $self->{CURRENT}{ROW}->{$val_fld} }->{num}++;
		unless ($_[0]->{UNIQUE}->{ $val_fld . $reduction }++) {
			$_[0]->{REDUCE}->{ $val_fld }->{loc}++ ;
		}
		unless ($_[0]->{UNIQUE}->{ $self->{CURRENT}{ROW}->{$val_fld} . $reduction }++) {
			$_[0]->{REDUCE}->{ $self->{CURRENT}{ROW}->{$val_fld} }->{loc}++;
		}
		$_[0]->{COUNTS}->{"$val_fld:$self->{CURRENT}{ROW}->{$val_fld}"}++;

		for my $cross_bin_fld (@binary_flds) {
			next unless $self->{CURRENT}{ROW}->{$cross_bin_fld};
			$_[0]->{REDUCE}->{CROSS}->{ $cross_bin_fld }->{ $self->{CURRENT}{ROW}->{ $val_fld } }->{num}++;
			unless ($_[0]->{UNIQUE}->{ $cross_bin_fld . $self->{CURRENT}{ROW}->{ $val_fld } . $reduction }++) {
				$_[0]->{REDUCE}->{CROSS}->{ $cross_bin_fld }->{ $self->{CURRENT}{ROW}->{ $val_fld } }->{loc}++;
			}
		}

		for my $cross_val_fld (@value_flds) {
			next if $val_fld eq $cross_val_fld;
			$_[0]->{REDUCE}->{CROSS}->{ $self->{CURRENT}{ROW}->{$cross_val_fld} }->{ $self->{CURRENT}{ROW}->{$val_fld} }->{num}++;
			unless ($_[0]->{UNIQUE}->{ $self->{CURRENT}{ROW}->{$cross_val_fld} . $self->{CURRENT}{ROW}->{$val_fld} . $reduction }++) {
				$_[0]->{REDUCE}->{CROSS}->{ $self->{CURRENT}{ROW}->{$cross_val_fld} }->{ $self->{CURRENT}{ROW}->{$val_fld} }->{loc}++;
			}
		}
	}
}

sub cross_total {
	my $self		= $_[0];
	my $sum_fld		= $_[1];
	my @flds		= @_ > 2 ? @_[2..$#_] : @{ $self->{_head} };

	# Binary Fields
	my @binary_flds	= grep { $self->{_types}{$_} eq 'b' } @flds;

	# Value Fields (for now, just recognized fields not type 'b')
	my @value_flds	= grep { $self->{_types}{$_} and $self->{_types}{$_} ne 'b' } @flds;

	# Grand total of values in $sum_fld
	$_[0]->{SUMS}->{TOTAL}->{sum}	+= $self->{CURRENT}{ROW}->{$sum_fld};
	$_[0]->{SUMS}->{TOTAL}->{count}++;

	for my $fld (@binary_flds) {
		next unless $self->{CURRENT}{ROW}->{$fld};
		$_[0]->{SUMS}->{$fld}->{count}++;
		$_[0]->{SUMS}->{$fld}->{sum}	+= $self->{CURRENT}{ROW}->{$sum_fld};

		for my $cross_fld (@binary_flds) {
			next unless $self->{CURRENT}{ROW}->{$cross_fld};
			$_[0]->{SUMS}->{CROSS}->{ $cross_fld }->{ $fld }->{sum}	+= $self->{CURRENT}{ROW}->{$sum_fld};
			$_[0]->{SUMS}->{CROSS}->{ $cross_fld }->{ $fld }->{count}++;
		}

		for my $cross_fld (@value_flds) {
			# next unless $self->{CURRENT}{ROW}->{$cross_fld};
			$_[0]->{SUMS}->{CROSS}->{ $self->{CURRENT}{ROW}->{$cross_fld} || "*No $cross_fld" }->{ $fld }->{sum}	+= $self->{CURRENT}{ROW}->{$sum_fld};
			$_[0]->{SUMS}->{CROSS}->{ $self->{CURRENT}{ROW}->{$cross_fld} || "*No $cross_fld" }->{ $fld }->{count}++;
		}
	}

	for my $fld (@value_flds) {
		$_[0]->{SUMS}->{$self->{CURRENT}{ROW}->{$fld} || "*No $fld"}->{sum}	+= $self->{CURRENT}{ROW}->{$sum_fld};
		$_[0]->{SUMS}->{$self->{CURRENT}{ROW}->{$fld} || "*No $fld"}->{count}++;
		next unless $self->{CURRENT}{ROW}->{$fld};
		$_[0]->{SUMS}->{$fld}->{count}++;
		$_[0]->{SUMS}->{$fld}->{sum}								+= $self->{CURRENT}{ROW}->{$sum_fld};
		$_[0]->{SUMS}->{$fld}->{ $self->{CURRENT}{ROW}->{$fld} }	+= $self->{CURRENT}{ROW}->{$sum_fld};


		for my $cross_fld (@binary_flds) {
			next unless $self->{CURRENT}{ROW}->{$cross_fld};
			$_[0]->{SUMS}->{CROSS}->{ $cross_fld }->{ $self->{CURRENT}{ROW}->{$fld} }->{sum}	+= $self->{CURRENT}{ROW}->{$sum_fld};
			$_[0]->{SUMS}->{CROSS}->{ $cross_fld }->{ $self->{CURRENT}{ROW}->{$fld} }->{count}++;
		}

		for my $cross_fld (@value_flds) {
			#next if $fld eq $cross_fld;
			$_[0]->{SUMS}->{CROSS}->{ $self->{CURRENT}{ROW}->{$cross_fld} || "*No $cross_fld" }->{ $self->{CURRENT}{ROW}->{$fld} }->{sum}	+= $self->{CURRENT}{ROW}->{$sum_fld};
			$_[0]->{SUMS}->{CROSS}->{ $self->{CURRENT}{ROW}->{$cross_fld} || "*No $cross_fld" }->{ $self->{CURRENT}{ROW}->{$fld} }->{count}++;
		}
	}
}

sub sum_unique {
	my $self		= $_[0];
	my $sum_fld		= $_[1];
	my @flds		= @_ > 2 ? @_[2..$#_] : @{ $self->{_head} };

	# Binary Fields
	my @binary_flds	= grep { $self->{_types}{$_} eq 'b' } @flds;

	# Value Fields (for now, just recognized fields not type 'b')
	my @value_flds	= grep { $self->{_types}{$_} and $self->{_types}{$_} ne 'b' } @flds;

	# Grand total of values in $sum_fld
	$_[0]->{SUMS}->{TOTAL}->{sum}	+= $self->{CURRENT}{ROW}->{$sum_fld};
	$_[0]->{SUMS}->{TOTAL}->{count}++;

	for my $fld (@binary_flds) {
		next unless $self->{CURRENT}{ROW}->{$fld};
		$_[0]->{SUMS}->{$fld}->{count}++;
		$_[0]->{SUMS}->{$fld}->{sum}	+= $self->{CURRENT}{ROW}->{$sum_fld};

	}

	for my $fld (@value_flds) {
		$_[0]->{SUMS}->{$self->{CURRENT}{ROW}->{$fld} || "*No $fld"}->{sum}	+= $self->{CURRENT}{ROW}->{$sum_fld};
		$_[0]->{SUMS}->{$self->{CURRENT}{ROW}->{$fld} || "*No $fld"}->{count}++;
		next unless $self->{CURRENT}{ROW}->{$fld};
		$_[0]->{SUMS}->{$fld}->{count}++;
		$_[0]->{SUMS}->{$fld}->{sum}								+= $self->{CURRENT}{ROW}->{$sum_fld};
		$_[0]->{SUMS}->{$fld}->{ $self->{CURRENT}{ROW}->{$fld} }	+= $self->{CURRENT}{ROW}->{$sum_fld};

		for my $cross_fld (@value_flds) {
			#next if $fld eq $cross_fld;
			$_[0]->{SUMS}->{CROSS}->{ $self->{CURRENT}{ROW}->{$cross_fld} || "*No $cross_fld" }->{ $self->{CURRENT}{ROW}->{$fld} }->{sum}	+= $self->{CURRENT}{ROW}->{$sum_fld};
			$_[0]->{SUMS}->{CROSS}->{ $self->{CURRENT}{ROW}->{$cross_fld} || "*No $cross_fld" }->{ $self->{CURRENT}{ROW}->{$fld} }->{count}++;
		}

	}
}

sub cross_tab_cube {
	my $self		= $_[0];
	my @flds		= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };

	# Binary Fields
	my @binary_flds	= grep { $self->{_types}{$_} eq 'b' } @flds;

	# Value Fields (for now, just recognized fields not type 'b')
	my @value_flds	= grep { $self->{_types}{$_} and $self->{_types}{$_} ne 'b' } @flds;

	for my $fld (@binary_flds) {
		next unless $self->{CURRENT}{ROW}->{$fld};
		$_[0]->{COUNTS}->{"$fld Subtotal"}++;

		for my $cross_fld (@binary_flds) {
			next unless $self->{CURRENT}{ROW}->{$cross_fld};
			$_[0]->{COUNTS}->{CROSS}->{ $fld }->{ $cross_fld }++;
		}

		for my $cross_fld (@value_flds) {
			# next unless $self->{CURRENT}{ROW}->{$cross_fld};
			$_[0]->{COUNTS}->{CROSS}->{ $fld }->{ $cross_fld }->{ $self->{CURRENT}{ROW}->{$cross_fld} || "No $cross_fld" }++;
		}
	}

	for my $fld (@value_flds) {
		next unless $self->{CURRENT}{ROW}->{$fld};
		$_[0]->{COUNTS}->{$fld}->{"$fld Subtotal"}++;
		$_[0]->{COUNTS}->{$fld}->{$self->{CURRENT}{ROW}->{$fld}}++;

		for my $cross_fld (@binary_flds) {
			next unless $self->{CURRENT}{ROW}->{$cross_fld};
			$_[0]->{COUNTS}->{CROSS}->{ $fld }->{ $self->{CURRENT}{ROW}->{$fld} }->{ $cross_fld }++;
		}

		for my $cross_fld (@value_flds) {
			# next unless ($self->{CURRENT}{ROW}->{$cross_fld});
			next if ($fld eq $cross_fld);
			$_[0]->{COUNTS}->{CROSS}->{ $fld }->{ $self->{CURRENT}{ROW}->{$fld} }->{ $cross_fld }->{ $self->{CURRENT}{ROW}->{$cross_fld} || "No $cross_fld" }++;
		}
	}
}

sub gather_unique {
	my $self			= $_[0];
# 	my ($unique, @flds)	= @_ > 1 ? @_[1..$#_] : ($self->{_head}->[$self->{_id_col}], @{ $self->{_head} });
	my $unique			= @_ > 1 ? $_[1] : $self->{_head}->[$self->{_id_col}];
	my @flds			= @_ > 2 ? @_[2..$#_] : @{ $self->{_head} };
	$_[0]->{COUNTS}->{$unique}->{ $self->{CURRENT}{ROW}->{$unique} }[0]++;
	push @{ $_[0]->{COUNTS}->{$unique}->{ $self->{CURRENT}{ROW}->{$unique} } } => @{ $self->{CURRENT}{ROW} }{@flds}
}

sub gather_unique_records {
	my $self			= $_[0];
	my $unique			= @_ > 1 ? $_[1] : $self->{_head}->[$self->{_id_col}];
	$_[0]->{COUNTS}->{$unique}->{ $self->{CURRENT}{ROW}->{$unique} }[0]++;
	$_[0]->{RECORDS}->{$unique}->{ $self->{CURRENT}{ROW}->{$unique} } = $self->{CURRENT}{ROW};
}

sub collect_unique_records {
	my $self			= $_[0];
	my $unique			= $_[1];
	my @flds			= @_ > 2 ? @_[2..$#_] : @{ $self->{_head} };
	push @{ $_[0]->{RECORDS}->{$unique}->{ $self->{CURRENT}{ROW}->{$unique} } } => [ @{ $self->{CURRENT}{ROW} }{@flds} ];
}

sub catflds {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	$self->{CURRENT}{ROW}->{$flds[0]} = join '' => map { $self->{CURRENT}{ROW}->{$_} } @flds;
}

sub catflds_replace {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	$self->{CURRENT}{ROW}->{$flds[0]} = join '' => map { $self->{CURRENT}{ROW}->{$_} } @flds[1..$#flds];
}

sub catflds_hyphen {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	$self->{CURRENT}{ROW}->{$flds[0]} = join '-' => map { $self->{CURRENT}{ROW}->{$_} } @flds;
	$self->{CURRENT}{ROW}->{$flds[0]} =~ s/-+/-/g;
	$self->{CURRENT}{ROW}->{$flds[0]} =~ s/^-*(.*?)-*$/$1/g;
}

sub catflds_replace_hyphen {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	$self->{CURRENT}{ROW}->{$flds[0]} = join '-' => map { $self->{CURRENT}{ROW}->{$_} } @flds[1..$#flds];
	$self->{CURRENT}{ROW}->{$flds[0]} =~ s/-+/-/g;
	$self->{CURRENT}{ROW}->{$flds[0]} =~ s/^-*(.*?)-*$/$1/g;
}

sub catflds_period {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	$self->{CURRENT}{ROW}->{$flds[0]} = join '.' => map { $self->{CURRENT}{ROW}->{$_} } @flds;
}


sub catflds_replace_period {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	$self->{CURRENT}{ROW}->{$flds[0]} = join '.' => map { $self->{CURRENT}{ROW}->{$_} } @flds[1..$#flds];
}


sub catflds_tab {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	$self->{CURRENT}{ROW}->{$flds[0]} = join "\t" => map { $self->{CURRENT}{ROW}->{$_} } @flds;
}

sub catflds_replace_tab {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	$self->{CURRENT}{ROW}->{$flds[0]} = join "\t" => map { $self->{CURRENT}{ROW}->{$_} } @flds[1..$#flds];
}

sub catflds_space {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	$self->{CURRENT}{ROW}->{$flds[0]} = join " " => map { $self->{CURRENT}{ROW}->{$_} } @flds;
	$self->{CURRENT}{ROW}->{$flds[0]} =~ s/ +/ /g;
	$self->{CURRENT}{ROW}->{$flds[0]} =~ s/^\s*(.*?)\s*$/$1/g;
}

sub catflds_replace_space {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : @{ $self->{_head} };
	$self->{CURRENT}{ROW}->{$flds[0]} = join " " => map { $self->{CURRENT}{ROW}->{$_} } @flds[1..$#flds];
	$self->{CURRENT}{ROW}->{$flds[0]} =~ s/ +/ /g;
	$self->{CURRENT}{ROW}->{$flds[0]} =~ s/^\s*(.*?)\s*$/$1/g;
}

sub progress {
	my $self		= $_[0];
	my $incr		= $_[1] || ( $_[0]->{LIMIT}->[0]/1000 > 10 ? $_[0]->{LIMIT}->[0]/1000 : 100 );
	my $width		= $_[2] || 100;
	print STDOUT '.'		if ($_[0]->{selector}->{count} % $incr == 0);
	print STDOUT "\n"		if ($_[0]->{selector}->{count} % ($width * $incr) == 0);
}

sub clean_binaries {
    my $self    = $_[0];
    my @flds    = @_ > 1 ? @_[1..$#_] : grep { $self->{_types}{$_} eq 'b' } @{ $self->{_head} };
    for my $fld (@flds) {
       if ($_[0]->{CURRENT}{ROW}{$fld} =~ /^\s*(1|Y|Yes|True)\s*$/i) {
			$_[0]->{CURRENT}{ROW}{$fld} = 1;
       } elsif ($_[0]->{CURRENT}{ROW}{$fld} =~ /^\s*(0|N|No|False)\s*$/i) {
			$_[0]->{CURRENT}{ROW}{$fld} = 0;
       }
    }
}

sub force_binaries {
    my $self    = $_[0];
    my @flds    = @_ > 1 ? @_[1..$#_] : grep { $self->{_types}{$_} eq 'b' } @{ $self->{_head} };
    for my $fld (@flds) {
       if ($_[0]->{CURRENT}{ROW}{$fld} =~ /^\s*(1|Y|Yes|True)\s*$/i) {
			$_[0]->{CURRENT}{ROW}{$fld} = 1;
       } elsif ($_[0]->{CURRENT}{ROW}{$fld} =~ /^\s*(0|N|No|False)\s*$/i) {
			$_[0]->{CURRENT}{ROW}{$fld} = 0;
       } elsif ( ! $_[0]->{CURRENT}{ROW}{$fld} ) {
			$_[0]->{CURRENT}{ROW}{$fld} = 0;
       } else {
			$_[0]->{CURRENT}{ROW}{$fld} = 1;
       }
    }
}

sub fix_dates {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : grep { $self->{_types}{$_} eq 'd' } @{ $self->{_head} };
	for my $fld (@flds) {
		$_[0]->{CURRENT}{ROW}{$fld} =~ s{^(\d\d?)\/(\d\d?)\/(\d\d\d\d)}
										{sprintf qq{%04d-%02d-%02d}, $3,$1,$2}e;
	}
}

sub fix_us_short_dates {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : grep { $self->{_types}{$_} eq 'd' } @{ $self->{_head} };
	for my $fld (@flds) {
		$_[0]->{CURRENT}{ROW}{$fld} =~ s{^01\/01\/1900}{1900-01-01};  # mont_co no date
		$_[0]->{CURRENT}{ROW}{$fld} =~ s{^(\d\d?)\/(\d\d?)\/(18\d\d)(.*)$}
										{sprintf qq{%04d-%02d-%02d}, $3,$1,$2}e;
		$_[0]->{CURRENT}{ROW}{$fld} =~ s{^(\d\d?)\/(\d\d?)\/(19\d\d)(.*)$}
										{sprintf qq{%04d-%02d-%02d}, $3,$1,$2}e;
		$_[0]->{CURRENT}{ROW}{$fld} =~ s{^(\d\d?)\/(\d\d?)\/(20\d\d)(.*)$}
										{sprintf qq{%04d-%02d-%02d}, $3,$1,$2}e;

		$_[0]->{CURRENT}{ROW}{$fld} =~ s{^(\d\d?)\/(\d\d?)\/([1-9]\d)(.*)$}
										{sprintf qq{19%02d-%02d-%02d}, $3,$1,$2}e;
		$_[0]->{CURRENT}{ROW}{$fld} =~ s{^(\d\d?)\/(\d\d?)\/(0\d|10)(.*)$}
										{sprintf qq{20%02d-%02d-%02d}, $3,$1,$2}e;
		$_[0]->{CURRENT}{ROW}{$fld} =~ s{^(\d\d?)-(\d\d?)-([1-9]\d)(.*)$}
										{sprintf qq{19%02d-%02d-%02d}, $3,$1,$2}e;
		$_[0]->{CURRENT}{ROW}{$fld} =~ s{^(\d\d?)-(\d\d?)-(0\d|10)(.*)$}
										{sprintf qq{20%02d-%02d-%02d}, $3,$1,$2}e;
	}
}

sub get_excel_month_nums {
	my $self	= $_[0];
	return { qw/Jan 01 Feb 02 Mar 03 Apr 04 May 05 Jun 06 Jul 07 Aug 08 Sep 09 Oct 10 Nov 11 Dec 12/ };
}

sub fix_excel_dates {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : grep { $self->{_types}{$_} eq 'd' } @{ $self->{_head} };
	my %month_nums = %{ $self->{COUNTS}->{'_month_nums'} ||= $self->get_excel_month_nums() };
	for my $fld (@flds) {
		$_[0]->{CURRENT}{ROW}{$fld} =~ s{^(\d\d?)-(\w\w\w)-(\d\d\d\d)}
										{sprintf qq{%04d-%02d-%02d}, $3,$month_nums{$2},$1}e;
	}
}

sub fix_excel_short_dates {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : grep { $self->{_types}{$_} eq 'd' } @{ $self->{_head} };
	my %month_nums = %{ $self->{COUNTS}->{'_month_nums'} ||= $self->get_excel_month_nums() };
	for my $fld (@flds) {
		$_[0]->{CURRENT}{ROW}{$fld} =~ s{^(\d\d?)-(\w\w\w)-(\d\d)}
										{sprintf qq{20%02d-%02d-%02d}, $3,$month_nums{$2},$1}e;
	}
}

sub fix_date_times {
	my $self	= $_[0];
	my @flds	= @_ > 1 ? @_[1..$#_] : grep { $self->{_types}{$_} eq 'd' } @{ $self->{_head} };
	for my $fld (@flds) {
		$_[0]->{CURRENT}{ROW}{$fld} =~ s{^(\d\d?)\/(\d\d?)\/(\d\d\d\d)([ T](\d{1,2}):(\d{2})(:(\d{2}))?)?}
										{sprintf qq{%04d-%02d-%02d}, $3,$1,$2}e;
	}
}

sub set_date {
	my $self	= $_[0];

	my @flds	= @_ > 1 ? @_[1..$#_] : grep { $self->{_types}{$_} eq 'd' } @{ $self->{_head} };

	# Derive standard local date values/indices
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;

	$year			+= 1900;
	my $mil_hour	= $hour;
	my $AP			= $hour > 11 ? 'PM' : 'AM' ;
	$hour			= $hour % 12 || 12;
	my $season		= $isdst ? 'DST' : 'STD' ; # local savings/standard time

	for my $fld (@flds) {
		$_[0]->{CURRENT}{ROW}{$fld} = sprintf "%4.4d-%2.2d-%2.2d",
			$year, $mon + 1, $mday;
	}
}




1;

