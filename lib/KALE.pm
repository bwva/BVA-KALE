package BVA::KALE;

$BVA::KALE::VERSION      = "3.08.01";
$BVA::KALE::VERSION_DATE = '2019-12-02';

use strict;
use warnings;

use Carp;
use Data::Dumper;
use IO::Handle;
use Cpanel::JSON::XS;

use vars qw/ *KEY *KALE *OUTPUT *INPUT /;

use parent
  qw{ BVA::KALE::IN BVA::KALE::DB BVA::KALE::DATA BVA::KALE::OUT BVA::KALE::UTILS BVA::KALE::DATETIME };

=head1 NAME

BVA::KALE - Extensible User Interface!

=head1 VERSION

Version 3.08.01

=cut

=head1 SYNOPSIS

KALE provides methods and structures for creating dynamic user interfaces.

    use BVA::KALE;

    my $ui			= BVA::KALE->init();
    my $students	= $ui->new( _mark => 'ST', _start => '{*', _end => '*}");
    my $tmpl		= "{*ST:DATA=number*}\t{*ST:DATA=firstname*}\t{*ST:DATA=lastname*}\t{*ST:DATA=birthdate*}\t\n}";
    $students->form($tmpl);
    my $counter		= 0;
    while (my $st = $sth->fetchrow_hashref()) {	# data from somewhere
    											# including fields firstname,lastname,birthdate
    	$students->charge($st);
    	$students->charge(number => $counter++);
    	$students->buffer;
    }
    my $list	= join '' $students->flush();

=head1 EXPORT

No functions exported.

=head1 SUBROUTINES/METHODS

=head2 init

=cut

## Initialization #################
## Creates and returns the master UI object generator
sub initialize_ui {
	goto &init;
}

sub init {
	my ( $class, @args ) = @_;
	{
		local $_ = ref( $args[0] );
		/HASH/i and %KEY = %{ $args[0] }
		  or /ARRAY/ and @KEY{qw/_env _start _end/} = @{ $args[0] }
		  or @KEY{qw/_env _start _end/} = @args;
	}

	$KEY{_init_time} = BVA::KALE::DATETIME::tell_time( 'iso_store', time );

	$KEY{_env} ||=
		$KEY{env} ? delete $KEY{env}
	  : exists $ENV{SERVER_PROTOCOL} ? 'htm'
	  : exists $ENV{TERM_PROGRAM}    ? 'term'
	  :                                'edit';

	$KEY{_start} ||=
		$KEY{start} ? delete $KEY{start}
	  : $KEY{_env} =~ /^(htm|psgi)/i ? '<!--'
	  : '#';

	$KEY{_end} ||=
		$KEY{end} ? delete $KEY{end}
	  : $KEY{_env} =~ /^(htm|psgi)/i ? '-->'
	  : '#';

	$KEY{_mark} ||=
		$KEY{mark} ? delete $KEY{mark}
	  : 'KEY';
	$KEY{_ui_mark} = $KEY{_mark};

	$KEY{_sub} ||= \&OUTPUT;
	$KEY{_match_str} =
	  qr{(?s:((\Q$KEY{_start}$KEY{_mark}\E)[: -]((.(?!\2))*?)\Q$KEY{_end}\E))};
	$KEY{_default_tmpl} = qq{$KEY{_start}$KEY{_mark} DATA=_mark$KEY{_end}};
	$KEY{_hdr_prntd}    = 0;

	$KEY{_in_lib} ||= '';
	$KEY{_in_max} ||= 1000;

	$KEY{_home_dir}     ||= '.';
	$KEY{_display_dir}  ||= "$KEY{_home_dir}/displays";
	$KEY{_list_dir}     ||= "$KEY{_home_dir}/lists";
	$KEY{_message_dir}  ||= "$KEY{_home_dir}/messages";
	$KEY{_image_dir}    ||= "$KEY{_home_dir}/images";
	$KEY{_message_file} ||= '';
	$KEY{_list_file}    ||= '';
	$KEY{_dbi}          ||= undef;
	$KEY{_dbh}          ||= undef;

	## Start with the typeglob based on the %KEY hash
	*KEY = \%KEY;

	## If a master output sub was specified, assign it to the typeglob
	unless ( defined &KEY ) {
		*KEY = $KEY{_sub} || \&{"KEY{_mark}"};
	}

	## _objects: Store a reference to the generator's buffer
	$KEY{_objects_in_use}->{ $KEY{_mark} }++;
	$KEY{_objects} = \@KEY;

	## generator: Create the ui object generator
	## Access it with class or instance method ->generator()
	$KEY{_generator} = bless \*KEY, $class;

	## Store the generator in @KEY; its ui objects will each be stored there, too.
	## Access them with class or instance method ->objects().
	push @{*KEY} => $KEY{_generator};

	$KEY{_generator}->INPUT;

	$KEY{_generator}->get_marked_input;

	return $KEY{_generator};
}

# Instantiate a UI object around a filehandle or a typeglob
sub new {
	my $gen_obj = shift;
	unless ( ref($gen_obj) eq __PACKAGE__ ) {
		$gen_obj = __PACKAGE__->init();
	}
	my %properties = %{*$gen_obj};

	my @args = @_;

	# Store the generator's mark before getting the new object's mark from args
	$properties{_ui_mark} = $properties{_mark};

	my $argref = ref( $args[0] );
	my %new_props;
	if ( $argref =~ /HASH/i ) {
		%new_props = %{ $args[0] };
	}
	elsif ( $argref =~ /ARRAY/i ) {
		@new_props{qw/_mark _file _start _end _sub/} = @{ $args[0] };
	}
	else {
		@new_props{qw/_mark _file _start _end _sub/} = @args;
	}
	%new_props =
	  map { $new_props{$_} ? ( $_ => $new_props{$_} ) : () } keys %new_props;
	%properties = ( %properties, %new_props );

	%new_props	= ();

	$properties{_env} =
		$properties{env} ? delete $properties{env}
	  : $properties{_env} ? $properties{_env}
	  : exists $ENV{SERVER_PROTOCOL} ? 'htm'
	  : exists $ENV{TERM_PROGRAM}    ? 'term'
	  :                                'edit';

	$properties{_mark}  =
		$properties{mark} ? delete $properties{mark}
	  : $properties{_mark} ? $properties{_mark}
	  : '';

	$properties{_start} =
		$properties{_start} ne '#' ? $properties{_start}
	  : $properties{start} ? delete $properties{start}
	  : $properties{_env} =~ /^(htm|psgi)/i ? '<!--'
	  : '#';

	$properties{_end} =
		$properties{_end} ne '#' ? $properties{_end}
	  : $properties{end} ? delete $properties{end}
	  : $properties{_env} =~ /^(htm|psgi)/i ? '-->'
	  : '#';

	$properties{_file}  =
		$properties{file} ? delete $properties{file}
	  : $properties{_file} ? $properties{_file}
	  : '';
	$properties{_file} &&=
	  $properties{_file} =~ m{\A\s*([^`<>,]+)\s*\z} ? $1 : '-';
	$properties{_file} ||= '-';

	$properties{_owner} ||= $properties{_mark};

	$properties{_obj_init_time} =
	  BVA::KALE::DATETIME::tell_time( 'secs', time );

	$properties{_sub} ||= \&OUTPUT;

	## Match Pattern and Default Template
	if ( $properties{'_is_direct'} ) {
		$properties{_default_tmpl} =
		  qq{$properties{_start}:_mark$properties{_end}};
	}
	else {
		$properties{_match_str} =
qr{(?s:((\Q$properties{_start}$properties{_mark}\E)[: -]((.(?!\2))*?)\Q$properties{_end}\E))};
# 		$properties{_default_tmpl} =
		$properties{_default_tmpl} ||=   # 2019-12-21
		  qq{$properties{_start}$properties{_mark}:DATA=_mark$properties{_end}};
	}

	$properties{_in_lib} ||= '';
	$properties{_in_max} ||= 1000;

	$properties{_display_dir} ||= "$properties{_home_dir}/displays";
	$properties{_list_dir}    ||= "$properties{_home_dir}/lists";
	$properties{_message_dir} ||= "$properties{_home_dir}/messages";
	$properties{_image_dir}   ||= "$properties{_home_dir}/images";

	$properties{_message_file} ||= '';
	$properties{_list_file}    ||= '';
	$properties{_dbi}          ||= undef;
	$properties{_dbh}          ||= undef;

	$properties{_req_prefix} ||= '*';

	## Object instantiation
	my $new_obj		= do {
		no strict 'refs';
		if ( $properties{_mark} ) {
			if ( $properties{_file} !~ /[\^-]/ ) {
				open( \*{ "main::" . $properties{_mark} },
					"+>>:encoding(UTF8)", $properties{_file} )
				  or carp "Can't open file $properties{_file}: $!";
				*{"main::$properties{_mark}"}{IO}->autoflush();
				$properties{_file_as_opened} = [
					'File',
					*{"main::$properties{_mark}"}{IO}->fileno(),
					*{"main::$properties{_mark}"}{IO}->stat()
				];
				$properties{_file_keep_open} = 1;
			}
			*{"main::$properties{_mark}"} = \%properties;
			unless ( defined &{"main::$properties{_mark}"} ) {
				*{"main::$properties{_mark}"} =
				  $properties{_sub} || \&{"main::$properties{_mark}"};
			}
			bless \*{"main::$properties{_mark}"}, ref($gen_obj) || $gen_obj;
		} else {
			*{"main::OUTPUT"} = \%properties;
			bless \*{"main::OUTPUT"}, ref($gen_obj) || $gen_obj;
		}
	};

	# Don't store, or collect input for, direct() objects
	return $new_obj if $new_obj->data('_is_direct');

	## Store the instance ref for use by render() and objects()
	unless ( $properties{_objects_in_use}->{ $new_obj->data('_mark') }++ ) {
		push @{*$gen_obj} => $new_obj;
	}

	## Collect any input marked for this object
	$new_obj->get_marked_input;

	return $new_obj;
}

## INPUT
# Capture, clean, and untaint any input
# Filter Input by field and source type
sub INPUT {
	goto &BVA::KALE::IN::IN;
}

## OUTPUT
## Main Display Dispatcher
sub OUTPUT {
	goto &BVA::KALE::OUT::OUT;
}

############################################

## Invert: Turns the UI object into its internal typeglob (*KEY)
sub invert {
	my ($self) = @_;
	return ( ref($self) eq __PACKAGE__ ? $self : \*{$self} );
}

sub generator ($) {
	my ($self) = @_;
	local *KEY = $self->invert();
	return $KEY{_generator};
}

## Objects: returns a list of all current UI objects, or
## a list of the objects specified in the args with
## valid KEY marks ($KEY{_mark} -- 'KEY').
sub objects ($;@) {
	my ( $self, @object_names ) = @_;
	local *KEY = invert($self);

	my @objs = grep { ref($_) eq __PACKAGE__ } @{ $KEY{_objects} };

	#return @objs unless @object_names;

	my %objs = map { ${*$_}{_mark} => $_ } @objs;

	my @these =
	  @object_names > 0 ? @object_names : keys %{ $KEY{_objects_in_use} };

	return map { $objs{$_} ? $objs{$_} : () } @these;
}

sub object_marks_in_use {
	my $self = shift;
	local *KEY = $self->invert;
	my @objs = sort keys %{ $KEY{_objects_in_use} };
	return @objs;    # 2018-11-10
}

## Object: returns a UI object specified by a single arg
## with a valid KEY marks ($KEY{_mark} -- 'KEY').
sub object ($;$) {
	my ( $self, $object_name ) = @_;
	local *KEY = invert($self);

	return $KEY{_generator} unless $object_name;

	my @objs = grep { ref($_) eq __PACKAGE__ } @{ $KEY{_objects} };

	my ($obj) = grep { ${*$_}{_mark} eq $object_name } @objs;

	return $obj;
}

## direct: instantiate a ui object with an atomic output sub.
## Accessible as class or instance method ->direct()
## Use in place of ->new(), with no args.
## Inherits meta_data from the object or generator that creates it.
## Memoizes the ui object (for its parent);
## NOTE: direct()'s _match_str allows \b to separate mark from EXPR, while
## the standard _match_str REQUIRES a colon ':' or space ' ' following the mark;
## this allows direct()'s templates to use a colon AS the mark:
## E.g, with _start => '[', _end => ']', _mark => ':',
## can now use  [:fieldname] instead of [::fieldname] or [: fieldname].
## 2013-02-13 This match_str also allows expressions of the type MARK[:.]fieldname, with
## the parent ui object's mark, a colon or period (: .), and then the fieldname,
## no brackets needed. E.g., if _mark is 'SUP', SUP:address or SUP.address
## 2015-02-03 use of underscore '_' removed
## 2015-02-24 added caching of $KEY{_direct}
sub direct ($;@) {
	my ( $self, $sub ) = @_;
	local *KEY = invert($self);
	$sub ||= sub {
		my ( $innerself, $field ) = @_;
		return '' unless defined $field;
		local *KEY = invert($innerself);
		$field =~ s/^\s*(.*?)\s*$/$1/s;
		my $out = defined $KEY{$field} ? $KEY{$field} : "";
		$KEY{__DONE__}++ unless $out;
		return $out;
	};

	unless ( exists $KEY{_direct} ) {
		my $owner = $KEY{_mark};
		my $mark  = $KEY{_direct_mark} || ':';
		my $start = $KEY{_direct_start} || '[';
		my $end   = $KEY{_direct_end} || ']';
		my $match_str1 =
			qr{(?sx: ((\Q${start}${mark}\E)	(?:\:|\s|\b)	((.(?!\2))+?)	\Q${end}\E) )};
		my $match_str2 =
			qr{(?sx: ((\Q${owner}\E[:.])					((\S(?!\2))+?)	(?:\b))   	)};
		$KEY{_direct} = $KEY{_generator}->new(
			{
				_is_direct => 1,
				_mark      => $mark,
				_start     => $start,
				_end       => $end,
				_owner     => $owner,
				_match_str => qr{(?sx: $match_str1 | $match_str2 )},
				_sub       => $sub,
			}
		);
	}

	$KEY{_direct}->clear();
	return $KEY{_direct};
}

## Resolve: returns a string with the UI object's data values in %KEY, including meta-data,
## atomically substituted for any template tokens in the string.
## The default token pattern uses _start => '[', _end => ']', and _mark => ':';
## the pattern uses the UI object's _direct_mark, _direct_start, and _direct_end if the UI object has them.
## $obj->resolve('[:system_dir]/settings.config'); # '/Volumes/Dev/MyProject/System/settings.config'
## Multiple args are joined with '' because _process_tmpl takes only one template arg.
## NOTE: Unlike render(), resolve does NOT auto-charge or calculate,
## to avoid traps in deep recursion.
sub resolve ($@) {
	my $self = shift;
	local *KEY = invert($self);

	if ( $KEY{_is_direct} ) {
		return $self->replace(@_);
	}

	local *KALE = sub {
		my ( $obj, $field ) = @_;
		return '' unless defined $field;
		local *KALE = invert($obj);
		$field =~ s/^\s*(.*?)\s*$/$1/s;
		my $out =
		  defined $KALE{$field}
		  ? $KALE{$field}
		  : "$KALE{_direct_start}$KALE{_direct_mark}$field$KALE{_direct_end}";
		$KALE{__DONE__}++ if length($out);
		return $out;
	};

	%KALE = %KEY;

	@KALE = @KEY;

# 	$KALE = @_ ? join( '' => @_ ) : '';
	$KALE = @_ ? join( '' => @_ ) : $KEY;

	my $owner = $KALE{_mark};
	my $mark  = $KALE{_direct_mark} ||= ':';
	my $start = $KALE{_direct_start} ||= '[';
	my $end   = $KALE{_direct_end} ||= ']';
	my $match_str1 =
	  qr{(?sx: ((\Q${start}${mark}\E)	(?:\:|\s|\b)	((.(?!\2))+?)	\Q${end}\E) )};
	my $match_str2 =
	  qr{(?sx: ((\Q${owner}\E[.:])						((\S(?!\2))+?)	(?:\b))   	)};
	$KALE{_owner} = $owner;

  GO: {
		my $str = $KALE;
		my $result;
		$str =~ s{ $match_str1 | $match_str2 }
					{ $result = KALE(\*KALE, $3||$7)
						or !$KALE{__DONE__} and $result = OUTPUT(\*KALE, $3||$7)
							or (delete $KALE{__DONE__} ? $result : $1) }gsex;
		last GO if $str eq $KALE;
		$KALE = $str and redo GO;
	}

	return $KALE;
}
#
sub index_resolve ($@) {
	my ($self, @strings)	= (@_);
   	local *KEY	= invert($self);

 	$KEY		= @strings ? join( '' => @strings) : '';

 	my $owner	= $KEY{_mark};
 	my $mark	= $KEY{_direct_mark}	|| ':';
 	my $start	= $KEY{_direct_start}	|| '[';
 	my $end		= $KEY{_direct_end}		|| ']';
 	my $index_str			= $start . $mark;
 	my $index_str_len		= length $index_str;
 	my $index_str_end		= $end;
 	my $index_str_end_len	= length $index_str_end;
 	my $startPos			= 0;

	GO: {
		my $str 	= $KEY;
		my $pos1	= index $str, $index_str, $startPos;
		last GO if $pos1 < 0;

		my $pos2	= index $str, $index_str_end, $pos1;
		last GO if $pos2 < 0;

		my $extract_pos	= $pos1 + $index_str_len;
		my $extract_len	= $pos2 - $extract_pos;
		my $extract		= substr $str, $extract_pos, $extract_len;

		substr $str, $pos1, $pos2 + $index_str_end_len - $pos1, (length $KEY{$extract} ? $KEY{$extract} : "");
		last GO if $str eq $KEY;
		$startPos		= $pos1;
		$KEY 			= $str;
		redo GO;
	}

 	return $KEY;
}

## Render: Class method that recursively processes
## all instantiated ui objects against template
## composed of any optional args, or $KEY,
## or the default template.
## Use with the object generator, which stores each
## ui object in @KEY.
## Performs any auto-charges and calculations set for each ui object.
## Processing cycles through all ui objects until a full cycle yields
## no further change to the output.
## Returns processed output.
sub render ($;@) {
	my ( $self, @strings ) = (@_);
	local *KEY = $self->invert();

	my $tmpl =
	     join( '' => @strings )
	  || $KEY
	  || $KEY{_default_tmpl};

	my $output = ' ';

	my @objects = objects(*KEY);
  LOAD: {
		foreach my $obj (@objects) {
			$obj->charge_auto();
			$obj->calculate();
		}
	}

	# Make sure nesting works across UI objects
	my $start_pat =
	  '(' . join( '|' => map { "\Q${ *{ $_ } }{_start}\E" } @objects ) . ')';
	my $mark_pat =
	  '(' . join( '|' => map { ${ *{$_} }{_mark} } @objects ) . ')';

  RENDER: {
		foreach my $obj (@objects) {
			my ( $start, $end, $mark, $own_match_str ) =
			  $obj->data( '_start', '_end', '_mark', '_match_str' );
			$obj->charge_meta( _match_str =>
qr{(?s:((\Q${start}${mark}\E)[: ]((.(?!${start_pat}${mark_pat}))*?)\Q$end\E))}
			);
			$tmpl = $obj->_process_tmpl($tmpl);
			$obj->charge_meta( _match_str => $own_match_str );
		}
		last RENDER if $output eq $tmpl;
		$output = $tmpl and redo RENDER;
	}

	return $output;
}

sub inventory_tmpl {
	my $obj = shift;
	local *KEY = $obj->invert();

	my @tokens;

	local *KALE = sub {
		my ( $innerobj, $field ) = @_;
		return '' unless defined $field;
		$field =~ s/^\s*(.*?)\s*$/$1/s;
		my $out = $field || "";
		push @tokens => $KEY{_mark} . ':' . $out;
		$KALE{__DONE__}++ unless $out;
		return $out;
	};

	%KALE = %KEY;

	@KALE = @KEY;

	$KALE = @_ ? join( '' => @_ ) : $KEY || '';

	my $tmpl = $KALE;

  GO: {
		my $str = $tmpl;
		study $str;
		my $result;
		$str =~ s{$KALE{_match_str}}
					{ $result = KALE(\*KALE, $3||$7)
						or !$KALE{__DONE__} and $result = OUTPUT(\*KALE, $3||$7)
							or (delete $KALE{__DONE__} ? $result : $1) }gsex;
		last GO if $str eq $tmpl;
		$tmpl = $str and redo GO;
	}

	return @tokens;
}

sub render_qp ($;@) {
	my ( $self, @strings ) = (@_);
	local *KEY = $self->invert();    # invert($self);

	@BVA::KALE::OUT::OUT = ();

	my $tmpl = @strings ? join( '' => @strings ) : $KEY;
	$tmpl ||= $KEY{_default_tmpl};

	my $output = ' ';

	my @objects = objects(*KEY);

  LOAD: {
		foreach my $obj (@objects) {
			$obj->charge_auto();
			$obj->calculate();
		}
	}

	# Make sure nesting works across UI objects
	my $start_pat =
	  '(' . join( '|' => map { "\Q${ *{ $_ } }{_start}\E" } @objects ) . ')';
	my $mark_pat =
	  '(' . join( '|' => map { ${ *{$_} }{_mark} } @objects ) . ')';

  RENDER: {
		foreach my $obj (@objects) {
			my ( $start, $end, $mark, $own_match_str ) =
			  $obj->data( '_start', '_end', '_mark', '_match_str' );
			$obj->charge_meta( _match_str =>
qr{(?s:((\Q${start}${mark}\E)[: ]((.(?!${start_pat}${mark_pat}))*?)\Q$end\E))}
			);
			$tmpl = $obj->_process_tmpl($tmpl);
			$obj->charge_meta( _match_str => $own_match_str );
		}
		last RENDER if $output eq $tmpl;
		$output = $tmpl and redo RENDER;
	}

	require MIME::QuotedPrint;
	return MIME::QuotedPrint::encode_qp( $output || $KEY );
}

## Replace: Processes the current template with available data;
##			Returns processed output.
sub replace ($;@) {
	my ( $self, @strings ) = (@_);
	local *KEY = $self->invert();    # invert($self);

	my $tmpl =
	     join( '' => @strings )
	  || $KEY
	  || $KEY{_default_tmpl};

	$tmpl = _process_tmpl( \*KEY, $tmpl );

	return $tmpl;
}

## Process: Provides OO access to dispatch sub $KEY{_sub}.
## The arg is the same as what replace() would pass to the dispatcher
## after stripping off the _start, _mark, and _end tokens.
## In list context, returns an array whose elements
## are the processed values of the arguments in order.
## The same array is returned concatenated as a string in scalar context.
## Output may be () or ''.
## Usage: $obj->process(qq{INPUT=$fld,$value,r,,,-1})
## Compare to $obj->replace(qq{<!--KEY:INPUT=$fld,$value,r,,,-1-->})
## where _start is '<!--', _mark is 'KEY', _end is '-->.
sub process {
	my ( $self, @strings ) = (@_);
	local *KEY = $self->invert();    # invert($self);

	return '' unless @strings;

	defined &KEY
	  or *KEY = \&OUTPUT;

	my @products =
	  map { KEY( \*KEY, $_ ) || OUTPUT( \*KEY, $_ ) || $_ } @strings;

	return wantarray ? @products : join ' ' => @products;
}

## _process_tmpl: the "private" internal sub for processing templates.
## MUST be curried to receive valid \*KEY and a single defined $tmpl string;
## Recursively replaces template markers,
## by using pattern matching [_start][_mark](...)[_end]
## and handing each (...) to the UI object's designated OUTPUT dispatcher.
## The OUTPUT() dispatcher uses available data and subroutines or defaults to
## substitute for (...), and returns the result for another iteration.
## Returns $tmpl after substitutions are exhausted.
sub _process_tmpl ($$) {
	my ( $self, $tmpl ) = @_;
	local *KEY = $self->invert();    # invert($self);

	defined &KEY
	  or *KEY = \&OUTPUT;

  GO: {
		my $str = $tmpl;
		study $str;
		my $result;
		$str =~ s{$KEY{_match_str}}
					{ $result = KEY(\*KEY, $3||$7)
						or !$KEY{__DONE__} and $result = OUTPUT(\*KEY, $3||$7)
							or (delete $KEY{__DONE__} ? $result : $1) }gsex;
		last GO if $str eq $tmpl;
		$tmpl = $str and redo GO;
	}

	return $tmpl;
}

sub _index_process_tmpl ($$) {
	my ( $self, $tmpl ) = @_;
	local *KEY = $self->invert();    # invert($self);

	defined &KEY
	  or *KEY = \&OUTPUT;

	$KEY{_index_str} ||= qq{$KEY{_direct_start}$KEY{_direct_mark}};
	$KEY{_index_str_len} = length $KEY{_index_str};
	$KEY{_index_str_end} ||= qq{$KEY{_direct_end}};
	$KEY{_index_str_end_len} = length $KEY{_index_str_end};

  GO: {
		my $str = $tmpl;
		my $result;
		my $pos1 = index $str, $KEY{_index_str};
		last GO if $pos1 < 0;
		my $pos2 = index $str, $KEY{_index_str_end}, $pos1;
		last GO if $pos2 < 0;
		my $start_pos   = $pos1 + $KEY{_index_str_len};
		my $extract_len = $pos2 - $start_pos;
		my $extract     = substr $str, $start_pos, $extract_len;
		substr $str, $pos1, $pos2 + $KEY{_index_str_end_len} - $pos1, do {
			my $field = $extract;
			$field =~ s/^\s*(.*?)\s*$/$1/s;
			$result = defined $KALE{$field} ? $KALE{$field} : "";
			$KALE{__DONE__}++ unless $result;
			$result;
		};

		last GO if $str eq $tmpl;
		$tmpl = $str and redo GO;
	}

	return $tmpl;
}

## Attach file: allows a file to be specified after instantiation of the object
sub attach_file {
	my ( $self, $file, $keep_open ) = @_;
	local *KEY = $self->invert();    # invert($self);
	$file ||= undef;
	$keep_open ||=
	  0;    # only affects named files, not tmp files or scalar variable

	if ( !$file ) {
		if ( open KEY, "+>>:encoding(UTF8)", undef ) {
			*KEY{IO}->autoflush();
			$KEY{_file_as_opened} =
			  [ 'Tmp', *KEY{IO}->fileno(), *KEY{IO}->stat() ];
			$KEY{_file_keep_open} = 1;
		}
		else {
			warnings::warnif( 'io', "Problem with attaching temp file:\n$!" );
			charge_err( \*KEY, "Problem with attaching temp file:\n$!" )
			  and return;
		}
	}
	elsif ( $file eq '^' ) {
		$KEY{_vfile} = '';
		if ( open KEY, "+>>:encoding(UTF8)", \$KEY{_vfile} ) {
			*KEY{IO}->autoflush();
			$KEY{_file} = $file;
			$KEY{_file_as_opened} =
			  [ 'Virtual', *KEY{IO}->fileno(), *KEY{IO}->stat() ];
			$KEY{_file_keep_open} = 1;
		}
		else {
			warnings::warnif( 'io', "Problem with attaching temp file:\n$!" );
			charge_err( \*KEY, "Problem with attaching temp file:\n$!" )
			  and return;
		}
	}
	elsif ( ref($file) eq __PACKAGE__ ) {
		*KEY = $file;
	}
	elsif ( $file =~ m{^([^`]+)$} ) {
		$file = $1;
		if ( open KEY, "+>>:encoding(UTF8)", $file ) {
			*KEY{IO}->autoflush();
			$KEY{_file} = $file;
			$KEY{_file_as_opened} =
			  [ 'File', *KEY{IO}->fileno(), *KEY{IO}->stat() ];
			$KEY{_file_keep_open} = $keep_open;

			#chmod oct(777), $file;
		}
		else {
			warnings::warnif( 'io', "Problem with attaching file $file:\n$!" );
			charge_err( \*KEY, "Problem with attaching file $file:\n$!" )
			  and return;
		}
	}
	else {
		warnings::warnif( 'io',
"Proposed attached file is neither a filehandle nor a valid filename."
		);
		carp
"Proposed attached file is neither a filehandle nor a valid filename.";
	}
	\*KEY;
}

