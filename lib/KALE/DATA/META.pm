package BVA::KALE::DATA::META;

$BVA::KALE::DATA::META::VERSION	= .099_001;

use strict;
use warnings;

sub meta_fldtype_defaults {
	my $self	= shift;
	
	return {
		_sort_packs 	=> \%BVA::KALE::DATA::META::sort_packs,
		_record_packs	=> \%BVA::KALE::DATA::META::record_packs,
		_fld_packs		=> \%BVA::KALE::DATA::META::fld_packs,
		_fld_fmts		=> \%BVA::KALE::DATA::META::fld_fmts,
		_nulls			=> \%BVA::KALE::DATA::META::nulls,
	};
}

%BVA::KALE::DATA::META::sort_packs = (
	't'		=> 'A#',
	'n'		=> 'N',
	'b'		=> 'A#',
	'd'		=> 'A#',
	'ct'	=> 'A#',
	'a'		=> 'Z*',
	's'		=> 'A#',
	'h'		=> 'A#',
	'r'		=> 'A#',
	'rset'	=> 'A#',
	'pop'	=> 'A#',
	'c'		=> 'A#',
	'f'		=> 'A#',
	'p'		=> 'A#',
	'm'		=> 'A#',
);	 
	 
%BVA::KALE::DATA::META::record_packs = (
	't'		=> 'Z*',
	'n'		=> 'Z*',
	'b'		=> 'Z*',
	'd'		=> 'Z*',
	'ct'	=> 'Z*',
	'a'		=> 'Z*',
	's'		=> 'Z*',
	'h'		=> 'Z*',
	'r'		=> 'Z*',
	'rset'	=> 'Z*',
	'pop'	=> 'Z*',
	'c'		=> 'Z*',
	'f'		=> 'Z*',
	'p'		=> 'Z*',
	'm'		=> 'Z*',
);

%BVA::KALE::DATA::META::fld_packs = (
	't'		=> 'A#',
	'n'		=> 'N',
	'b'		=> 'A#',
	'd'		=> 'A#',
	'ct'	=> 'A#',
	'a'		=> 'Z*',
	's'		=> 'A#',
	'h'		=> 'A#',
	'r'		=> 'A#',
	'rset'	=> 'A#',
	'pop'	=> 'A#',
	'c'		=> 'A#',
	'f'		=> 'A#',
	'p'		=> 'A#',
	'm'		=> 'A#',
);

%BVA::KALE::DATA::META::fld_fmts = (
	't'		=> '%-#.#s',
	'n'		=> '%#.#s',
	'b'		=> '%-#.#s',
	'd'		=> '%-#.#s',
	'ct'	=> '%-#.#s',
	'a'		=> '%-#.#s',
	's'		=> '%-#.#s',
	'h'		=> '%-#.#s',
	'r'		=> '%-#.#s',
	'rset'	=> '%-#.#s',
	'pop'	=> '%-#.#s',
	'c'		=> '%-#.#s',
	'f'		=> '%-#.#s',
	'p'		=> '%-#.#s',
	'm'		=> '%-#.#s',
);

%BVA::KALE::DATA::META::nulls = (
	't'		=> '',
	'n'		=> 0,
	'b' 	=> 0,
	'd'		=> '0000-00-00',
	'ct'	=> '00:00:00',
	'a'		=> '',
	's'		=> '',
	'h'		=> '',
	'r'		=> '',
	'rset'	=> '',
	'pop'	=> '',
	'c'		=> '',
	'f'		=> '',
	'p'		=> '',
	'm'		=> '',
);