##################

## Buffer: Same as replace, plus all output is accumulated in the array
## @KEY, which may be accessed as @{$mark} in the calling program
## or by using any of the flush or read variants:
## flush(), flush_lifo(), flush_next(), flush_last(), flush_trained, flush_random,
## read_fifo(), read_lifo(), read_unique(), read_except()
sub buffer ($;@) {
	my $arg1 = shift;
	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};

	if ( ref( $_[0] ) ) {
		push @KEY => $_[0];
		return $_[0];
	}
	my $tmpl =
	     join( '' => @_ )
	  || $KEY
	  || $KEY{_default_tmpl};

	$tmpl = _process_tmpl( \*KEY, $tmpl );
	push @KEY => $tmpl;
	return $tmpl;
}

sub buffer_resolved ($;@) {
	my $arg1 = shift;
	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};

	if ( ref( $_[0] ) ) {
		push @KEY => $_[0];
		return $_[0];
	}
	my $tmpl =
	     join( '' => @_ )
	  || $KEY
	  || $KEY{_default_tmpl};

	$tmpl = resolve( \*KEY, $tmpl );
	push @KEY => $tmpl;
	return $tmpl;
}

## Buffer Trained !!!!
sub buffer_trained {

}

## Flush: returns and clears the @KEY buffer
sub flush ($) {
	goto &flush_refsOK;
}

## Flush: returns and clears the @KEY buffer
sub flush_refsOK ($) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my @buf;
	my @strs;
	my @refs;
	my @globs;
	foreach my $elem (@KEY) {
		my $elemRef = '';
		if ( $elemRef = ref($elem) ) {
			if ( $elemRef eq __PACKAGE__ ) {
				push @globs => $elem;
			}
			else {
				push @refs => $elem;
				push @buf  => $elem;
			}
		}
		else {
			push @strs => $elem;
			push @buf  => $elem;
		}
	}
	@KEY = @globs;
	return
	  wantarray ? @buf : @refs ? [ @refs, join '' => @buf ] : join '' => @buf;
}

## Flush Num: Iterates through @KEY for the number of times specified in the second arg,
## returning the first valid value, which is deleted from @KEY each iteration
sub flush_num ($$) {
	my $obj = shift;
	my $num = shift || 1;

	local *KEY = $obj->invert();

	my @keep;
	my @out;
	foreach my $elem (@KEY) {
		if ( ref($elem) eq __PACKAGE__ ) {
			push @keep => $elem;
		}
		elsif ($num) {
			push @out => $elem;
			$num--;
		}
		else {
			push @keep => $elem;
		}
	}
	@KEY = @keep;
	return wantarray ? @out : join '' => @out;
}

## Flush Next: Iterates through @KEY, returning the first valid value, which is deleted from @KEY
sub flush_next ($) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my @buf;
	my @keep;
	foreach my $elem (@KEY) {
		if ( ref($elem) eq __PACKAGE__ ) {
			push @keep => $elem;
			next;
		}
		if (@buf) {
			push @keep => $elem;
			next;
		}
		push @buf => $elem;
	}
	@KEY = @keep;
	return wantarray ? @buf : $buf[0];
}

## Flush Last: Iterates through @KEY, returning the last valid value, which is deleted from @KEY
sub flush_last ($) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my @buf;
	my @keep;
	foreach my $elem ( reverse @KEY ) {
		if ( ref($elem) eq __PACKAGE__ ) {
			push @keep => $elem;
			next;
		}
		if (@buf) {
			push @keep => $elem;
			next;
		}
		push @buf => $elem;
	}
	@KEY = reverse @keep;
	return wantarray ? @buf : $buf[0];
}

## Flush_lifo: returns and clears the @KEY buffer, last in first out
sub flush_lifo ($) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my @buf;
	my @globs;
	foreach my $elem (@KEY) {
		if ( ref($elem) eq __PACKAGE__ ) {
			push @globs => $elem;
		}
		else {
			push @buf => $elem;
		}
	}
	@KEY = @globs;
	return reverse @buf;
}

## Flush Trained: incrementally returns and clears the @KEY buffer, in chunks defined by first optional arg.
## If the arg is an arrayref, its elements are the defaults and the number of its elements
## sets the number of @KEY elements returned each time flush_trained is called.
## If the arg is a string matching the form [number] : [default],
## the defaults are [default], and the number sets the number of @KEY elements returned.
## Defaults are provided when elements fail a simple truth test [i.e., doesn't test for zero vs ''].
sub flush_trained ($;$) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my $pattern = shift();

	my $num_elems;
	my @defaults;
	if ( ref($pattern) =~ /array/i ) {
		@defaults  = @{$pattern};
		$num_elems = @defaults;
	}
	elsif ( $pattern =~ /^\s*(\d+)\s*(:(.*))?$/ ) {
		$num_elems = $1;
		my $def = defined $3 ? $3 : '';
		@defaults = ($def) x $num_elems;
	}

	my @buf;
	my @globs;
	foreach my $elem (@KEY) {
		if ( ref($elem) eq __PACKAGE__ ) {
			push @globs => $elem;
		}
		else {
			push @buf => $elem;
		}
	}
	@KEY = @globs;

	my @out;
	if ( @buf and @defaults ) {
		my @elems = splice @buf, 0, $num_elems;
		@out = map { $elems[$_] || $defaults[$_] } ( 0 .. $num_elems - 1 );
	}

	push @KEY => @buf;

	return wantarray ? @out : join '' => @out;
}

# flush_random - non-repeating
## Returns a number of randomly selected elements of the buffer (@KEY);
## The number returned is the first optional arg or
## the total number of elements in the buffer.
## Returned elements are picked without repeats and removed from the buffer.
## If the second optional arg is a boolean true, the returned elements are sorted
## to the order they were added to the buffer; otherwise, they are returned in the order
## by which they were (randomly) picked from the buffer.

sub flush_random ($;$) {
	goto &flush_random_pick;
}

# flush_random_pick - non-repeating
sub flush_random_pick ($;$$) {
	my $obj = shift;
	my $size		= shift() || 0;
	my $ordered		= shift() || 0;

	local *KEY = $obj->invert();

	my @buf;
	my @globs;
	foreach my $elem (@KEY) {
		if ( ref($elem) eq __PACKAGE__ ) {
			push @globs => $elem;
		}
		elsif ( $elem eq $KEY{_mark} ) {
			push @globs => $elem;
		}
		else {
			push @buf => $elem;
		}
	}
	my $num_elems	= scalar @buf;

	unless ($size and $size < $num_elems) {
		$size		= $num_elems;
	}

	my %random;
	my @random_series;
	my @picks;

	srand();
 	for ( 1 .. $size ) {
		my $rand_num = int( rand $num_elems + 0 ) + 0;
		redo if $random{$rand_num}->{seen}++;
		$random{$rand_num}->{ord}	= $_-1;
		push @random_series => $rand_num;
	}

	if ($ordered) {
		for ( reverse sort {$a <=> $b} @random_series ) {
			unshift @picks => splice @buf, $_, 1;
		}
	}  else  {
		for ( reverse sort {$a <=> $b} @random_series ) {
			$picks[$random{$_}->{ord}]	= splice @buf, $_, 1;
		}
	}
	@KEY	= (@globs, @buf);
	return @picks;
}

sub buffer_count ($;$) {
	my $obj = shift;
	local *KEY = $obj->invert();
	my $buf_count	= 0;
	foreach my $elem (@KEY) {
		next if ref($elem) eq __PACKAGE__;
		next if $elem eq $KEY{_mark};
		$buf_count++
	}
	$buf_count;
}

## read
sub read_buffer ($) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my @buf;
	my @globs;
	foreach my $elem (@KEY) {
		if ( ref($elem) eq __PACKAGE__ ) {
			push @globs => $elem;
		}
		else {
			push @buf => $elem;
		}
	}
	return wantarray ? @buf : join '' => @buf;
}

## Read_fifo: returns the @KEY buffer, first in first out
sub read_fifo ($) {
	my $obj = shift;

	local *KEY = $obj->invert();

	return grep { !ref($_) eq __PACKAGE__ } @KEY;
}

## Read_lifo: returns the @KEY buffer, last in first out
sub read_lifo ($) {
	my $obj = shift;

	local *KEY = $obj->invert();

	return reverse grep { !ref($_) eq __PACKAGE__ } @KEY;
}

## Read_unique: returns the @KEY buffer, unique values only.
## Optional args are added to @KEY, dereferencing any arg found to be an array ref
sub read_unique ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %found;
	return
	  map { $found{$_}++ ? () : $_ }
	  grep { !ref($_) eq __PACKAGE__ }
	  ( @KEY, map { ref($_) =~ /ARRAY/ ? @{$_} : $_ } @_ );
}

## Read_except: returns the @KEY buffer, excluding any values matching
## any optional args, dereferencing any arg found to be an array ref
sub read_except ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %exceptions =
	  map { ( $_ => 1 ) } map { ref($_) =~ /ARRAY/ ? @{$_} : $_ } @_;
	return grep { !( $exceptions{$_} || ref($_) eq __PACKAGE__ ) } @KEY;
}

## Template: Returns a template named by the first optional arg.
## The name is looked up, first in $KEY{_displays} and then
## in the display directory $KEY{_display_dir}.
##
## A name starting with '-' will only be looked up in the
## display directory (without the starting '-'). In this case,
## any additional args are concatenated and appended to the template.
##
## A name ending with '+' will concatenate any additional args
## and append them to the template of that name (without the '+').
##
## If the name has no starting '-' or ending '+' any additional args
## are concatenated as the template, and nothing is looked up.
##
## The resulting template might be an empty string ''.
## The resulting template is added UNPROCESSED to $KEY{_displays},
## replacing any template already there with that name.
##
##  The resulting template is then returned.
sub template ($;@) {
	my $obj = shift;

	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

# 	my $tmpl = '';
	my $tmpl = $KEY || $KEY{_default_tmpl}; # 2019-12-21
	my $tmpl_name = shift || '';
	my ( $get_tmpl_file, $template_name, $append ) =
	  $tmpl_name =~ /^(-)?([a-zA-Z_][\w -]*?)(\+)?\s*$/;

	return $tmpl unless $template_name;

	if ($get_tmpl_file) {
		$tmpl = $obj->_get_template_from_file($template_name);
		$tmpl .= join '' => @_;
	}
	elsif ( @_ and not $append ) {
		$tmpl = join '' => @_;
	}
	else {
		$tmpl = $KEY{_displays}->{$template_name}
		  || $obj->_get_template_from_file($template_name);
		$tmpl .= join '' => @_ if @_;
	}
	$KEY{_displays}->{$template_name} = $tmpl;

	return $tmpl;
}

## Save Template: Same as template(), except the resulting template
## is also saved as a file in the display directory $KEY{_display_dir},
## writing over any existing template of the same name.
##
## The resulting template might be ''.
## The resulting template is added UNPROCESSED to $KEY{_displays},
## replacing any template already there with that name.
##
##  The resulting template is then returned.

sub save_template ($;@) {
	my $obj = shift;

	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	my $tmpl = '';
	my $tmpl_name = shift || '';
	my ( $get_tmpl_file, $template_name, $append ) =
	  $tmpl_name =~ /^(-)?([a-zA-Z_][\w -]*?)(\+)?\s*$/;

	return $tmpl unless $template_name;

	if ($get_tmpl_file) {
		$tmpl = $obj->_get_template_from_file($template_name);
		$tmpl .= join '' => @_;
	}
	elsif ( @_ and not $append ) {
		$tmpl = join '' => @_;
	}
	else {
		$tmpl = $KEY{_displays}->{$template_name}
		  || $obj->_get_template_from_file($template_name);
		$tmpl .= join '' => @_ if @_;
	}
	$KEY{_displays}->{$template_name} = $tmpl;

	$obj->_save_template_to_file( $template_name, $tmpl );

	return $tmpl;
}

sub _get_template_from_file {
	my $obj = shift;

	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	%KEY and exists $KEY{_display_dir}
	  or return '';

	my $template_name = shift || '';
	my $tmpl = '';

	if ($template_name) {
		local $/ = undef;
		if ( open my $d, "<", "$KEY{_display_dir}/$template_name" . ".tmpl" ) {
			$tmpl = join( '' => <$d> );
			close $d;
		}
	}
	return $tmpl;
}

sub _save_template_to_file {
	my $obj = shift;

	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	%KEY and exists $KEY{_display_dir}
	  or return '';

	my $template_name = shift || '';
	my $tmpl          = shift || '';

	if ($template_name) {
		open my $t, ">:encoding(UTF8)", "$KEY{_display_dir}/$template_name" . ".tmpl"
		  or return "";
		print $t $tmpl, "\n";
		close $t;
	}

	return $tmpl;
}

## Message: Same as template, with the first optional argument taken as a
## message name. If no more args are given,
## the name is looked up, first in $KEY{_messages} and then
## in the message file $KEY{_message_file}.
## If additional args are given, they are concatenated as
## the message, and nothing is looked up.
## EXCEPTION: A name prepended with '-' will always be looked up in the
## message file, without the starting '-'. In this case,
## any additional args are concatenated and appended to the message.
##
## The resulting message might be ''.
## The resulting message is added UNPROCESSED to $KEY{_messages},
## replacing any message already there with that name.
## The resulting message is then recursively PROCESSED and output.

sub message ($;@) {
	my $arg1 = shift;

	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};

	%KEY or return '';

	my $tmpl_name = shift
	  or return '';

	my $tmpl = '';

	if ( $tmpl_name =~ s/^-([a-zA-Z_][\w -]*)$/$1/ ) {
		$tmpl = $KEY{_messages}->{$tmpl_name} = do {
			local $/ = '';
			my $m = '';
			if ( open M, "<", "$KEY{_message_file}" ) {
				while (<M>) {
					next unless /^$tmpl_name\n/;
					chomp;
					$m = join( '' => ( split "\n" => $_, 2 )[1], @_ );
					last;
				}
				close M;
			}
			$m;
		  }
	}
	elsif (@_) {
		$tmpl = $KEY{_messages}->{$tmpl_name} = join( '' => @_ );
	}
	elsif ($tmpl_name) {
		$tmpl = $KEY{_messages}->{$tmpl_name} ||= do {
			local $/ = '';
			my $m = '';
			if ( open M, "<", "$KEY{_message_file}" ) {
				while (<M>) {
					next unless /^$tmpl_name\s*\n/;
					chomp;
					$m = ( split "\n" => $_, 2 )[1];
				}
				close M;
			}
			$m;
		  }
	}
	return '' unless $tmpl;

	$tmpl = _process_tmpl( \*KEY, $tmpl );

	return $tmpl;
}

## Save_Message: Same as template, with the first optional argument taken as a
## message name. If no more args are given,
## the name is looked up, first in $KEY{_messages} and then
## in the message file $KEY{_message_file}.
## If additional args are given, they are concatenated as
## the message, and nothing is looked up.
## EXCEPTION: A name prepended with '-' will always be looked up in the
## message file, without the starting '-'. In this case,
## any additional args are concatenated and appended to the message.
##
## The resulting message might be ''.
## The resulting message is added UNPROCESSED to $KEY{_messages},
## replacing any message already there with that name.
## The resulting message is also saved in the message file $KEY{_message_file},
## replacing any message already there with that name.
## The resulting message is then recursively PROCESSED and output.

sub save_message ($;@) {
	my $arg1 = shift;

	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};

	%KEY or return '';

	my $tmpl_name = shift
	  or return '';

	my $tmpl = '';

	if ( $tmpl_name =~ s/^-([a-zA-Z_][\w -]*)$/$1/ ) {
		$tmpl = $KEY{_messages}->{$tmpl_name} = do {
			local $/ = '';
			my $m = '';
			if ( open M, "<", "$KEY{_message_file}" ) {
				while (<M>) {
					next unless /^$tmpl_name\n/;
					chomp;
					$m = join( '' => ( split "\n" => $_, 2 )[1], @_ );
					last;
				}
				close M;
			}
			$m;
		  }
	}
	elsif (@_) {
		$tmpl = $KEY{_messages}->{$tmpl_name} = join( '' => @_ );
	}
	elsif ($tmpl_name) {
		$tmpl = $KEY{_messages}->{$tmpl_name} ||= do {
			local $/ = '';
			my $m = '';
			if ( open M, "<", "$KEY{_message_file}" ) {
				while (<M>) {
					next unless /^$tmpl_name\s*\n/;
					chomp;
					$m = ( split "\n" => $_, 2 )[1];
				}
				close M;
			}
			$m;
		  }
	}

	return '' unless $tmpl;

	my $printed = 0;
	my $msg     = $tmpl;

	#$msg			=~ s{(\015?\012)|\015}{\n}gs;
  REPLACE: {
		local $^I   = '';
		local @ARGV = ( $KEY{_message_file} );
		local $/    = '';
	  MSG: while (<>) {
			unless (/^$tmpl_name\s*\n/) {
				print;
				next MSG;
			}
			print $tmpl_name, "\n", $msg, "\n\n";
			$printed++;
		}
	}
  ADD: {
		unless ($printed) {
			if ( open M, ">>:encoding(UTF8)", $KEY{_message_file} ) {
				print M "\n\n", $tmpl_name, "\n", $msg, "\n";
				close M;
			}
		}
	}

	$tmpl = _process_tmpl( \*KEY, $tmpl );

	return $tmpl;
}

## List_items: Same as template, with the first optional argument taken as a
## list name. If no more args are given,
## the name is looked up, first in $KEY{_lists} and then
## in the list file $KEY{_list_file}.
## If additional args are given, they are made into
## the list, and nothing is looked up.
## EXCEPTION: A name prepended with '-' will always be looked up in the
## list file, without the starting '-'. In this case,
## any additional args are appended to the list from the file.
##
## The resulting list might be empty ().
## The resulting list is added UNPROCESSED to $KEY{_lists},
## replacing any list already there with that name.
## If no optional args are given, the ordered elements of
## internal buffer @KEY are used as an anonymous list.
## The resulting list items are then output UNPROCESSED
## as list or an array ref, depending on context.

sub list_items ($;@) {
	my $obj = shift;
	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	%KEY or return '';

	my @list;

	my $list_name = shift;
	unless ($list_name) {
		@list = grep { !ref($_) eq __PACKAGE__ } @KEY;
		return [@list];
	}

	my @supplemental_items = ref( $_[0] ) ? @{ $_[0] } : @_;

	if ( $list_name =~ s/^-([a-zA-Z][-\w ]*)$/$1/ ) {
		unless ( @list = $obj->_list_from_file($list_name) ) {
			unless ( @list = $obj->_list_from_dir($list_name) ) {
				return;
			}
		}
		push @list => @supplemental_items;
	}
	elsif (@supplemental_items) {
		@list = @supplemental_items;
	}
	else {
		if ( exists $KEY{_lists}->{$list_name} ) {
			@list = @{ $KEY{_lists}->{$list_name} };
		}
		else {
			unless ( @list = $obj->_list_from_file($list_name) ) {
				unless ( @list = $obj->_list_from_dir($list_name) ) {
					return;
				}
			}
		}
	}

	$KEY{_lists}->{$list_name} = [@list];

	return wantarray ? @list : [@list];
}

## Save_List_items: Same as template, with the first optional argument taken as a
## list name. If no more args are given,
## the name is looked up, first in $KEY{_lists} and then
## in the list file $KEY{_list_file}.
## If additional args are given, they are made into
## the list, and nothing is looked up.
## EXCEPTION: A name prepended with '-' will always be looked up in the
## list file, without the starting '-'. In this case,
## any additional args are appended to the list.
##
## The resulting list might be empty ().
## The resulting list is added UNPROCESSED to $KEY{_lists},
## replacing any list already there with that name.
## The resulting list is also saved in the list file $KEY{_list_file},
## replacing any list already there with that name.
## If no optional args are given, no list is saved
## and the resulting list is empty ().
## The resulting list items are then output UNPROCESSED
## as an array ref.

sub save_list_items ($;@) {    # same as save_list; kept for legacy
	my $obj = shift;
	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	%KEY or return [];

	my $list_name = shift
	  or return [];

	my @items;
	my @supplemental_items = ref( $_[0] ) ? @{ $_[0] } : @_;
	my $use_default_list = 0;

	if ( $list_name =~ s/^-([a-zA-Z][-\w ]*)$/$1/ ) {
		unless ( @items = $obj->_list_from_file($list_name) ) {
			@items = $obj->_list_from_dir($list_name);
		}
		$use_default_list++ if @items;
		push @items => @supplemental_items;
	}
	unless ($use_default_list) {
		if (@supplemental_items) {
			@items = @supplemental_items;
		}
		elsif ( exists $KEY{_lists}->{$list_name} ) {
			@items = @{ $KEY{_lists}->{$list_name} };
		}
		else {
			unless ( @items = $obj->_list_from_dir($list_name) ) {
				@items = $obj->_list_from_file($list_name);
			}
		}
	}

	my $list_pathname = "$KEY{_list_dir}/$list_name";
	return [] unless open my $lfh, ">:encoding(UTF8)", $list_pathname;
	print $lfh join "\n" => @items, "";
	close $lfh;

	$KEY{_lists}->{$list_name} = [@items];
}

sub save_list ($;@) {
	my $obj = shift;
	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	%KEY or return [];

	my $list_name = shift
	  or return [];

	my @items;
	my @supplemental_items = ref( $_[0] ) ? @{ $_[0] } : @_;
	my $use_default_list = 0;

	if ( $list_name =~ s/^-([a-zA-Z][-\w ]*)$/$1/ ) {
		unless ( @items = $obj->_list_from_file($list_name) ) {
			@items = $obj->_list_from_dir($list_name);
		}
		$use_default_list++ if @items;
		push @items => @supplemental_items;
	}
	unless ($use_default_list) {
		if (@supplemental_items) {
			@items = @supplemental_items;
		}
		elsif ( exists $KEY{_lists}->{$list_name} ) {
			@items = @{ $KEY{_lists}->{$list_name} };
		}
		else {
			unless ( @items = $obj->_list_from_dir($list_name) ) {
				@items = $obj->_list_from_file($list_name);
			}
		}
	}

	my $list_pathname = "$KEY{_list_dir}/$list_name";
	return [] unless open my $lfh, ">:encoding(UTF8)", $list_pathname;
	print $lfh join "\n" => @items, "";
	close $lfh;

	$KEY{_lists}->{$list_name} = [@items];
}

sub save_sys_list ($;@) {
	my $obj = shift;
	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	%KEY or return [];

	my $list_name = shift
	  or return [];

	my @items;
	my $use_default_list = 0;

	if ( $list_name =~ s/^-([a-zA-Z][-\w ]*)$/$1/ ) {
		@items = $obj->_list_from_file($list_name);
		$use_default_list++ if @items;
		push @items => @_;
	}
	unless ($use_default_list) {
		if (@_) {
			@items = @_;
		}
		elsif ( exists $KEY{_lists}->{$list_name} ) {
			@items = @{ $KEY{_lists}->{$list_name} };
		}
		else {
			@items = $obj->_list_from_file($list_name);
			push @items => @_;
		}
	}
	@items = map { /\A([^`]+)\z/ ? $1 : () } @items;

	my $printed = 0;
  REPLACE: {
		local $^I   = '';
		local @ARGV = ( $KEY{_list_file} );
		local $/    = '';
	  LIST: while (<>) {
			unless (/^$list_name\s*\n/) {
				print;
				next LIST;
			}
			print $list_name, "\n", join( "\n" => @items ), "\n\n";
			$printed++;
		}
	}
  ADD: {
		unless ($printed) {
			if ( open my $M, ">>:encoding(UTF8)", $KEY{_list_file} ) {
				print $M "\n\n", $list_name, "\n", join( "\n" => @items ), "\n";
				close $M;
			}
		}
	}

	my $list_dir = $KEY{_list_dir} || '';
	$list_dir = $list_dir eq "./" ? "./lists" : $list_dir;
	unless ( -d $list_dir ) {
		mkdir( $list_dir, oct(777) )
		  or carp "List dir creation failed for $list_dir: $!";
	}

	my $list_pathname = "$list_dir/$list_name";
	return [] unless open my $lfh, ">:encoding(UTF8)", $list_pathname;
	print $lfh join "\n" => @items, "";
	close $lfh;

	$KEY{_lists}->{$list_name} = [@items];
}

sub _list_from_file {
	local *KEY = shift;
	my $list_name = shift;
	my %flist;
	if ( open my $LF, "<", "$KEY{_list_file}" ) {
		local $/ = '';
	  LIST: while ( my $lff = <$LF> ) {
			next LIST unless $lff =~ /\A$list_name\s*\n/;
			$flist{$list_name} = $lff;
			last LIST;
		}
		close $LF;
	}
	return unless exists $flist{$list_name};
	my @items = split "\n" => $flist{$list_name};
	my @list =
	  map { defined && /\A\s*([^`]+)\s*\z/ ? $1 : () } splice( @items, 1 );
	return wantarray ? @list : [@list];
}

sub _list_from_dir {
	local *KEY = shift;
	my $list_name = shift;
	my $list      = '';
	my $list_dir  = $KEY{_list_dir} || '';
	$list_dir = $list_dir eq "./" ? "./lists" : $list_dir;
	return unless -d $list_dir;
	my $list_pathname = "$list_dir/$list_name";
	return unless -e $list_pathname;
	return unless open my $lfh, "<", $list_pathname;
	my @items = <$lfh>;
	close $lfh;
	chomp @items;
	my @list = map { defined && /\A\s*([^`]+)\s*\z/ ? $1 : () } @items;
	return wantarray ? @list : [@list];
}

## Num_list_items: Same as list_items, with the first optional argument taken as a
## list name. If no more args are given,
## the name is looked up, first in $KEY{_lists} and then
## in the list file $KEY{_list_file}.
## If additional args are given, they are made into
## the list, and nothing is looked up.
## EXCEPTION: A name prepended with '-' will always be looked up in the
## list file, without the starting '-'. In this case,
## any additional args are appended to the list.
##
## The resulting list might be empty ().
## The resulting list is added UNPROCESSED to $KEY{_lists},
## replacing any list already there with that name.
## If no optional args are given, the ordered elements of
## internal buffer @KEY are used as an anonymous list.
## The resulting list items are NOT PROCESSED.
## The NUMBER of items in the list is returned.

sub num_list_items ($;@) {
	my $obj = shift;
	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	%KEY or return '';

	my @list;

	my $list_name = shift;
	unless ($list_name) {
		@list = grep { !ref($_) eq __PACKAGE__ } @KEY;
		return scalar @list;
	}

	if ( $list_name =~ s/^-([a-zA-Z][-\w ]*)$/$1/ ) {
		unless ( @list = $obj->_list_from_file($list_name) ) {
			@list = $obj->_list_from_dir($list_name);
		}
		push @list => @_;
	}
	elsif (@_) {
		@list = @_;
	}
	else {
		if ( exists $KEY{_lists}->{$list_name} ) {
			@list = @{ $KEY{_lists}->{$list_name} };
		}
		else {
			unless ( @list = $obj->_list_from_file($list_name) ) {
				@list = $obj->_list_from_dir($list_name);
			}
		}
	}

	$KEY{_lists}->{$list_name} = [@list];

	return scalar @list;
}

## Store: Same as replace, plus all output is written to the filehandle KEY.
##		If no file was specified in the initialization of the object,
##		or attached with attach_file() after initialization,
##		store() will write to a temporary file if called.
##		retrieve() returns the contents of the file, and empties the file.
##		recall() returns the contents of the file.
##		File may be written to (appending) directly by printing to the filehandle KEY,
##		but it's better to use store().
##		File may be read directly from the filehandle KEY using <KEY>, but
##		it's better to use recall().

sub store ($;@) {
	my $arg1 = shift;
	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};

	unless ( defined *KEY{IO} and *KEY{IO}->opened() ) {
		if ( !$KEY{_file} ) {
			return;
		}
		elsif ( $KEY{_file} eq '-' ) {
			open KEY, "+>>:encoding(UTF8)", undef or return;
		}
		elsif ( $KEY{_file} eq '^' ) {
			$KEY{_vfile} ||= '';
			open KEY, "+>>:encoding(UTF8)", \$KEY{_vfile} or return;
		}
		else {
			open KEY, "+>>:encoding(UTF8)", "$KEY{_file}" or return;
		}
		*KEY{IO}->autoflush;
	}

	my $tmpl =
	     join( '' => @_ )
	  || $KEY
	  || $KEY{_default_tmpl};

	my $output = _process_tmpl( \*KEY, $tmpl );

	print KEY $output;

	close KEY unless $KEY{_file_keep_open};

	return $output;
}

# store_file Same as replace, plus all output is written to the filehandle KEY,
## 		overwriting anything already in the file.
##		If no file was specified in the initialization of the object,
##		or attached with attach_file() after initialization,
##		store() will write to a temporary file if called.
##		retrieve() returns the contents of the file, and empties the file.
##		recall() returns the contents of the file.
##		File may be written to directly by printing to the filehandle KEY,
##		but it's better to use store_file().
##		File may be read directly from the filehandle KEY using <KEY>, but
##		it's better to use recall().

sub store_file ($;@) {
	my $arg1 = shift;
	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};

	if ( defined *KEY{IO} and *KEY{IO}->opened() ) {
		truncate( KEY, 0 );
	}
	else {
		if ( !$KEY{_file} ) {
			return;
		}
		elsif ( $KEY{_file} eq '-' ) {
			open KEY, ">:encoding(UTF8)", undef or return;
		}
		elsif ( $KEY{_file} eq '^' ) {
			$KEY{_vfile} ||= '';
			open KEY, ">:encoding(UTF8)", \$KEY{_vfile} or return;
		}
		else {
			open KEY, ">:encoding(UTF8)", "$KEY{_file}" or return;
		}
		*KEY{IO}->autoflush;
	}

	my $tmpl =
	     join( '' => @_ )
	  || $KEY
	  || $KEY{_default_tmpl};

	my $output = _process_tmpl( \*KEY, $tmpl );

	print KEY $output;

	close KEY unless $KEY{_file_keep_open};

	return $output;
}

## Store data: Appends data in %KEY to the attached file
## as a stringified hash. If arguments are provided, they are used as
## field names; otherwise all fields are used. If a field name is not
## in the %KEY hash, an empty string is stored. Only stores main data
## with scalar values or array/hash references; skips meta-data (fields starting with '_'), fields that
## contain non-ARRAY/HASH references, and the object's KEY field (holding marked input).
## Does not process data, except to provide '' for empty non-zero field values.
## Returns a hash of the stored values.
sub store_data ($;@) {
	my $arg1 = shift;
	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};

	return unless scalar keys %KEY;

	unless ( defined *KEY{IO} and *KEY{IO}->opened() ) {
		if ( !$KEY{_file} ) {
			return;
		}
		elsif ( $KEY{_file} eq '-' ) {
			open KEY, "+>>:encoding(UTF8)", undef or return;
		}
		elsif ( $KEY{_file} eq '^' ) {
			$KEY{_vfile} ||= '';
			open KEY, "+>>:encoding(UTF8)", \$KEY{_vfile} or return;
		}
		else {
			open KEY, "+>>:encoding(UTF8)", "$KEY{_file}" or return;
		}
		*KEY{IO}->autoflush;
	}

	my %_KEY;
	for my $key ( @_ ? @_ : sort keys %KEY ) {
		if ($key =~ /^-.*$/) {
			$arg1->calculate($key);
		}
		next if $key eq $KEY{_mark};
		next if $key eq $KEY{_ui_mark};
		next if $key =~ /^_/;
		next if ref( $KEY{$key} ) =~ /(CODE|GLOB)/;

		$_KEY{$key} = defined $KEY{$key} ? $KEY{$key} : '';
	}

	local $Data::Dumper::Purity   = 1;
	local $Data::Dumper::Sortkeys = 1;
	print KEY Data::Dumper->Dump( [ \%_KEY ], [qw/*_KEY/] );    #
	print KEY "\n#=\n";
	close KEY unless $KEY{_file_keep_open};
	wantarray ? %_KEY : \%_KEY;
}

## Store JSON: Appends data in %KEY to the attached file
## as a stringified JSON object. If arguments are provided, they are used as
## field names; otherwise all fields are used. If a field name is not
## in the %KEY hash, an empty string is stored. Only stores main data
## with scalar values or array/hash references; skips meta-data (fields starting with '_')
## EXCEPT for the _meta field (2017-08-08), fields that
## contain non-ARRAY/HASH references, and the object's KEY field (holding marked input).
## Does not process data, except to provide '' for empty/false non-zero field values.
## Returns a hash of the stored values.
sub store_json ($;@) {
	my $arg1 = shift;
	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};

	return unless scalar keys %KEY;

	unless ( defined *KEY{IO} and *KEY{IO}->opened() ) {
		if ( !$KEY{_file} ) {
			return;
		}
		elsif ( $KEY{_file} eq '-' ) {
			open KEY, "+>>:encoding(UTF8)", undef or return;
		}
		elsif ( $KEY{_file} eq '^' ) {
			$KEY{_vfile} ||= '';
			open KEY, "+>>:encoding(UTF8)", \$KEY{_vfile} or return;
		}
		else {
			open KEY, "+>>:encoding(UTF8)", "$KEY{_file}" or return;
		}
		*KEY{IO}->autoflush;
	}

	my %_KEY;
	for my $key ( @_ ? @_ : sort keys %KEY ) {
		next if $key eq $KEY{_mark};
		next if $key =~ /^_(?!meta)/;
		next if ref( $KEY{$key} ) =~ /(CODE|GLOB)/;
		$_KEY{$key} = defined $KEY{$key} ? $KEY{$key} : '';
	}

	print KEY encode_json( \%_KEY );
	print KEY "\n#=\n";
	close KEY unless $KEY{_file_keep_open};

	wantarray ? %_KEY : \%_KEY;
}

## Store META: Appends data in %KEY to the attached file
## as a serialized hash object. If arguments are provided, they are used as
## field names; otherwise all fields are used. If a field name is not
## in the %KEY hash, an empty string is stored. Only stores meta data
## (fields starting with '_'); skips fields that contain CODE or GLOB references,
## and the object's KEY field (holding marked input).
## Does not process data, except to provide '' for empty non-zero field values.
## Returns a hash of the stored values.
sub store_meta ($;@) {
	my $arg1 = shift;
	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};

	return unless scalar keys %KEY;

	unless ( defined *KEY{IO} and *KEY{IO}->opened() ) {
		if ( !$KEY{_file} ) {
			return;
		}
		elsif ( $KEY{_file} eq '-' ) {
			open KEY, "+>>:encoding(UTF8)", undef or return;
		}
		elsif ( $KEY{_file} eq '^' ) {
			$KEY{_vfile} ||= '';
			open KEY, "+>>:encoding(UTF8)", \$KEY{_vfile} or return;
		}
		else {
			open KEY, "+>>:encoding(UTF8)", "$KEY{_file}" or return;
		}
		*KEY{IO}->autoflush;
	}

	my %_META;
	for my $key ( @_ ? @_ : sort keys %KEY ) {
		next if $key eq $KEY{_mark};
		next unless $key =~ /^_/;
		next if ref( $KEY{$key} ) =~ /(CODE|GLOB)/;

		$_META{$key} = defined $KEY{$key} ? $KEY{$key} : '';
	}

	local $Data::Dumper::Purity   = 1;
	local $Data::Dumper::Deepcopy = 1;
	local $Data::Dumper::Pair     = ' => ';    # ' : '
	print KEY Data::Dumper->Dump( [ \%_META ], [qw/*_META/] );
	print KEY "\n#=\n";
	close KEY unless $KEY{_file_keep_open};

	wantarray ? %_META : \%_META;
}

## Restore data: Reads back any data stored in the attached file.
## Data read back is eval()-ed on the assumption that it is a
## serialized hash named %_KEY; anything else in the file is ignored, EXCEPT
## that any statement must eval() OK, including 'strict' requirements.
## The hash is then added to the existing %KEY, over-writing fields with
## the same names. Allows multiple serialized hashes to be read in, in the order
## they were stored, resulting in the latest values for fields stored more than once.
## Does not process data; does not alter the file.
## Returns a hash of the restored values.
sub restore_data {
	my $arg1 = shift;
	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};

	local $/ = "\n#=\n";

	my $old_tell;
	if ( defined *KEY{IO} and *KEY{IO}->opened() ) {
		$old_tell = tell KEY;
	}
	elsif ( !$KEY{_file} ) {
		return;
	}
	elsif ( $KEY{_file} eq '-' ) {
		return;
	}
	elsif ( $KEY{_file} eq '^' ) {
		$KEY{_vfile} ||= '';
		open KEY, "+>>:encoding(UTF8)", \$KEY{_vfile} or return;
		$old_tell = tell KEY;
	}
	else {
		open KEY, "+>>:encoding(UTF8)", "$KEY{_file}" or return;
		$old_tell = tell KEY;
	}
	seek( KEY, 0, 0 );

	my %_KEY;
	my %_KEYS;

	while (<KEY>) {
		next unless /^([^`]+)$/;
		my $d = $1;
		next unless eval $d;
		$_KEYS{$_}++ for keys %_KEY;
		*KEY = { %KEY, %_KEY };
	}
	seek KEY, $old_tell, 0;
	close KEY unless $KEY{_file_keep_open};

	wantarray
	  ? map { $_ => $KEY{$_} || '' } keys %_KEYS
	  : { map { $_ => $KEY{$_} || '' } keys %_KEYS };
}

## Restore json: Reads back json-formatted data stored in the attached file.
## Data read back is json_decode-d into a hash assuming that it is valid json .
## The hash is then added to the existing %KEY, over-writing fields with
## the same names. Allows multiple serialized hashes to be read in, in the order
## they were stored, resulting in the latest values for fields stored more than once.
## Does not process data; does not alter the file.
## Returns a hash of the restored values.
sub restore_json {
	my $arg1 = shift;
	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};

	local $/ = "\n#=\n";

	my $old_tell;
	if ( defined *KEY{IO} and *KEY{IO}->opened() ) {
		$old_tell = tell KEY;
	}
	elsif ( !$KEY{_file} ) {
		return;
	}
	elsif ( $KEY{_file} eq '-' ) {
		return;
	}
	elsif ( $KEY{_file} eq '^' ) {
		$KEY{_vfile} ||= '';
		open KEY, "+>>:encoding(UTF8)", \$KEY{_vfile} or return;
		$old_tell = tell KEY;
	}
	else {
		open KEY, "+>>:encoding(UTF8)", "$KEY{_file}" or return;
		$old_tell = tell KEY;
	}
	seek( KEY, 0, 0 );

	my %_KEY;
	my %_KEYS;

	while (<KEY>) {
		chomp;
		next unless /^([^`]+)$/;
		my $d = $1;
		%_KEY = $d ? %{ decode_json $d } : ();
		$_KEYS{$_}++ for keys %_KEY;
		*KEY = { %KEY, %_KEY };
	}
	seek KEY, $old_tell, 0;
	close KEY unless $KEY{_file_keep_open};

	wantarray
	  ? map { $_ => $KEY{$_} || '' } keys %_KEYS
	  : { map { $_ => $KEY{$_} || '' } keys %_KEYS };
}

## retrieve_data, same as restore_data,
## except it also empties the file, like retrieve()
sub retrieve_data {
	my $arg1 = shift;
	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};

	local $/ = "\n#=\n";

	unless ( defined *KEY{IO} and *KEY{IO}->opened() ) {
		if ( !$KEY{_file} ) {
			return qq{};
		}
		elsif ( $KEY{_file} eq '-' ) {
			return qq{};
		}
		elsif ( $KEY{_file} eq '^' ) {
			$KEY{_vfile} ||= '';
			open KEY, "+>>:encoding(UTF8)", \$KEY{_vfile} or return qq{};
		}
		else {
			open KEY, "+>>:encoding(UTF8)", "$KEY{_file}" or return qq{};
		}
	}
	seek( KEY, 0, 0 );

	my %_KEY;
	my %_KEYS;

	while (<KEY>) {
		next unless /^([^`]+)$/;
		my $d = $1;
		next unless eval $d;
		$_KEYS{$_}++ for keys %_KEY;
		*KEY = { %KEY, %_KEY };
	}

	truncate( KEY, 0 );
	close KEY unless $KEY{_file_keep_open};

	wantarray
	  ? map { $_ => $KEY{$_} || '' } keys %_KEYS
	  : { map { $_ => $KEY{$_} || '' } keys %_KEYS };
}

## file_data/recall_data, same as restore_data,
## except it does NOT insert the recalled data into the main %KEY hash.
## Opens file provided in optional arg, or $KEY{_file} if available.
## Allows multiple serialized hashes to be read in, in the order
## they were stored, resulting in the latest values for fields stored more than once.
## Does not process data; does not alter the file.
## Returns a HASHREF of the stored values.
# sub recall_data {
sub file_data {
	my $arg1 = shift;
	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};

	my $file = shift || '';
	my @entries = ();

	if ( $file and -s $file ) {
		open my $fh, "<", $file or return {};
		local $/ = "\n#=\n";
		@entries = (<$fh>);
		close $fh;
	}
	elsif ( $KEY{_file} ) {
		my $old_tell;
		unless ( defined *KEY{IO} and *KEY{IO}->opened() ) {
			if ( !$KEY{_file} ) {
				return {};
			}
			elsif ( $KEY{_file} eq '-' ) {
				return {};
			}
			elsif ( $KEY{_file} eq '^' ) {
				$KEY{_vfile} ||= '';
				open KEY, "+>>:encoding(UTF8)", \$KEY{_vfile} or return qq{};
				$old_tell = tell KEY;
			}
			else {
				open KEY, "+>>:encoding(UTF8)", "$KEY{_file}" or return qq{};
				$old_tell = tell KEY;
			}
		}
		seek( KEY, 0, 0 );
		local $/ = "\n#=\n";
		@entries = (<KEY>);
		seek KEY, $old_tell, 0;
		close KEY unless $KEY{_file_keep_open};
	}
	else {
		return {};
	}

	my %_KEY;
	my %NEW;

	for (@entries) {
		next unless /^([^`]+)$/;
		my $d = $1;
		next unless eval $d;
		%NEW = ( %NEW, %_KEY );
	}

	\%NEW;
}

## Retrieve: Analogous to flush; reads and returns contents of file
## to which store() has written, and empties the file.
sub retrieve ($) {
	my $obj = shift;

	local *KEY = $obj->invert();

	local $/ = undef;

	unless ( defined *KEY{IO} and *KEY{IO}->opened() ) {
		if ( !$KEY{_file} ) {
			return qq{};
		}
		elsif ( $KEY{_file} eq '-' ) {
			return qq{};
		}
		elsif ( $KEY{_file} eq '^' ) {
			$KEY{_vfile} ||= '';
			open KEY, "+>>:encoding(UTF8)", \$KEY{_vfile} or return qq{};
		}
		else {
			open KEY, "+>>:encoding(UTF8)", "$KEY{_file}" or return qq{};
		}
	}
	seek( KEY, 0, 0 );

	my $retr = <KEY>;
	truncate( KEY, 0 );
	close KEY unless $KEY{_file_keep_open};
	$retr;
}

## Recall: reads the file to which store()
## has written, and returns an array of
## its lines in list context, or its first line
## in scalar context, and leaves the file unchanged.
## A non-zero value in the first optional arg reverses the list order
## and causes the LAST line to be returned in scalar context.
## "Lines" are chunks of the file terminated by the
## second optional arg, if any, or Perl's $/, usually \n. The
## second arg may be any string; it's chomped off.
sub recall ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my $reverse = shift() ? 1 : 0;

	local $/ = shift() || $/;    #

	my $old_tell;
	if ( defined *KEY{IO} and *KEY{IO}->opened() ) {
		$old_tell = tell KEY;
	}
	elsif ( !$KEY{_file} ) {
		return qq{};
	}
	elsif ( $KEY{_file} eq '-' ) {
		return qq{};
	}
	elsif ( $KEY{_file} eq '^' ) {
		open KEY, "+>>:encoding(UTF8)", \$KEY{_vfile} or return qq{};
		$old_tell = tell KEY;
	}
	else {
		open KEY, "+>>:encoding(UTF8)", "$KEY{_file}" or return qq{};
		$old_tell = tell KEY;
	}
	seek( KEY, 0, 0 );

	my @lines = <KEY>;

	seek KEY, $old_tell, 0;
	close KEY unless $KEY{_file_keep_open};

	chomp @lines;

	@lines = map { /^([^`]+)$/ ? $1 : () } @lines;

	@lines = reverse @lines if $reverse;

	wantarray ? @lines : $lines[0];
}

## Recall_match: reads the file to which store()
## has written line by line, and returns an array of
## the lines matching the first optional arg in list context, or
## the first matching line in scalar context, and leaves the file unchanged.
## The first arg may be any string or regular expression.
## A non-zero value in the second arg reverses the list order
## and causes the LAST matching line to be returned in scalar context.
## "Lines" are chunks of the file terminated by the
## third arg, if any, or Perl's $/, usually \n. The
## third arg may be any string; it's chomped off.
## A non-zero value in the fourth arg causes the byte number of
## each match to be returned; this may be used by recall_seek().
sub recall_match ($$;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my $match = shift() or return wantarray ? () : '';

	my $reverse = shift() ? 1 : 0;

	local $/ = shift() || $/;

	my $want_byte = shift() ? 1 : 0;

	my $start_tell;
	if ( defined *KEY{IO} and *KEY{IO}->opened() ) {
		$start_tell = tell KEY;
	}
	elsif ( !$KEY{_file} ) {
		return qq{};
	}
	elsif ( $KEY{_file} eq '-' ) {
		return qq{};
	}
	elsif ( $KEY{_file} eq '^' ) {
		open KEY, "+>>:encoding(UTF8)", \$KEY{_vfile} or return qq{};
		$start_tell = tell KEY;
	}
	else {
		open KEY, "+>>:encoding(UTF8)", "$KEY{_file}" or return qq{};
		$start_tell = tell KEY;
	}

	seek( KEY, 0, 0 );

	my %matches;
	my $tell     = 0;
	my $byte_key = 0;
	while ( my $line = <KEY> ) {
		$byte_key = $tell;
		$tell     = tell(KEY);
		next unless $line =~ /$match/;
		chomp $line;
		$matches{$byte_key} = $line;
	}
	seek KEY, $start_tell, 0;

	close KEY unless $KEY{_file_keep_open};

	my @keys =
	  $reverse
	  ? reverse sort keys %matches
	  : sort keys %matches;

	if ($want_byte) {
		wantarray ? map { $_ => $matches{$_} } @keys : $keys[0];
	}
	else {
		wantarray ? @matches{@keys} : $matches{ $keys[0] };
	}
}

## Recall_seek: reads the file to which store()
## has written,
sub recall_seek ($$;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my $tell = shift() || 0;

	my $index = shift() ? -2 : 0;

	local $/ = shift() || $/;

	my $old_tell;
	if ( defined *KEY{IO} and *KEY{IO}->opened() ) {
		$old_tell = tell KEY;
	}
	elsif ( !$KEY{_file} ) {
		return qq{};
	}
	elsif ( $KEY{_file} eq '-' ) {
		return qq{};
	}
	elsif ( $KEY{_file} eq '^' ) {
		open KEY, "+>>:encoding(UTF8)", \$KEY{_vfile} or return qq{};
		$old_tell = tell KEY;
	}
	else {
		open KEY, "+>>:encoding(UTF8)", "$KEY{_file}" or return qq{};
		$old_tell = tell KEY;
	}
	seek( KEY, 0, 0 );

	my @matches;
	for my $t ( ref($tell) ? @{$tell} : ($tell) ) {
		seek KEY, $t, 0;
		my $line = <KEY>;
		push @matches => $t, $line;
	}

	chomp @matches;
	seek KEY, $old_tell, 0;
	close KEY unless $KEY{_file_keep_open};

	wantarray ? @matches : $matches[$index];
}

## Form: designates the form (template) against which replace() etc. operate
## and returns the form UNPROCESSED. Accepts '' as a form.
## If no form argument is provided, returns the current form or ''.
## Copies the form to $KEY.
## A form may be assigned directly to $KEY as a string.
## The current form may be read directly from $KEY.
## Note: $KEY is left unchanged when other forms/templates are passed
## as arguments to replace() etc.

sub form ($;@) {
	my ( $self, @args ) = @_;
	local *KEY = *{$self};
	return ( $KEY || '' ) unless defined $args[0];
	{
		my $ref = ref( $args[0] );
		if ( $ref =~ /HASH/ ) {
			$KEY = ( $args[0]->{_form} || $args[0]->{_tmpl} || '' );
		}
		elsif ( $ref =~ /ARRAY/ ) {
			$KEY = join '' => '', @{ $args[0] } || ('');
		}
		elsif ( $ref =~ /CODE/ ) {
			$KEY = join '' => '', @{ $args[0]->() } || ('');
		}
		else {
			$KEY = join '' => '', @args;
		}
	}
	$KEY;
}

## Charge: safely adds data to %KEY, and returns updated ui object.
## Over-writes existing fields with the same names, but doesn't
## accept any data from fields whose names start with '_'.
sub charge ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %NEW;
	{
		local $_ = ref( $_[0] );
		/HASH/ and %NEW = %{ $_[0] }
		  or /ARRAY/ and %NEW = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' )
		  : @{ $_[0] }
		  or /CODE/ and %NEW = %{ $_[0]->() }
		  or %NEW =
		  @_ % 2
		  ? ( @_, '' )
		  : @_
	}

	%KEY = ( %KEY, map { /^_/ ? () : ( $_ => $NEW{$_} ) } keys %NEW );

	return $obj;
}

## Charge Chomped: safely adds data to %KEY, and returns updated ui object.
## Over-writes existing fields with the same names, but doesn't
## accept any data from fields whose names start with '_'.
## Removes system end-of-line
sub charge_chomped ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %NEW;
	{
		local $_ = ref( $_[0] );
		/HASH/ and %NEW = %{ $_[0] }
		  or /ARRAY/ and %NEW = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' )
		  : @{ $_[0] }
		  or /CODE/ and %NEW = %{ $_[0]->() }
		  or %NEW =
		  @_ % 2
		  ? ( @_, '' )
		  : @_
	}

	chomp $NEW{$_} for keys %NEW;

	%KEY = ( %KEY, map { /^_/ ? () : ( $_ => $NEW{$_} ) } keys %NEW );

	return $obj;
}

## Charge_meta:  safely adds meta-data to %KEY, and returns updated ui object.
## Similar to charge, but only accepts data from fields whose names start with '_'.
## Over-writes existing fields with same names.
sub charge_meta ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %NEW;
	{
		local $_ = ref( $_[0] );
		/HASH/ and %NEW = %{ $_[0] }
		  or /ARRAY/ and %NEW = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' )
		  : @{ $_[0] }
		  or /CODE/ and %NEW = %{ $_[0]->() }
		  or %NEW =
		  @_ % 2
		  ? ( @_, '' )
		  : @_
	}

	%KEY = ( %KEY, map { /^_/ ? ( $_ => $NEW{$_} ) : () } keys %NEW );

	return $obj;
}

## Charge_as_meta:  safely adds meta-data to %KEY, and returns updated ui object.
## Similar to charge_meta, but accepts data from fields with any names.
## Adds '_' to the start of field names that don't already have it.
## Over-writes existing fields with same names.
sub charge_as_meta ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %NEW;
	{
		local $_ = ref( $_[0] );
		/HASH/ and %NEW = %{ $_[0] }
		  or /ARRAY/ and %NEW = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' )
		  : @{ $_[0] }
		  or /CODE/ and %NEW = %{ $_[0]->() }
		  or %NEW =
		  @_ % 2
		  ? ( @_, '' )
		  : @_
	}

	%KEY = (
		%KEY,
		map { /^_/ ? ( $_ => $NEW{$_} ) : ( "_$_" => $NEW{$_} ) } keys %NEW
	);

	return $obj;
}

sub charge_sqlite_meta {
	my $obj = shift;

	local *KEY = $obj->invert();

	return unless $KEY{_dbh};

	$obj->db_prepare( $obj->resolve(q{PRAGMA table_info([:_table])}) );
	$obj->sth->execute();
	$obj->charge_meta(
		'_fields' => [ map { $_->[1] } @{ $obj->sth->fetchall_arrayref } ] );

	$obj->db_prepare(
		$obj->resolve(q{ SELECT * FROM [:_table] WHERE meta IS ? }) );

	for (qw/label type size format default null/) {
		$obj->sth->execute($_);
		$obj->charge_meta( "_$_" => $obj->sth->fetchrow_hashref );
	}

	return $obj;
}

## Charge_all: safely adds data and meta-data to %KEY, and returns updated ui object.
## Over-writes existing fields with the same names.
sub charge_all ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %NEW;
	{
		local $_ = ref( $_[0] );
		/HASH/ and %NEW = %{ $_[0] }
		  or /ARRAY/ and %NEW = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' )
		  : @{ $_[0] }
		  or /CODE/ and %NEW = %{ $_[0]->() }
		  or %NEW =
		  @_ % 2
		  ? ( @_, '' )
		  : @_
	}

	%KEY = ( %KEY, %NEW );

	return $obj;
}

## Charge_these: safely adds data and meta-data to specified fields of %KEY,
## and returns updated ui object. The first arg is a comma-separated string or
## an arrayref listing the fields to be changed.
## The following args are the values, in order of the listed fields.
## Over-writes existing fields with the same names.
sub charge_these ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my $flds = shift();
	my @flds = ref($flds) ? @{$flds} : split( /\s*,\s*/ => $flds );
	my %NEW  = map { $_ => shift() } @flds;

	%KEY = ( %KEY, %NEW );

	return $obj;
}

## Charge_auto: executes anonymous sub stored in $KEY{_auto}, and returns updated ui object.
## $KEY{_auto} may hold any series of actions, usually including charge methods.
## Executed for each UI object by render() just before rendering.
sub charge_auto ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	$KEY{_auto}
	  and $KEY{_auto}->();

	return $obj;
}

## Calculate: executes code references stored in %KEY, and returns updated ui object.
## Coderefs may be called by name as optional args; if no optional args are provided,
## all fields in %KEY with names starting with a hyphen '-' will be called, sorted alphabetically.
## Coderefs stored in fields whose names start with a hyphen '-' return their results
## to fields of the same name without the starting hyphen, replacing any value previously there.
## E.g.: A calculation stored in the field -fullname will put its result in the field fullname.
## A calculation stored in a field named without the starting hyphen will put its
## result in a field of the same name with '_out' appended, replacing any value previously there.
## If the value of the field is not a coderef, the value itself is returned.
## Coderefs generally should only alter values in fields to which they return their results;
## however, .
## The coderef is passed an anonymous UI object charged with data from %KEY.
## Circular references:
## Forced context:
## Order of execution:
##
## Examples:
# 	$ui->charge(-system_status => sub {
# 		my $obj	= shift;
# 		$obj->charge(test_mode_status => ($obj->data('test_mode') ? "Test Mode On" : "Test Mode Off"));
# 		return $obj->resolve('[:title]: Now at [:state] - [:test_mode_status]');
# 	});
#
# 	$ui->charge(-admin_test_checkbox => sub {
# 		my $obj	= shift;
# 		my ($ses_obj)	= $obj->objects('SES');
# 		if ($ses_obj->data('group') eq 'admin' and $obj->data('test_mode')) {
#  			return $ui->process(qq{INPUT=do_test,,c:2,,Test});
# 		} else {
# 			return "";
# 		}
# 	});
#
## Calculate() is called by render() for each UI object's '-' flds just before rendering, but after
## charge_auto has been called for that object.
sub calculate ($;@) {
	my $obj = shift;
	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};
	my @flds = @_ ? @_ : sort grep { /^-./ } keys %KEY;
	my $ui_obj = $obj->direct();
	for my $fld (@flds) {

		# charge with updated COPY of %KEY each time
		$ui_obj->charge( {%KEY} );
		my $result;
		if ( ref( $KEY{$fld} ) =~ /CODE/ ) {
			$result = $KEY{$fld}->($ui_obj);
		}
		else {
			# don't process, but see charge_as_calc()
			$result = $KEY{$fld} || '';
		}
		if ( $fld =~ /^-(.+)$/ ) {
			$KEY{$1} = $result;
		}
		else {
			$KEY{ $fld . '_out' } = $result;
		}
		$ui_obj->clear();
	}

	# %KEY;
	return $obj;
}

sub calculated_data ($;@) {
	my $obj = shift;
	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};
	my @flds = @_ ? @_ : sort grep { /^-./ } keys %KEY;
	my $ui_obj = $obj->direct();
	my @calcflds;
	for my $fld (@flds) {

		# charge with updated COPY of %KEY each time
		$ui_obj->charge( {%KEY} );
		my $result;
		if ( ref( $KEY{$fld} ) =~ /CODE/ ) {
			$result = $KEY{$fld}->($ui_obj);
		}
		elsif ( ref( $KEY{"-$fld"} ) =~ /CODE/ ) {
			$result = $KEY{"-$fld"}->($ui_obj);
		}
		else {
			# don't process, but see charge_as_calc()
			$result = $KEY{$fld} || '';
		}
		if ( $fld =~ /^-(.+)$/ ) {
			$KEY{$1} = $result;
			push @calcflds => $1;
		}
		else {
			$KEY{ $fld . '_out' } = $result;
			push @calcflds => $fld . '_out';
		}
		$ui_obj->clear();
	}
	return @KEY{@calcflds};
}

## Charge_as_calc:  safely adds calculating fields to %KEY, and returns updated ui object.
## Expects subroutine references; if the new value is not a coderef, wraps it in an
## anonymous subroutine that returns the value, dereferencing it and stringifying
## it according to the type of reference.
## Adds '-' to the start of field names that don't already have it.
## Over-writes existing fields with same names (including the hyphen).
## The result of a calculation will be put in the corresponding data field
## named without the starting '-'.
sub charge_as_calc ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %NEW;
	my $new_type = ref( $_[0] );
	if ( $new_type =~ /HASH/ ) {
		%NEW = %{ $_[0] };
	}
	elsif ( $new_type =~ /ARRAY/ ) {
		%NEW = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' ) : @{ $_[0] };
	}
	elsif ( $new_type =~ /CODE/ ) {
		%NEW = %{ $_[0]->() };
	}
	else {
		%NEW = @_ % 2 ? ( @_, '' ) : @_;
	}

	for my $k ( keys %NEW ) {
		my $c = $NEW{$k};
		$k =~ s/^-?(.*)$/$1/;
		if ( ref($c) =~ /CODE/ ) {
			$KEY{"-$k"} = $c;
		}
		elsif ( ref($c) =~ /SCALAR/ ) {
			$KEY{"-$k"} = sub { return ${$c} };
		}
		elsif ( ref($c) =~ /ARRAY/ ) {
			$KEY{"-$k"} = sub { return join " " => @{$c} };
		}
		elsif ( ref($c) =~ /HASH/ ) {

			# sort keys here so a given input always comes out the same
			$KEY{"-$k"} = sub {
				return
				  join ", " => map { uc($_) . ": $c->{$_}" } sort keys %{$c};
			};
		}
		else {
			$KEY{"-$k"} = sub { return $c; };
		}
	}

	return $obj;
}

## Charge_msg: safely stores a message in the internal subroutine $KEY{_msg},
## creating $KEY{_msg} if necessary with make_msg().
## The first optional arg is a string or a hash reference, following the
## requirements of make_msg
sub charge_msg ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my $arg = shift;
	$KEY{_msg} ||= make_msg( \*KEY );

	$KEY{_msg}->($arg);

	return $obj;
}

## Charge_err: safely stores a message in the internal subroutine $KEY{_err},
## creating $KEY{_err} if necessary with make_msg().
sub charge_err ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my $arg = shift;
	$KEY{_err} ||= make_msg( \*KEY );

	$KEY{_err}->($arg);

	return $obj;
}

## Charge_xor: safely adds data and meta-data to %KEY, and returns updated ui object.
## Over-writes values in existing fields with the same names only in fields evaluating to false.
sub charge_xor ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %NEW;
	{
		local $_ = ref( $_[0] );
		/HASH/ and %NEW = %{ $_[0] }
		  or /ARRAY/ and %NEW = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' )
		  : @{ $_[0] }
		  or /CODE/ and %NEW = %{ $_[0]->() }
		  or %NEW =
		  @_ % 2
		  ? ( @_, '' )
		  : @_
	}

	%KEY = ( %KEY, ( map { $KEY{$_} ? () : ( $_ => $NEW{$_} ) } keys %NEW ) );

	return $obj;
}

## Charge_or: safely adds data and meta-data to %KEY, and returns updated ui object.
## Does not over-write existing fields with the same names.
sub charge_or ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %NEW;
	{
		local $_ = ref( $_[0] );
		/HASH/ and %NEW = %{ $_[0] }
		  or /ARRAY/ and %NEW = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' )
		  : @{ $_[0] }
		  or /CODE/ and %NEW = %{ $_[0]->() }
		  or %NEW =
		  @_ % 2
		  ? ( @_, '' )
		  : @_
	}

	%KEY =
	  ( %KEY, ( map { exists $KEY{$_} ? () : ( $_ => $NEW{$_} ) } keys %NEW ) );

	return $obj;
}

## Charge_true: safely adds data and meta-data to %KEY, and returns updated ui object.
## Over-writes existing fields with the same names only if the new data evaluates to 'true'.
sub charge_true ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %NEW;
	{
		local $_ = ref( $_[0] );
		/HASH/ and %NEW = %{ $_[0] }
		  or /ARRAY/ and %NEW = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' )
		  : @{ $_[0] }
		  or /CODE/ and %NEW = %{ $_[0]->() }
		  or %NEW =
		  @_ % 2
		  ? ( @_, '' )
		  : @_
	}

	# special case for null dates
	%KEY = (
		%KEY,
		(
			map { $_ => $NEW{$_} }
			grep { $NEW{$_} and $NEW{$_} !~ /0000-00-00/ } keys %NEW
		)
	);

	return $obj;
}

## Charge_valid: safely adds validated data and meta-data to %KEY, and returns updated ui object.
## Data is validated by a test passed in as the first optional arg. The test may be a reference
## to a function that tests some aspect of the new value for each field being charged.
## The test may also be the number 1, the string '1', or the string 'true' (case-insensitive;
## if so, the new values for fields being charged must resolve to a Perl "true" value.
## Likewise, the test may be the number 0 (zero), the string '0', the empty string '',
## or the string 'false' (case-insensitive); if so, the new values for fields
## being charged must resolve to a Perl "false" value. [Use case?]
## Only fields of %KEY for which the new values pass the test are updated.
## TODO: test by type
sub charge_valid ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my $test = shift;

	my %NEW;
	{
		local $_ = ref( $_[0] );
		/HASH/ and %NEW = %{ $_[0] }
		  or /ARRAY/ and %NEW = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' )
		  : @{ $_[0] }
		  or /CODE/ and %NEW = %{ $_[0]->() }
		  or %NEW =
		  @_ % 2
		  ? ( @_, '' )
		  : @_
	}

	if ( defined $test and scalar @_ ) {

		if ( ref($test) =~ /CODE/ ) {
			%NEW =
			  map { $_ => $NEW{$_} } grep { $test->( $NEW{$_} ) } keys %NEW;
		}
		elsif ( $test =~ /^(1|true)$/i ) {
			%NEW = map { $_ => $NEW{$_} } grep { $NEW{$_} } keys %NEW;
		}
		elsif ( $test =~ /^(0|false|)$/i ) {
			%NEW = map { $_ => $NEW{$_} } grep { !$NEW{$_} } keys %NEW;
		}
		else {
			%NEW = ();
		}
		%KEY = ( %KEY, %NEW );

	}

	return $obj;
}

## Charge_marked:  safely adds marked input data to %KEY, and returns updated ui object.
## Similar to charge, but only accepts data from fields whose
## names start with 'MARK:' or 'MARK_', or end with '_MARK' where MARK is $KEY{_mark} (which is 'KEY').
## If no argument is given, inserts marked input data stored in $KEY{$KEY{_mark}} (same as $KEY{_vals}).
## Over-writes existing fields with same names (with the mark stripped off).
sub charge_marked ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	unless (@_) {
		*KEY = { %KEY, %{ $KEY{ $KEY{_mark} } || {} } };
		return %KEY;
	}

	my @flds = ref( $_[0] ) ? @{ $_[0] } : @_;
	my %NEW;
	for (@flds) {
		exists $KEY{_input}->{"$KEY{_mark}:$_"}
		  and do { $NEW{$_} = $KEY{_input}->{"$KEY{_mark}:$_"}; 1 }
		  or exists $KEY{_input}->{"$KEY{_mark}_$_"}
		  and do { $NEW{$_} = $KEY{_input}->{"$KEY{_mark}_$_"}; 1 }
		  or exists $KEY{_input}->{"${_}_$KEY{_mark}"}
		  and do { $NEW{$_} = $KEY{_input}->{"${_}_$KEY{_mark}"}; 1 };
	}

	%KEY = ( %KEY, %NEW );

	#	*KEY	= { %KEY, %NEW };

	return $obj;
}

## Charge from input: safely adds input data to %KEY, and returns updated ui object.
## Similar to charge_marked, but can charge from any input field.
## Optional args are tried as field names, and must be exact matches to input field names.
## If no input field name matches, args are tried with the UI object's mark added in one
## of these ways: Bare fieldname ('first') or Marked fieldname ('CON:first', 'CON_first', or 'first_CON').
## E.g., suppose input has fields SUP:first => 'A', CON:first => 'B' and 'first' => 'C';
## CON->charge_from_input('first'); # stores 'C' in its 'first' field
## CON->charge_from_input('CON:first'); # stores 'B' in its 'first' field
## CON->charge_from_input('SUP:first'); # stores 'A' in its 'SUP:first' field
## SUP->charge_from_input('first'); # stores 'C' in its 'first' field
## SUP->charge_from_input('SUP:first'); # stores 'A' in its 'first' field
## SUP->charge_from_input('CON:first'); # stores 'B' in its 'CON:first' field
sub charge_from_input ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	unless (@_) {
		return %KEY;
	}

	my @flds = ref( $_[0] ) ? @{ $_[0] } : @_;
	my %NEW;
	for my $fld (@flds) {
		exists $KEY{_input}->{$fld}
		  and do { $NEW{$fld} = $KEY{_input}->{$fld}; 1 }
		  or exists $KEY{_input}->{"$KEY{_mark}:$fld"}
		  and do { $NEW{$fld} = $KEY{_input}->{"$KEY{_mark}:$fld"}; 1 }
		  or exists $KEY{_input}->{"$KEY{_mark}_$fld"}
		  and do { $NEW{$fld} = $KEY{_input}->{"$KEY{_mark}_$fld"}; 1 }
		  or exists $KEY{_input}->{"${fld}_$KEY{_mark}"}
		  and do { $NEW{$fld} = $KEY{_input}->{"${fld}_$KEY{_mark}"}; 1 };
	}

	%KEY = ( %KEY, %NEW );

	return $obj;
}

## Charge_resolve. Safely adds resolved data to fields in %KEY, and returns updated ui object.
## See resolve(). Data is resolved by atomic substitutions of the UI object's data in %KEY,
## including any meta-data. Substitutions are made using the resolve() method, which
## defaults to using _start => '[', _end => ']', _mark => ':', as in, e.g.,
## $obj->charge_resolve('settings_file' => '[:system_dir]/settings.config');
sub charge_resolve ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %NEW;
	{
		local $_ = ref( $_[0] );
		/HASH/ and %NEW = %{ $_[0] }
		  or /ARRAY/ and %NEW = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' )
		  : @{ $_[0] }
		  or /CODE/ and %NEW = %{ $_[0]->() }
		  or %NEW =
		  @_ % 2
		  ? ( @_, '' )
		  : @_
	}

	%NEW = map { $_ => resolve( \*KEY, $NEW{$_} ) } keys %NEW;

	%KEY = ( %KEY, %NEW );

	return $obj;
}

## Charge_add. Safely adds numerical data to fields in %KEY, and returns updated ui object.
## In mixed alpha-numerical strings, operates on the last (right-most) digits found.
## An input value may be any expression that resolves to a number (integer or float).
## Does nothing if an input value is not a number. Starts with zero value.
sub charge_add {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %ADD;
	return %KEY unless @_;

	my $i = ref( $_[0] );
	$i =~ /HASH/ and %ADD = %{ $_[0] }
	  or $i =~ /ARRAY/
	  and %ADD = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' ) : @{ $_[0] }
	  or $i =~ /CODE/ and %ADD = %{ $_[0]->() }
	  or %ADD = @_ % 2 ? ( @_, '' ) : @_;

	for my $key ( keys %ADD ) {
		next unless $ADD{$key} =~ /^[+-]?\d+(\.\d*)?$/;
		$KEY{$key} ||= 0;
		$KEY{$key} =~ s{^ (.*?)? ([+-]?\d+(?:\.\d*)?|) ([^\d]+)? $}
						{($1 || '') . ($2||0) + $ADD{$key} . ($3 || '')}ex;
	}

	return $obj;
}

## Charge_append. Safely appends data to fields in %KEY, and returns updated ui object.
## Note that NO white space or other separator is inserted between the original and appended values.
sub charge_append {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %ADD;
	return %KEY unless @_;

	my $i = ref( $_[0] );
	$i =~ /HASH/ and %ADD = %{ $_[0] }
	  or $i =~ /ARRAY/
	  and %ADD = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' ) : @{ $_[0] }
	  or $i =~ /CODE/ and %ADD = %{ $_[0]->() }
	  or %ADD = @_ % 2 ? ( @_, '' ) : @_;

	for my $key ( keys %ADD ) {
		$KEY{$key} .= $ADD{$key};
	}

	return $obj;
}

## Charge_prepend. Safely prepends data to fields in %KEY, and returns updated ui object.
## Note that NO white space or other separator is inserted between the original and prepended values.
sub charge_prepend {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %ADD;
	return %KEY unless @_;

	my $i = ref( $_[0] );
	$i =~ /HASH/ and %ADD = %{ $_[0] }
	  or $i =~ /ARRAY/
	  and %ADD = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' ) : @{ $_[0] }
	  or $i =~ /CODE/ and %ADD = %{ $_[0]->() }
	  or %ADD = @_ % 2 ? ( @_, '' ) : @_;

	for my $key ( keys %ADD ) {
		$KEY{$key} = $ADD{$key} . $KEY{$key};
	}

	return $obj;
}

## Charge_push. Safely appends data to fields in %KEY, and returns updated ui object.
## Data is appended to fields as an element pushed onto an anonymous array;
## the value of the field is a reference to that array. Any value in the field
## before charge_push becomes the first element of the anonymous array.
sub charge_push {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %ADD;
	return %KEY unless @_;

	my $i = ref( $_[0] );
	$i =~ /HASH/ and %ADD = %{ $_[0] }
	  or $i =~ /ARRAY/
	  and %ADD = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' ) : @{ $_[0] }
	  or $i =~ /CODE/ and %ADD = %{ $_[0]->() }
	  or %ADD = @_ % 2 ? ( @_, '' ) : @_;

	for my $key ( keys %ADD ) {
		if ( ref( $KEY{$key} ) =~ /ARRAY/i ) {
			push @{ $KEY{$key} } => $ADD{$key};
		}
		elsif ( defined $KEY{$key} ) {
			$KEY{$key} = [ $KEY{$key}, $ADD{$key} ];
		}
		else {
			$KEY{$key} = [ $ADD{$key} ];
		}
	}

	return $obj;
}

## Charge_fh. Safely writes data to fields in %KEY,
## treating the fields as filehandles, and returns updated ui object.
## The first time a field is charged with charge_fh,
## a filehandle is opened on a reference to any string in the field.
## The filehandle is stored in a field named for the target field
## with '-fh' appended to the field name.
## The new charge value is printed to the filehandle, followed by
## a newline. This updates the string value in the target field.
## The filehandle is opened for read & append (+>>), and is left open
##  until explicitly closed or when the UI object is destroyed.
sub charge_fh {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %ADD;
	return %KEY unless @_;

	my $i = ref( $_[0] );
	if ($i =~ /HASH/) {
		%ADD = %{ $_[0] };
	} elsif ($i =~ /ARRAY/) {
		%ADD = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' ) : @{ $_[0] };
	} elsif ($i =~ /CODE/) {
		%ADD = %{ $_[0]->() };
	} else {
		%ADD = @_ % 2 ? ( @_, '' ) : @_;
	}
	
	for my $key ( keys %ADD ) {
		my $ref_key = qq/$key-fh/;
		if ( $KEY{$ref_key} and ref( $KEY{$ref_key} ) eq 'IO' ) {
			my $fh = $KEY{$ref_key};
			print $fh $ADD{$key}, "\n";
		}
		else {
			open my $fh, "+>>:encoding(UTF8)", \$KEY{$key} || '';
			$fh->autoflush();
			print $fh $ADD{$key}, "\n";
			$KEY{$ref_key} = $fh;
		}
	}
	return $obj;
}

sub charge_fh_gzip {
	my $obj = shift;

	local *KEY = $obj->invert();

	my %ADD;
	return %KEY unless @_;

	my $i = ref( $_[0] );
	$i =~ /HASH/ and %ADD = %{ $_[0] }
	  or $i =~ /ARRAY/
	  and %ADD = @{ $_[0] } % 2 ? ( @{ $_[0] }, '' ) : @{ $_[0] }
	  or $i =~ /CODE/ and %ADD = %{ $_[0]->() }
	  or %ADD = @_ % 2 ? ( @_, '' ) : @_;

	for my $key ( keys %ADD ) {
		my $ref_key = qq/$key-fh/;
		if ( $KEY{$ref_key} and ref( $KEY{$ref_key} ) eq 'IO' ) {
			my $fh = $KEY{$ref_key};
			print $fh $ADD{$key}, "\n";
		}
		else {
			open my $fh, "+>>:gzip", \$KEY{$key} || '';
			print $fh $ADD{$key}, "\n";
			$KEY{$ref_key} = $fh;
		}
	}

	return $obj;
}

## Clear: safely deletes data from %KEY, and returns updated ui object.
## Args are tried as fieldnames; if not present, the field will be added.
## If no args, all non-meta fields are cleared,
## EXCEPT the field named for the object's mark ($KEY{_mark}),
## which holds marked input data.
## Fields whose data is deleted receive the value ''.
## Meta_data (fieldnames starting with '_') is not deleted.
sub clear ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	if (@_) {
		$KEY{$_} = '' for grep { !/^_/ } @_;
	}
	else {
		%KEY = map {
			( /^_/ or $_ eq $KEY{_mark} ) ? ( $_ => $KEY{$_} ) : ( $_ => '' )
		} keys %KEY;
	}

	return $obj;
}

## Clear_undef: safely deletes data from %KEY, and returns updated ui object.
## Args are tried as fieldnames; if not present, the field will be added.
## If no args, all non-meta fields are cleared,
## EXCEPT the field named for the object's mark ($KEY{_mark}),
## which holds marked input data.
## Fields whose data is deleted receive the value undef.
## Meta_data (fieldnames starting with '_') is not deleted.
sub clear_undef ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	if (@_) {
		$KEY{$_} = '' for grep { !/^_/ } @_;
	}
	else {
		%KEY = map {
			( /^_/ or $_ eq $KEY{_mark} )
			  ? ( $_ => $KEY{$_} )
			  : ( $_ => undef )
		} keys %KEY;
	}

	return $obj;
}

## Clear_data, clear_input, clear_marked_input
## Similar to clear(), but REMOVES THE FIELD AS WELL AS THE DATA
## If no args, ALL non-meta fields are deleted,
## EXCEPT the field named for the object's mark ($KEY{_mark}),
## which holds marked input data.
## Meta_data (fieldnames starting with '_') is not deleted.
sub clear_data ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	if (@_) {
		delete $KEY{$_} for grep { !/^_/ } @_;
	}
	else {
		%KEY =
		  map { ( /^_/ or $_ eq $KEY{_mark} ) ? ( $_ => $KEY{$_} ) : () }
		  keys %KEY;
	}

	return $obj;
}

## Removes selected or all input fields & their values
sub clear_input ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	$KEY{_input}->{$_} = '' for @_ ? @_ : keys %{ $KEY{_input} };
	delete $KEY{_vals}->{$_} for @_ ? @_ : keys %{ $KEY{_vals} };

	return $obj;
}

## Removes selected or all marked input fields & their values
sub clear_marked_input ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	delete $KEY{_vals}->{$_} for @_ ? @_ : keys %{ $KEY{_vals} };

	return $obj;
}

## Instrospection
## Call spill on a method to set its results and a B::Deparse view of its source code.
## The first required argument after the invocant is the name of the sub;
## the method name should be fully qualified if not in the current namespace.
## Any additonal arguments are passed to the named method;
## The output is a dump of: the name of the method, its inputs & output, and its source code.
sub spill ($$;@) {
	my $obj	= shift;

	local *KEY = $obj->invert();

	my $sub	= shift;

	$sub	= defined &{ 'main::' . $sub } ?
		'main::' . $sub
			: defined &{ $sub } ?
			$sub
				: sub { 'No defined method specified to spill.' };
	require B::Deparse;
	my $deparse = B::Deparse->new("-sC");
	my $source	= $deparse->coderef2text( \&{ $sub } );
	my $theSub	= \&{ $sub };
	my $output	= [ $obj->$theSub(@_) ];
	my $input	= [ @_ ];
	$obj->oh(
		{
			input		=> $input,
			output		=> $output,
			process		=> $source
		},
		$sub
 	);
}

## Data Access
sub list_keys ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	grep { !/^_/ } keys %KEY;
}

sub list_values ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	map { $KEY{$_} } grep { !/^_/ } keys %KEY;
}

sub list_pairs ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	map { "$_:  $KEY{$_}" } grep { !/^_/ } keys %KEY;
}

sub list_meta_keys ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	grep { /^_/ } keys %KEY;
}

sub list_meta_values ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	map { $KEY{$_} } grep { /^_/ } keys %KEY;
}

sub list_meta_pairs ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	map { "$_:  $KEY{$_}" } grep { /^_/ } keys %KEY;
}

sub data ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	wantarray ? map { $KEY{$_} || '' } @_ : $KEY{ $_[0] } || '';
}

sub fh_data ($;@) {
	my $obj = shift;
	local *KEY = $obj->invert();
	
	my $fld	= shift || '';
	return unless $fld;
	
	my $ref_key = qq/$fld-fh/;
 	return unless ( $KEY{$ref_key} );
	my $fh 		= $KEY{$ref_key};
	my $oldtell	= tell $fh;
	seek $fh, 0,0;
	my @lines = <$fh>;
	seek $fh, $oldtell, 0;
	wantarray ? @lines : join '' => @lines;
}

sub untainted_data ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

# 	wantarray ? map { $KEY{$_} =~ /^([^`]+)$/ ? $1 : '' } @_ : $KEY{$_[0]} =~ /^([^`]+)$/ ? $1 : ''
	wantarray ? map { $KEY{$_} =~ /\A([^`]+)\z/ ? $1 : '' } @_
	  : $KEY{ $_[0] } =~ /\A([^`]+)\z/ ? $1
	  :                                  '';
}

sub pairs ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	map { $_ => ( $KEY{$_} || '' ) } grep { !/^_/ } @_ ? @_ : keys %KEY;
}

sub meta_pairs ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	map { $_ => $KEY{$_} } grep { /^_/ } @_ ? @_ : keys %KEY;
}

sub input_data ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	wantarray ? map { $KEY{_input}->{$_} || '' } @_ : $KEY{_input}->{ $_[0] }
	  || '';
}

sub input_keys ($) {
	my $obj = shift;

	local *KEY = $obj->invert();

	return keys %{ $KEY{_input} };
}

sub input_pairs ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	map { $_ => ( $KEY{_input}->{$_} || '' ) } keys %{ $KEY{_input} };
}

sub marked_input_data ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	wantarray ? map { $KEY{_vals}->{$_} || '' }
	  @_ : ( $_[0] ? $KEY{_vals}->{ $_[0] } || '' : '' );
}

sub marked_input_keys ($) {
	my $obj = shift;

	local *KEY = $obj->invert();

	return keys %{ $KEY{_vals} || () };
}

sub marked_input_pairs ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	@_
	  ? map { $_ => ( defined $KEY{_vals}->{$_} ? $KEY{_vals}->{$_} : '' ) }
	  @_
	  : %{ $KEY{_vals} || {} };
}

sub input ($) {
	my $obj = shift;

	local *KEY = $obj->invert();

	$KEY{_input};
}

sub marked_input ($) {
	my $obj = shift;

	local *KEY = $obj->invert();

	$KEY{_vals};
}

sub uploads ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	$KEY{_uploads} || {};
}

sub num_uploads ($;@) {
	my $obj = shift;

	local *KEY = $obj->invert();

	$KEY{_input}->{_num_uploads} || 0;
}

sub uploads_by_field {
	my $obj = shift;

	local *KEY = $obj->invert();

	my @flds = @_ ? @_ : keys %{ $KEY{_uploads} };
	my @uploads =
	  map { defined $KEY{_uploads}->{$_} ? $KEY{_uploads}->{$_} : () } @flds;
	return wantarray ? @uploads : $uploads[0];
}

sub request ($) {
	my $obj = shift;

	local *KEY = $obj->invert();

	$KEY{_request};
}

##################

# Load system messages and warnings
sub get_messages {
	my ( $arg1, $msg_file ) = @_;
	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};
	local $/ = '';
	$msg_file ||= $KEY{_message_file};

	$KEY{_messages} ||= {};
	my %file_messages;
	open my $msgs, "<", "$msg_file" or return $KEY{_messages};
	while ( my $msg = <$msgs> ) {
		next if $msg =~ /^\s*#/;
		if ( $msg =~ /^([^\n]*)\n(.*)\n+$/s ) {
			my ( $msg_name, $msg ) = ( $1, $2 );
			$msg =~ s/(^\s*|\s*$)//g;
			$file_messages{$msg_name} = $msg;
		}
	}
	close $msgs;

	$KEY{_messages} = { ( %{ $KEY{_messages} }, %file_messages ) };
}

# List system messages and warnings
# Does NOT load messages or warnings
sub list_messages {
	my ( $arg1, $msg_file ) = @_;
	local *KEY = ref($arg1) eq __PACKAGE__ ? $arg1 : *{$arg1};
	local $/ = '';
	$msg_file ||= $KEY{_message_file};

	$KEY{_message_list} = [];
	my %msgs_found;
	open my $msgs, "<", "$msg_file" or return $KEY{_messages};
	for (
		grep { !$msgs_found{$_}++ } sort keys %{ $KEY{_messages} },
		map { /^\s*#/ ? () : /^([^\n]*)\n.*/s ? $1 : () } <$msgs>
	  )
	{
		push @{ $KEY{_message_list} } => $_;
	}
	close $msgs;
	$KEY{_message_list};
}

# Load lists for popups etc
# returns hash of array refs
sub get_lists {
	my $obj = shift;
	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	my $list_file = shift || $KEY{_list_file} || '';
	my $list_dir = $KEY{_list_dir} || '';
	$list_dir = $list_dir eq "./" ? "./lists" : $list_dir;
	unless ( -d $list_dir ) {
		mkdir( $list_dir, oct(777) )
		  or carp "List dir creation failed for $list_dir: $!";
	}
  GET: {
		return $KEY{_lists} unless open my $LISTS, "<", "$list_file";
		local $/ = '';
	  LIST: while ( my $list = <$LISTS> ) {
			my @items = split "\n" => $list;
			my @list = map { defined && /\A\s*([^`]+)\s*\z/ ? $1 : () } @items;
			my $list_name = shift @list;
			next LIST unless $list_name =~ s/^\s*([a-zA-Z0-9_][^\n]+)\s*$/$1/;
			$KEY{_lists}->{$list_name} = [@list];
			$KEY{_listed}->{$list_name} = { map { $_ => 1 } @list };
			if ( open my $lfh, ">:encoding(UTF8)", "$list_dir/$list_name" ) {
				print $lfh join "\n" => @list, '';
				close $lfh;
			}
			else {
				$obj->oops("Can't save list file $list_name: $!\n");
			}
		}
		close $LISTS;
	}
	$KEY{_lists};
}

sub load_lists {
	my $obj = shift;
	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	my $list_dir = $KEY{_list_dir} || '';
	$list_dir = $list_dir eq "./" ? "./lists" : $list_dir;
	return $KEY{_lists} unless ( -d $list_dir );

	for my $file ( glob "$list_dir/*" ) {
		my $list_name = $file;
		$list_name =~ s{^.*\/(.*)$} {$1};
		next unless open my $lfh, "<", $file;
		my @items = <$lfh>;
		close $lfh;
		chomp @items;
		my @list = map { defined && /\A\s*([^`]+)\s*\z/ ? $1 : () } @items;
		$KEY{_lists}->{$list_name} = [@list];
		$KEY{_listed}->{$list_name} = { map { $_ => 1 } @list };
	}
	$KEY{_lists};
}

sub get_lists_old {
	my $obj = shift;
	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	my $list_file = shift || $KEY{_list_file} || '';
  GET: {
		local $/ = '';
		open LISTS, "<", "$list_file"
		  or $obj->oops("Can't open list file $list_file: $!\n");
		while (<LISTS>) {
			my ( $fld, $list ) = split "\n" => $_, 2;
			my @items = split "\n" => $list;
			$KEY{_lists}->{$fld} = [@items];
			$KEY{_listed}->{$fld} = { map { $_ => 1 } @items };
		}
		close LISTS;
	}
	$KEY{_lists};
}

sub get_system_lists {
	my $obj = shift;
	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	my $list_file = shift || $KEY{_list_file} || '';
	my %sys_lists;
  GET: {
		return {} unless open my $LISTS, "<", "$list_file";
		local $/ = '';
		while (<$LISTS>) {
			my ( $list_name, $list ) = split "\n" => $_, 2;
# 			next unless $list_name =~ s/^\s*([a-zA-Z0-9_][^\n]+)\s*$/$1/;
			next unless $list_name =~ s/^\s*(\w[^\n]+)\s*$/$1/;
# 			my @items = split "\n" => $list;
			my @items = split /\n/ => $list;
			@items = map { defined && /\A\s*([^`]+)\s*\z/ ? $1 : () } @items;
			$sys_lists{$list_name} = [@items];
		}
		close $LISTS;
	}
	wantarray ? %sys_lists : {%sys_lists};
}

sub load_system_lists {
	my $obj = shift;
	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	my $list_file = shift || $KEY{_list_file} || '';
	my %sys_lists;
  GET: {
		return {} unless open my $LISTS, "<", "$list_file";
		local $/ = '';
		while (<$LISTS>) {
			my ( $list_name, $list ) = split "\n" => $_, 2;
# 			next unless $list_name =~ s/^\s*([a-zA-Z0-9_][^\n]+)\s*$/$1/;
			next unless $list_name =~ s/^\s*(\w[^\n]+)\s*$/$1/;
# 			my @items = split "\n" => $list;
			my @items = split /\n/ => $list;
			@items = map { defined && /\A\s*([^`]+)\s*\z/ ? $1 : () } @items;
			$sys_lists{$list_name} = [@items];
			$KEY{_lists}->{$list_name} = [@items];
			$KEY{_listed}->{$list_name} = { map { $_ => 1 } @items };
		}
		close $LISTS;
	}
	wantarray ? %sys_lists : {%sys_lists};
}

# Listed: Allows checking whether an item appears in a list;
# First optional argument is a list name; additional
# optional args are items to check the named list for.
#
# If one item is provided, returns "true" if the item is in the
# named list and "false" if not; if more than one item, returns
# a list of true/false for each item.
# If no items are provided, returns a boolean lookup hashref
# with the named list's items as keys and "true" as their values.
# Returns false if the named list doesn't exist;
# If no list name is provided, returns a hash ref with all lists
# as keys and each list's boolean lookup as their values;
sub listed ($;@) {
	my $obj = shift;
	local *KEY = ref($obj) eq __PACKAGE__ ? $obj : *{$obj};

	if (@_) {
		my $fld = shift;
		return unless exists $KEY{_listed}->{$fld};
		if (@_) {
			my @items = @_;
			if ( @items > 1 ) {
				return map { $KEY{_listed}->{$fld}->{$_} || 0 } @items;
			}
			else {
				return $KEY{_listed}->{$fld}->{ $items[0] } || 0;
			}
		}
		else {
			return $KEY{_listed}->{$fld} || {};
		}
	}
	else {
		return $KEY{_listed};
	}
}

# Optional display management

# Make list of all available templates by reading display directory globbing on '*.tmpl'
sub get_templates {
	my $self = shift;
	ref($self) eq __PACKAGE__ or unshift @_, $self;

	my $display_dir = shift;
	-d $display_dir or return '_NODIR_';    # ??
	my $displays_only = shift;
	my %templates;
	for my $file ( glob "$display_dir/*.tmpl" ) {
		my $name = $file;
# 		$name =~ s{^.*\/(.*)\.tmpl$} {$1};
		$name =~ s{^ .* / (.*) [.] tmpl $} {$1}x;
		$templates{$name}->{name} = $name;
		$templates{$name}->{file} = $file;

		if ( $templates{$name}->{file} =~ /_NOFILE_/ ) {
			$templates{$name}->{display} = '_NA_';
		}
		elsif ( open D, "<", $templates{$name}->{file} ) {
			local $/ = undef;
			$templates{$name}->{display} = <D>;
			close D;
		}
		else {
			$templates{$name}->{display} = '_NA_';
		}

# 		$templates{$name}->{display}	= do {
# 			if ($templates{$name}->{file} =~ /_NOFILE_/) {
# 				'_NA_'
# 			} else {
# 				local $/;
# 				unless ( open D, "<", $templates{$name}->{file} ) {
# 					'_NA_'
# 				} else {
# 					<D>
# 				}
# 			}
# 		};

		$templates{$name}->{reveal} = do {
			my $tmpl = "\n" . $templates{$name}->{display};
			$tmpl =~ s/(&)([^a])/&amp;$2/g;
			$tmpl =~ s/>/&gt;/g;
			$tmpl =~ s/</&lt;/g;
			$tmpl =~ s/\n/<br>\n/g;
			$tmpl;
		};
	}
	return ( map { $_ => $templates{$_}->{display} } keys %templates )
	  if $displays_only;
	%templates;
}

## Make list of designated display templates from a database in the
## designated directory, checking directory to verify templates
sub get_displays {
	my $self = shift;
	ref($self) eq __PACKAGE__ or unshift @_, $self;

	my $display_dir = shift;
	my $display_db = shift || 'displays_db.txt';
	-d $display_dir or return '_NODIR_';
	-e "$display_dir/$display_db" or return '_NODB_';

	# Connect to the database
	require BVA::KALE::DATA;
	my $displays =
	     BVA::KALE::DATA->init->connect( file => "$display_dir/$display_db" )
	  or carp "Couldn't connect to display DB: \n!";

	#header:name|tmpl|type|note
	#labels:Display Name|Template|Type|Note
	#formats:t:18|t:30|t:6|a:20.6
	my $all_displays_query = $displays->prepare(qq{SELECT * WHERE all});
	$all_displays_query->execute();

	my %display_data;

	while ( my $r = $all_displays_query->fetchrow_hashref() ) {
		$display_data{ $r->{name} } = { name => $r->{tmpl}, };
	}

	for ( keys %display_data ) {
		my $fname = $display_data{$_}->{name} . '.tmpl';
		$display_data{$_}->{file} =
		  -e "$display_dir/$fname"
		  ? "$display_dir/$fname"
		  : '_NOFILE_';

		if ( $display_data{$_}->{file} =~ /_NOFILE_/ ) {
			$display_data{$_}->{display} = '_NA_';
		}
		elsif ( open D, "<", $display_data{$_}->{file} ) {
			local $/ = undef;
			$display_data{$_}->{display} = <D>;
			close D;
		}
		else {
			$display_data{$_}->{display} = '_NA_';
		}

		# 		$display_data{$_}->{display}	= do {
		# 											if ($display_data{$_}->{file} =~ /_NOFILE_/) {
		# 												'_NA_'
		# 											} else {
		# 												local $/;
		# 												unless ( open D, "<", $display_data{$_}->{file} ) {
		# 													'_NA_'
		# 												} else {
		# 												 	<D>
		# 												}
		# 											}
		# 										};
		#next unless $display_data{$_}->{display};
		$display_data{$_}->{reveal} = do {
			my $tmpl = "\n" . $display_data{$_}->{display};
			$tmpl =~ s/(&)([^a])/&amp;$2/g;
			$tmpl =~ s/>/&gt;/g;
			$tmpl =~ s/</&lt;/g;
			$tmpl =~ s/\n/<br>\n/g;
			$tmpl;
		};
	}
	%display_data;
}

sub add_display {
	my $new_display  = shift;
	my $display_dir  = shift;
	my $display_note = shift || '';
	my $display_db   = shift || 'displays_db.txt';
	-d $display_dir or oops('_NODIR_');
	-e "$display_dir/$display_db" or return '_NODB_';

	# Connect to the database
	require BVA::KALE::DATA;
	my $displays =
	  BVA::KALE::DATA->init->connect( file => "$display_dir/$display_db" );

	#header:name|tmpl|type|note
	#labels:Display Name|Template|Type|Note
	#formats:t:18|t:30|t:6|a:20.6

	my $all_displays_query =
	  $displays->prepare(qq{ SELECT name FROM me WHERE all TO cursor: hash });

	$all_displays_query->execute();
	while ( my $r = $all_displays_query->fetchrow_hashref() ) {
		if ( $r->{name} eq $new_display ) {
			oops(
qq{Display \"$new_display\" already exists.<br>\nPlease choose a different name.}
			);
		}
	}

	my $insert = $displays->prepare(
qq{ INSERT INTO me VALUES name=>$new_display;note=>$display_note WITH id_override: 1 }
	);

	return $insert->execute;
}

## Interactive output

## reset_header	-- enables emission of a new header
##				-- for secondary output
sub reset_header {
	my $self = shift();
# 	my $ui   = $self->object( $self->data('_ui_mark') );
	my $ui   = $self->object();
	$ui->charge_meta( _hdr_prntd => 0 );

	1;
}

sub header_status {
	my ( $self, $status ) = @_;
# 	my $ui = $self->object( $self->data('_ui_mark') );
	my $ui = $self->object();
	if ( $status and $status =~ /^\s*([a-zA-Z0-9]+)\s*$/ ) {
		my $hdr_status = $1;
		$ui->charge_meta( _hdr_prntd => $hdr_status );
	}
	return $ui->data('_hdr_prntd');
}

sub ask ($;@) {
	my $arg1 = shift;
	ref($arg1) eq __PACKAGE__ or unshift @_, $arg1;
	my $text  = shift() || $arg1->process("MSG") || '';
	my $title = shift() || 'Info, please:';
	my $env   = shift() || $arg1->data('_env') || 'htm';
	my $state = shift() || $arg1->data('state') || $arg1->input_data('state');
	my $hid_vals  = shift() || '';
	my $mark      = $arg1->data('_mark');
	my $style     = $arg1->process("STYLESHEET") || '';
	my $cgi       = $arg1->data('cgi') || $ENV{SCRIPT_NAME};
	my $path_info = $arg1->input_data('_path_info');
	$path_info = $path_info ? "/$path_info" : "";
	my $ask_act = $arg1->data('_ask_act') || $arg1->data('action') || "OK";
	my $return =
	  $arg1->data('return_to') || $arg1->marked_input_data("return_to");
	my $header = $arg1->process("RES_HDR=${env}");
	my $ask    = '';

	if ( $env eq 'htm' ) {
		$ask = <<HT_ASK;
$header

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta http-equiv="x-ua-compatible"	content="ie=edge" />
    <meta name="viewport"               content="width=device-width, initial-scale=1" />
	$style
	<title>$title</title>
</head>
<body style="background-color:"#CCFFCC;" onLoad="
	var e=document.forms[0].elements;
	for (n=0; n!=e.length+1; n++) {
		if (e[n]!=null) {
			if (e[n].type=='text' || e[n].type=='textarea') {
				e[n].focus(); break;
			}
		}
	}
">

<div style="text-align:center;margin-left:auto;margin-right:auto;max-width:40em;">
<form action="$cgi$path_info" method="POST" enctype="application/x-www-form-urlencoded" name="ask">
	<div style="background-color:#CCCC99;margin-left:auto;margin-right:auto;">
<h3>$title</h3>
	</div>
	<div style="background-color:#FFFFCC;margin-left:auto;margin-right:auto;height:60vh;">
$text
	<div>
	<div style="background-color:#CCCC99;margin-left:auto;margin-right:auto;">
<input type="submit" name="action" value="$ask_act"> &nbsp;
<input type="submit" name="action" value="Cancel">

<input type="hidden" name="state" value="$state">
<input type="hidden" name="$mark:return_to" value="$return">
$hid_vals
	</div>
</form>
</div>

</body>
</html>

HT_ASK
	}
	elsif ( $env eq 'xhr' ) {
		$ask = <<XHR_ASK;
$header

<p>XHR</p>
<div style="text-align:center;margin-left:auto;margin-right:auto;">
<form action="$cgi$path_info" method="POST" enctype="application/x-www-form-urlencoded" name="ask">
	<div style="background-color:#CCCC99;margin-left:auto;margin-right:auto;">
<h3>$title</h3>
	</div>
	<div style="background-color:#FFFFCC;margin-left:auto;margin-right:auto;height:60vh;">
$text
	<div>
	<div style="background-color:#CCCC99;margin-left:auto;margin-right:auto;">
<input type="submit" name="action" value="$ask_act"> &nbsp;
<input type="submit" name="action" value="Cancel">

<input type="hidden" name="state" value="$state">
<input type="hidden" name="$mark:return_to" value="$return">
$hid_vals
	</div>
</form>
</div>

XHR_ASK
	}
	else {
		$ask = <<EDIT_ASK;
$title
$text

EDIT_ASK
	}

	print $ask;
	exit;
}

sub holdit ($;@) {
	my $arg1 = shift;
	ref($arg1) eq __PACKAGE__ or unshift @_, $arg1;
	my $text      = shift();
	my $title     = shift() || 'Please Wait:';
	my $mark      = $arg1->data('_mark');
	my $pause     = shift() || 0;
	my $next      = shift() || '';
	my $ask_act   = shift() || $arg1->data('_ask_act') || "OK";
	my $state     = shift() || $arg1->data('state');
	my $actor     = shift() || $arg1->data('actor');
	my $env       = shift() || $arg1->data('_env') || 'htm';
	my $cgi       = $arg1->data('cgi');
	my $path_info = $arg1->input_data('_path_info');
	$path_info = $path_info ? "/$path_info" : "";
	my $header = $arg1->process("RES_HDR=${env}");

	my $ask = $env eq 'htm' ? <<HT_ASK : <<EDIT_ASK;
$header

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"
        "http://www.w3.org/TR/html4/strict.dtd">

<html lang="en">
<head>
	<title>$title</title>
	<meta http-equiv="Refresh" content="$pause; URL=$next">
</head>
<body bgcolor="#CCFFCC">

<div align="center">

<form action="$cgi$path_info" method="POST" enctype="application/x-www-form-urlencoded" name="ask">

<h2>$title</h2>

$text

<input type="submit" name="action" value="$ask_act"> &nbsp;
<input type="submit" name="action" value="Cancel">
<input type="hidden" name="state" value="$state">
<input type="hidden" name="actor" value="$actor">
<input type="hidden" name="OK" value="1">

</form>
</div>

</body>
</html>

HT_ASK
$title
$text

EDIT_ASK

	print $ask;
	exit;
}

sub oops ($;@) {
	my $self = shift();
	local *KEY = $self->invert();    # invert($self);
	my $text   = shift();
	my $title  = shift() || 'Oops!';
	my $mark   = $self->data('_mark');
	my $env    = shift() || 'htm';
	my $header = $self->process("RES_HDR=${env}");

	my $oops = $env eq 'htm' ? <<HT_OOPS : <<EDIT_OOPS;
$header

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"
        "http://www.w3.org/TR/html4/strict.dtd">

<html lang="en">
<head>
	<title>$title</title>
</head>
<body bgcolor="#CCFFCC">
<div align="center">
	<table cellpadding="18" cellspacing="1">
		<tr>
			<th bgcolor="#CCCCFF">
				<h2>$title ($env)</h2>
			</th>
		</tr>
		<tr>
			<td bgcolor="#FFFFCC">
				$text
			</td>
		</tr>
	</table>
</div>
</body>
</html>

HT_OOPS
$title ($env)
$text

EDIT_OOPS

	print $oops;
	exit;
}

sub hey ($;@) {
	my $self = shift();
	local *KEY = $self->invert();    # invert($self);
	my $ref   = shift()    || ( $KEY{_mark} eq $KEY{_ui_mark} ? \%KEY : \*KEY );
	my $env   = $KEY{_env} || 'htm';
	my $title = shift()    || 'Hey!';
	my $pure  = shift();
	my $output = '';

	if ( ref($ref) ) {
		local $Data::Dumper::Purity   = length($pure) ? $pure : 1;
		local $Data::Dumper::Deparse  = 1;
		local $Data::Dumper::Sortkeys = 1;
		eval { $output = Dumper($ref); 1 }
		  or do { $output .= "\nDumper problem: \n$@"; };
		$output = $self->HTML_entify($output) if $env eq 'htm';
	}
	else {
		$output = $ref;
	}
	$output ||= "Oh, never mind.";

	my $header = $self->process("RES_HDR=${env}");

	my $hey =
	  $env eq 'htm' ? <<HT_HEY : $env eq 'term' ? <<EDIT_HEY : <<TERM_HEY;
$header

<!DOCTYPE HTML>

<html lang="en">
<head>
	<title>$title</title>
</head>
<body bgcolor="#FFFFFF">
<div align="center">
	<table cellpadding="8" cellspacing="1" bgcolor="#CCFFCC">
		<tr>
			<th>
				<h2>
$title
				</h2>
			</th>
		</tr>
		<tr>
			<td>
				<pre>
$output
				</pre>
			</td>
		</tr>
	</table>
</div>
</body>
</html>

HT_HEY
$title ($env)
$output

EDIT_HEY
$title ($env)
$output

TERM_HEY

	print $hey;
	exit;
}

sub wut {
	my $self = shift();
	local *KEY = ref($self) eq __PACKAGE__ ? $self : *{$self};
	use B qw(perlstring);

	my $env = $KEY{_env} || 'htm';
	my $ref   = shift() || ( $KEY{_mark} eq $KEY{_ui_mark} ? \%KEY : \*KEY );
	my $title = shift() || 'Oh!';
	my $pure  = shift();
	my $output = '';
	if ( ref($ref) ) {
		local $Data::Dumper::Purity   = length($pure) ? $pure : 1;
		local $Data::Dumper::Deparse  = 1;
		local $Data::Dumper::Sortkeys = 1;

		#no warnings;
		eval { $output = Dumper($ref); 1 }
		  or do { $output .= "\nDumper problem: \n$@"; };
		$output = $self->HTML_entify($output) if $env eq 'htm';
	}
	else {
		$output = $ref;
	}
	my $perl_output	= perlstring($output);
	if ( $env eq 'htm' ) {
		return <<HT;
	<section id="report">
		<pre>
$perl_output
		</pre>
	</section>
HT
	}
	elsif ( $env eq 'psgi' ) {
		return <<HT;
	<section id="report">
		<pre>
$perl_output
		</pre>
	</section>
HT
	}
	elsif ( $env eq 'term' ) {
	return $perl_output;
	}
	else {
	$perl_output =~ s{\\n}{\n}g;
	return $perl_output;
	}


}

sub oh ($;@) {
	my $self = shift();
	local *KEY = ref($self) eq __PACKAGE__ ? $self : *{$self};
	my $env = $KEY{_env} || 'htm';
	my $ref   = shift() || ( $KEY{_mark} eq $KEY{_ui_mark} ? \%KEY : \*KEY );
	my $title = shift() || 'Oh!';
	my $pure  = shift();
	my $output = '';

	if ( ref($ref) ) {
		local $Data::Dumper::Purity   = length($pure) ? $pure : 1;
		local $Data::Dumper::Deparse  = 1;
		local $Data::Dumper::Sortkeys = 1;

		#no warnings;
		eval { $output = Dumper($ref); 1 }
		  or do { $output .= "\nDumper problem: \n$@"; };
		$output = $self->HTML_entify($output) if $env eq 'htm';
	}
	else {
		$output = $ref;
	}
	$output ||= "Oh, never mind.";

	my $obj = $self->direct();
	$obj->charge( title => $title, output => $output );

	if ( $env eq 'htm' ) {
		return $obj->_process_tmpl(<<HT_HEY);
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="utf-8" />
	<meta name="generator" content="Interworks" />
	<title>[:title] ([:_env])</title>
    <style type="text/css">
		article, section, aside, hgroup, nav, header, footer, figure, figcaption {
		  display: block;
		}
		body {
		  background-color:#FFF;
		}
		#page {
		  background-color:#CFC;
		  max-width:60em;
		  margin-left:auto;
		  margin-right:auto;
		}
		header {
		  text-align:center;
		  background-color:#333;
		  color:white;
		  font-family:Arial,sans-serif;
		  font-weight:bold;
		  padding:2em;
		}
		footer{
		  text-align:center;
		  background-color:#EEE;
		  padding:1em;
		}
		#report {
		  text-align:left;
		  padding-left:2em;
		  padding-right:1em;
		  margin-left:6em;
		  margin-right:6em;
		  background-color:#FFC;
		}
	</style>
</head>
<body>
<div id="page">
	<header>
[:title] ([:_env])
	</header>
	<nav>
	</nav>
	<section id="report">
		<pre>
     [:
output
]
		</pre>
	</section>
	<footer>
[:title]
	</footer>
</div>
</body>
</html>

HT_HEY

	}
	elsif ( $env eq 'psgi' ) {
		return $obj->_process_tmpl(<<PSGI_HEY);
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="utf-8" />
	<meta name="generator" content="Interworks" />
	<title>[:title] ([:_env])</title>
    <style type="text/css">
		article, section, aside, hgroup, nav, header, footer, figure, figcaption {
		  display: block;
		}
		body {
		  background-color:#FFF;
		}
		#page {
		  background-color:#CFC;
		  max-width:60em;
		  margin-left:auto;
		  margin-right:auto;
		}
		header {
		  text-align:center;
		  background-color:#333;
		  color:white;
		  font-family:Arial,sans-serif;
		  font-weight:bold;
		  padding:2em;
		}
		footer{
		  text-align:center;
		  background-color:#EEE;
		  padding:1em;
		}
		#report {
		  text-align:left;
		  padding-left:2em;
		  padding-right:1em;
		  margin-left:6em;
		  margin-right:6em;
		  background-color:#FFC;
		}
	</style>
</head>
<body>
<div id="page">
	<header>
[:title] ([:_env])
	</header>
	<nav>
	</nav>
	<section id="report">
		<pre>
     [:
output
]
		</pre>
	</section>
	<footer>
[:title]
	</footer>
</div>
</body>
</html>

PSGI_HEY

	}
	elsif ( $env eq 'term' ) {
		return $obj->_process_tmpl(<<TERM_HEY);
[:title] ([:_env])
[:output]

TERM_HEY

	}
	else {
		return $obj->_process_tmpl(<<EDIT_HEY);
[:title] ([:_env])
[:output]

EDIT_HEY

	}
}

sub oh_data ($;@) {
	my $self = shift();
	local *KEY	= ref($self) eq __PACKAGE__ ? $self : *{$self};
	my $env		= $KEY{_env} || 'htm';
	my $flds	= shift() || [ keys %KEY ];
	my $title	= shift() || 'Oh!';
	my $pure	= shift();

	$flds		= ref($flds) ? $flds : [ split /\s*,\s*/ => $flds ];
	@$flds		= grep { ~! /^_/ } @$flds;
	my $out_ref = { map { $_ => $KEY{$_} } @{ $flds } };

	my $output = '';

	local $Data::Dumper::Purity   = length($pure) ? $pure : 1;
	local $Data::Dumper::Deparse  = 1;
	local $Data::Dumper::Sortkeys = 1;

	#no warnings;
	eval { $output = Dumper($out_ref); 1 }
	  or do { $output .= "\nDumper problem: \n$@"; };
	$output = $self->HTML_entify($output) if $env eq 'htm';

	$output ||= "Oh, never mind.";

	my $obj = $self->direct();
	$obj->charge( title => $title, output => $output );

	if ( $env eq 'htm' ) {
		return $obj->_process_tmpl(<<HT_HEY);
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="utf-8" />
	<meta name="generator" content="Interworks" />
	<title>[:title] ([:_env])</title>
    <style type="text/css">
		article, section, aside, hgroup, nav, header, footer, figure, figcaption {
		  display: block;
		}
		body {
		  background-color:#FFF;
		}
		#page {
		  background-color:#CFC;
		  max-width:60em;
		  margin-left:auto;
		  margin-right:auto;
		}
		header {
		  text-align:center;
		  background-color:#333;
		  color:white;
		  font-family:Arial,sans-serif;
		  font-weight:bold;
		  padding:2em;
		}
		footer{
		  text-align:center;
		  background-color:#EEE;
		  padding:1em;
		}
		#report {
		  text-align:left;
		  padding-left:2em;
		  padding-right:1em;
		  margin-left:6em;
		  margin-right:6em;
		  background-color:#FFC;
		}
	</style>
</head>
<body>
<div id="page">
	<header>
[:title] ([:_env])
	</header>
	<nav>
	</nav>
	<section id="report">
		<pre>
     [:
output
]
		</pre>
	</section>
	<footer>
[:title]
	</footer>
</div>
</body>
</html>

HT_HEY

	}
	elsif ( $env eq 'psgi' ) {
		return $obj->_process_tmpl(<<PSGI_HEY);
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="utf-8" />
	<meta name="generator" content="Interworks" />
	<title>[:title] ([:_env])</title>
    <style type="text/css">
		article, section, aside, hgroup, nav, header, footer, figure, figcaption {
		  display: block;
		}
		body {
		  background-color:#FFF;
		}
		#page {
		  background-color:#CFC;
		  max-width:60em;
		  margin-left:auto;
		  margin-right:auto;
		}
		header {
		  text-align:center;
		  background-color:#333;
		  color:white;
		  font-family:Arial,sans-serif;
		  font-weight:bold;
		  padding:2em;
		}
		footer{
		  text-align:center;
		  background-color:#EEE;
		  padding:1em;
		}
		#report {
		  text-align:left;
		  padding-left:2em;
		  padding-right:1em;
		  margin-left:6em;
		  margin-right:6em;
		  background-color:#FFC;
		}
	</style>
</head>
<body>
<div id="page">
	<header>
[:title] ([:_env])
	</header>
	<nav>
	</nav>
	<section id="report">
		<pre>
     [:
output
]
		</pre>
	</section>
	<footer>
[:title]
	</footer>
</div>
</body>
</html>

PSGI_HEY

	}
	elsif ( $env eq 'term' ) {
		return $obj->_process_tmpl(<<TERM_HEY);
[:title] ([:_env])
[:output]

TERM_HEY

	}
	else {
		return $obj->_process_tmpl(<<EDIT_HEY);
[:title] ([:_env])
[:output]

EDIT_HEY

	}
}

sub reveal ($;@) {
	my $self = shift();
	local *KEY =
	  $self->invert();    #ref($self) eq __PACKAGE__ ? $self : *{ $self };

	my $tmpl =
	     join( '' => @_ )
	  || $KEY
	  || $KEY{_default_tmpl};
	my $output = ' ';

	my @objects = objects(*KEY);

  LOAD: {
		foreach my $obj (@objects) {
			$obj->charge_auto();
			$obj->calculate();
		}
	}

	## Temporarily disable header block
	my $temp_hdr_status = $self->header_status();
	$self->reset_header;

	# Make sure nesting works across UI objects
	my %starts;
	my $start_pat = '('
	  . join( '|' => map { qq{\Q$_\E} }
		grep { !$starts{$_}++ } map { $_->data('_start') } @objects )
	  . ')';
	my $mark_pat =
	  '(' . join( '|' => map { $_->data('_mark') } @objects ) . ')';
	my %cycles = ( _cycle_num => 1 );
	my @renderlines;
	my %used_objects;
	use vars qw/*REV/;
  RENDER: {
		push @renderlines =>
qq{<a name=\"cycle$cycles{_cycle_num}\"> </a>\n<hr>Cycle $cycles{_cycle_num}:\t\t\t[<a href="#top">top</a>]\n<hr>\n};
		foreach my $obj (@objects) {
			local *REV = *{$obj};
			defined &REV
			  or *REV = \&OUTPUT;

			my ( $start, $end, $mark ) =
			  $obj->data( '_start', '_end', '_mark' );
			push @renderlines => qq{<pre>\nProcess:\nMark\tStart\tEnd\n},
			  BVA::KALE::UTILS::HTML_entify(qq{$mark\t$start\t$end}),
			  qq{\n</pre>\n};
			$REV{_match_str} =
qr{(?s:((\Q${start}${mark}\E)[: ]((.(?!${start_pat}${mark_pat}))*?)\Q$end\E))};

		  GO: {
				my $str = $tmpl;
				study $str;
				$str =~ s{$REV{_match_str}}
				   {
					my ($t,$token)	= ($1,$1);
					my $arg			= $3;
					my $out			= REV($obj, $arg);
					$out			||= ($REV{__DONE__} ? $out : OUTPUT($obj, $arg));
					$out			||= (delete $REV{__DONE__} ? $out : $t);
					my $form		= $out;
					$token			= BVA::KALE::UTILS::HTML_entify($token);
					$form			= BVA::KALE::UTILS::HTML_entify($form);

# 					push @renderlines => qq{\n$token\n<blockquote><b>\n$form\n</b></blockquote>\n};
					push @renderlines => qq{\n$token\n<blockquote>\n<pre><b>\n$form\n</b></pre></blockquote>\n};
					push( @{ $used_objects{_names} } => $mark) unless $used_objects{$mark}++;
					push( @{ $cycles{$cycles{_cycle_num}}{_names} } => $mark) unless $cycles{$cycles{_cycle_num}}{$mark}++;
					$out;
				}gsex;    # $form			=~ s/\n/<br>\n/g;
				last GO if $str eq $tmpl;
				$tmpl = $str and redo GO;
			}
			push @renderlines => qq{\n};
		}
		last RENDER if $output eq $tmpl;
		$cycles{_cycle_num}++;
		$output = $tmpl and redo RENDER;
	}

	# Restore header status
	$self->header_status($temp_hdr_status);

	my $title = 'Reveal';
	my $revelation =
	  join "" =>
	  join( "  " => "Objects available:", map { $_->data('_mark') } @objects ),
	  qq{\n<br>\nProcessing Done:<br>\n$cycles{_cycle_num} cycles },
	  qq{rendering from }, scalar @{ $used_objects{_names} },
	  qq{ of the available objects },
	  join( ' ' => '(', @{ $used_objects{_names} }, ")<br>\n" ),
	  map(
		{ qq{<a href=\"#cycle$_\">Cycle $_</a> &nbsp; }
			  . join( ' ' => '(', @{ $cycles{$_}{_names} }, ")<br>\n" ) }
		sort grep { !/^_cycle_num$/ } keys %cycles ),
	  qq{<a href=\"#final\">Final Rendering</a>},
	  @renderlines,
	  qq{<a name=\"final\"> </a>\n<hr>},
	  qq{Final Rendering:\t\t\t[<a href="#top">top</a>]\n<hr>\n},
	  qq{<pre><b>\n},
	  BVA::KALE::UTILS::HTML_entify($output),
	  qq{</b></pre>},
	  qq{<br>\n};

	my $header = $self->process("RES_HDR=htm");
	my $hey    = <<HEY;
$header

<!DOCTYPE HTML>
<html lang="en">
<head>
	<title>$title</title>
</head>
<body style="background-color:#CCFFCC;padding-top:0;margin-top:0;">
<hr id="top" style="width:100%;height:0;color:#CCFFCC;margin:0;">

<h2>
$title
</h2>

<div style="text-align: left;">

$revelation

</div>

</body>
</html>

HEY

	print $hey;
	exit;

}

sub unveil ($;@) {
	my $self = shift();
	local *KEY = ref($self) eq __PACKAGE__ ? $self : *{$self};

	my $tmpl =
	     join( '' => @_ )
	  || $KEY
	  || $KEY{_default_tmpl};
	my $output = ' ';

	my @objects = objects(*KEY);

  LOAD: {
		foreach my $obj (@objects) {
			$obj->charge_auto();
			$obj->calculate();
		}
	}

	## Temporarily disable header block
	my $temp_hdr_status = $self->header_status();
	$self->reset_header;

	# Make sure nesting works across UI objects
	my %starts;
	my $start_pat = '('
	  . join( '|' => map { qq{\Q$_\E} }
		grep { !$starts{$_}++ } map { $_->data('_start') } @objects )
	  . ')';
	my $mark_pat =
	  '(' . join( '|' => map { $_->data('_mark') } @objects ) . ')';
	my %cycles = ( _cycle_num => 1 );
	my @renderlines;
	my %used_objects;
	use vars qw/*REV/;
  RENDER: {
		push @renderlines =>
qq{<a name=\"cycle$cycles{_cycle_num}\"> </a>\n<hr>Cycle $cycles{_cycle_num}:\t\t\t[<a href="#top">top</a>]\n<hr>\n};
		foreach my $obj (@objects) {
			local *REV = *{$obj};
			defined &REV
			  or *REV = \&OUTPUT;

			my ( $start, $end, $mark ) =
			  $obj->data( '_start', '_end', '_mark' );
			push @renderlines => qq{<pre>\nProcess:\nMark\tStart\tEnd\n},
			  BVA::KALE::UTILS::HTML_entify(qq{$mark\t$start\t$end}),
			  qq{\n</pre>\n};
			$REV{_match_str} =
qr{(?s:((\Q${start}${mark}\E)[: ]((.(?!${start_pat}${mark_pat}))*?)\Q$end\E))};

		  GO: {
				my $str = $tmpl;
				study $str;
				$str =~ s{$REV{_match_str}}
				   {
					my ($t,$token)	= ($1,$1);
					my $arg			= $3;
					my $out			= REV($obj, $arg);
					$out			||= ($REV{__DONE__} ? $out : OUTPUT($obj, $arg));
					$out			||= (delete $REV{__DONE__} ? $out : $t);
					my $form		= $out;
					$token			= BVA::KALE::UTILS::HTML_entify($token);
					$form			= BVA::KALE::UTILS::HTML_entify($form);

# 					push @renderlines => qq{\n$token\n<blockquote><b>\n$form\n</b></blockquote>\n};
					push @renderlines => qq{\n$token\n<blockquote>\n<pre><b>\n$form\n</b></pre></blockquote>\n};
					push( @{ $used_objects{_names} } => $mark) unless $used_objects{$mark}++;
					push( @{ $cycles{$cycles{_cycle_num}}{_names} } => $mark) unless $cycles{$cycles{_cycle_num}}{$mark}++;
					$out;
				}gsex;    # $form			=~ s/\n/<br>\n/g;
				last GO if $str eq $tmpl;
				$tmpl = $str and redo GO;
			}
			push @renderlines => qq{\n};
		}
		last RENDER if $output eq $tmpl;
		$cycles{_cycle_num}++;
		$output = $tmpl and redo RENDER;
	}

	# Restore header status
	$self->header_status($temp_hdr_status);

	my $title = 'Rendering Steps';
	my $revelation =
	  join "" =>
	  join( "  " => "Objects available:", map { $_->data('_mark') } @objects ),
	  qq{\n<br>\nProcessing Done:<br>\n$cycles{_cycle_num} cycles },
	  qq{rendering from }, scalar @{ $used_objects{_names} },
	  qq{ of the available objects },
	  join( ' ' => '(', @{ $used_objects{_names} }, ")<br>\n" ),
	  map(
		{ qq{<a href=\"#cycle$_\">Cycle $_</a> &nbsp; }
			  . join( ' ' => '(', @{ $cycles{$_}{_names} }, ")<br>\n" ) }
		sort grep { !/^_cycle_num$/ } keys %cycles ),
	  qq{<a href=\"#final\">Final Rendering</a>},
	  @renderlines,
	  qq{<a name=\"final\"> </a>\n<hr>},
	  qq{Final Rendering:\t\t\t[<a href="#top">top</a>]\n<hr>\n},
	  qq{<pre><b>\n},
	  BVA::KALE::UTILS::HTML_entify($output),
	  qq{</b></pre>},
	  qq{<br>\n};

	my $hey = <<HEY;
<!DOCTYPE HTML>
<html lang="en">
<head>
    <meta charset="utf-8" />
	<title>$title</title>
	<style>
	body { background-color:#CCFFCC;padding-top:0;margin-top:0; }
	hr#top { width:100%;height:0;color:#CCFFCC;margin:0; }
	div#reveal { text-align:left;font-size:1.2em; }
	</style>
</head>
<body>
<hr id="top">

<h2>
$title
</h2>

<div id="reveal">

$revelation

</div>

</body>
</html>

HEY

	return $hey;
}

## Test Subroutines

sub dumpit {
	my $self = shift();
	local *KEY = ref($self) eq __PACKAGE__ ? $self : *{$self};
	my $env = $KEY{_env} || 'htm';

	my $ref    = shift() || ( $KEY{_mark} eq $KEY{_ui_mark} ? \%KEY : \*KEY );
	my $pure   = shift();
	my $output = '';

	# 	use Data::Dumper;
	local $Data::Dumper::Purity   = length($pure) ? $pure : 1;
	local $Data::Dumper::Deparse  = 1;
	local $Data::Dumper::Sortkeys = 1;

	#no warnings;
	eval { $output = Dumper($ref); 1 }
	  or do {
	  	my $prob	= $@;
	  	$output .= "\nDumper problem: \n$prob"; };
	if ($env =~ /htm|psgi/i) {
		$output = "<pre>\n" . $self->HTML_entify($output) . "\n</pre>"
	}
	return "\n$output\n";
}

## Generate message closures
## for placing dynamic text into layouts and templates
## $msg = make_msg("Record $id");	# creates the message sub with optional initial msg
## The closure accepts a string or a hash ref:
## $msg->("add: ...");			# appends ' ...' to msg
## $msg->("or: ...");			# inserts '...' if msg is empty
## $msg->("print: ...");			#outputs whole msg plus '...'
## $msg->("log: ...");				#outputs a timestamp and the whole msg, stripped of html
## $msg->("msg: msg_name, ...");	#looks up msg_name, inserts any message plus '...'
##  $msg->({msg => msg_name});
## Used by charge_msg() and charge_err().
sub make_msg ($;@) {

	# $key may be a UI object or typeglob (*KEY)
	my $key = shift;
	my $default_msg = shift || '';
	$default_msg =~ s/\<time\>/BVA::KALE::DATETIME::tell_time('iso')/ge;
	my $msg_holder = '';
	return sub {
		my $in = shift;
		return $msg_holder unless $in;
		my $time = BVA::KALE::DATETIME::tell_time('iso');
		my ( $command, $add_msg ) = ref($in) ? %{$in} : split /: /, $in, 2;
		$add_msg and $add_msg =~ s/\<time\>/$time/ge;

		if ( $command =~ /^print/i ) {
			$msg_holder .= $add_msg;
			return qq|$default_msg $msg_holder|;
		}
		elsif ( $command =~ /^add/i ) {
			$msg_holder .= $add_msg;
			return $add_msg;
		}
		elsif ( $command =~ /^msg/i ) {
			my ( $msg_name, $msg ) = split /\s*,\s*/ => $add_msg, 2;
			$msg_holder = message( $key, $msg_name ) . ( $msg || '' );
			return $msg_holder;
		}
		elsif ( $command =~ /^or/i ) {
			$msg_holder = $msg_holder =~ /^\s*$/s ? $add_msg : $msg_holder;
			return $msg_holder;
		}
		elsif ( $command =~ /^log/i ) {
			$msg_holder .= qq|\n$time $add_msg|;
			$msg_holder =~ s/<br>//i;
			return qq|$time $default_msg $msg_holder|;
		}
		else {
			$msg_holder = $in;
			return $msg_holder;
		}
	};
}

sub DESTROY {

	#	my ($pm,$me) = split '=', $_[0];
	#	my $self = shift;
	#	local *KEY = ref($me) eq __PACKAGE__ ? $me : *{ $me };
	#	local *KEY = *{ $self };
	#	close KEY if defined *KEY{IO};
	#	print qq{$KEY{_mark}\n};
	#	print qq{\n<!--[ Goodbye from $pm v. $VERSION]-->\n};
	#	return qq{[ Goodbye from $pm v. $BVA::KALE::VERSION ]};
}

=head1 AUTHOR

Bruce W Van Allen, C<< <bva at cruzio.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-bva-kale at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=BVA-KALE>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc BVA::KALE


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=BVA-KALE>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/BVA-KALE>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/BVA-KALE>

=item * Search CPAN

L<http://search.cpan.org/dist/BVA-KALE/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2014 Bruce W Van Allen.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1;
