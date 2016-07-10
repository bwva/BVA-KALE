#!/usr/bin/env perl

# Date:		2013-03-11

# Tests for DATA::WHERE::make_selector

use Carp qw( confess );
$SIG{__DIE__} =  \&confess;
$SIG{__WARN__} = \&confess;

use strict;
use warnings;

use Test::More;

use Data::Dumper;

use Class::Inspector;

$|++;

use BVA::KALE;
use BVA::KALE::DATA;
use BVA::KALE::DATA::WHERE;

my $ui		= BVA::KALE->init();
my $sup	= $ui->new({'_mark' => 'SUP', '_start' => '[', '_end' => ']'});

if ($sup->input_data('show_subs')) {
	print 'DATA::WHERE', "\n===========\n";
	print join("\n" => "Functions:\n--------", @{ Class::Inspector->functions( 'BVA::KALE::DATA::WHERE' ) || [] }), "\n---\n\n";
	print join("\n" => "Methods:\n--------", @{ Class::Inspector->methods( 'BVA::KALE::DATA::WHERE', 'full') || [] }), "\n---\n\n";	
#	print join("\n" => "Methods:\n--------", map { join("\n\t" => @{$_},"\n") } @{ Class::Inspector->methods( 'DATA::WHERE', 'public', 'expanded') }), "\n---\n";

	print 'BVA::KALE::DATA', "\n===========\n";
	print join("\n" => "Functions:\n--------", @{ Class::Inspector->functions( 'BVA::KALE::DATA' ) }), "\n---\n";
	print join("\n" => "Methods:\n--------", @{ Class::Inspector->methods( 'BVA::KALE::DATA', 'full') }), "\n---\n";	
#	print join("\n" => "Methods:\n--------", map { join("\n\t" => @{$_},"\n") } @{ Class::Inspector->methods( 'BVA::KALE::DATA', 'public', 'expanded') }), "\n---\n";
}

is($sup->data('_mark'), 'SUP', 'mark should be \'SUP\'');

ok($sup->dbx_connect({db => '/Users/bwva/Desktop/supporters.txt',input_sep => "\t"}), 'dbx_connect should load db' );

my $verbose				= $sup->input_data('verbose') || 0;
my $show_first_round	= $sup->input_data('show_first_round') || 0;
my $textnum	= 0;
my @tests;
while (my $testline = <DATA>) {

	next if $testline =~ /^\#/;

	chomp $testline;
	
	last unless $testline;

	$textnum++;
	
	my ($ok, $text)	= split /\s*,\s*/ => $testline, 2;
	
	my $err_test	= $ok ? 0 : 1;
	my $err_phrase	= $err_test ? "Expected error on invalid statement $textnum." : "Should be no errors on valid statement $textnum.";
	
	print "\n** Text $textnum:\n", $text, "\n";

	if ($show_first_round) {
		my $where	= $text;
	
		my @parts	= $sup->dbh->_parser($where);
		print "a. Parts:\n", Dumper(\@parts),"\n--\n" if $verbose;

		my @chunks	= $sup->dbh->_chunker(@parts);
		print "b. Chunks:\n", Dumper(\@chunks),"\n----\n" if $verbose;

		my @groups	= $sup->dbh->_grouper(@chunks);
		print "c. Groups:\n", Dumper(\@groups),"\n----\n" if $verbose;

		my @tagged_groups	= $sup->dbh->_tagger( @groups );
		print "d. Tagged Groups:\n", Dumper(\@tagged_groups),"\n----\n" if $verbose;
	
	# 	my $selector1		= $sup->dbh->_parse_conditions( @tagged_groups );
	# 	print "e. Selector:\n", $sup->dumpit($selector1),"\n----\n" if $verbose;
	}

 	my $selector1	= $sup->dbh->make_selector($text);	
	print "e. Selector:\n", $sup->dumpit($selector1),"\n----\n" if $verbose && $show_first_round;

	is( $selector1->{error}, $err_test, $err_phrase . qq{\n\t$selector1->{where}});
	
	my $selector2	= $sup->dbh->make_selector($selector1->{where});
	
	SKIP: {
		if ($selector1->{error}) {	
# 			skip( "because original selector had errors for statement $textnum.", 2);
			skip( "because original selector had errors for statement $textnum.",1);
		}
		
		is( $selector2->{error}, "0", "Should be no errors in re-done selector for statement $textnum.");
		
		SKIP: {
			if ($selector2->{error}) { 
				print $selector1->{where}, "\n";

				my @parts	= $sup->dbh->_parser($selector1->{where});
				#die join( ' | ' => grep { $_ } @parts), "\n";

				print "a. Parts:\n", Dumper(\@parts),"\n--\n" if $verbose;

				my @chunks	= $sup->dbh->_chunker(@parts);
				print "b. Chunks:\n", Dumper(\@chunks),"\n----\n" if $verbose;

				my @groups	= $sup->dbh->_grouper(@chunks);
				print "c. Groups:\n", Dumper(\@groups),"\n----\n" if $verbose;

				my @tagged_groups	= $sup->dbh->_tagger( @groups );
				print "d. Tagged Groups:\n", Dumper(\@tagged_groups),"\n----\n" if $verbose;

# 				skip("Because the re-done selector had errors for statement $textnum.", 1);
				skip("Because the re-done selector had errors for statement $textnum.");

			}
			
			SKIP: {
				unless ($sup->input_data('exact_sttmt')) {
# 					skip("Set to skip with \'exact_sttmt=0\'.", 1);
					skip("Set to skip with \'exact_sttmt\'.",1);
				}
				is($selector2->{where}, $selector1->{where}, "re-done \'where\' should be same as original, at statement $textnum\n\t$selector2->{where}");
			}
			
###
			my $selector3	= $sup->dbh->make_selector($selector2->{where});
	
			SKIP: {
				if ($selector2->{error}) {	
		# 			skip( "because secondary selector had errors for statement $textnum.", 2);
					skip( "because secondary selector had errors for statement $textnum.");
				} 
				is( $selector3->{error}, "0", "Should be no errors in re-done selector from secondary selector for statement $textnum.");
		
				SKIP: {
					if ($selector3->{error}) { 
						print $selector1->{where}, "\n";

						my @parts	= $sup->dbh->_parser($selector1->{where});
						#die join( ' | ' => grep { $_ } @parts), "\n";

						print "a. Parts:\n", Dumper(\@parts),"\n--\n" if $verbose;

						my @chunks	= $sup->dbh->_chunker(@parts);
						print "b. Chunks:\n", Dumper(\@chunks),"\n----\n" if $verbose;

						my @groups	= $sup->dbh->_grouper(@chunks);
						print "c. Groups:\n", Dumper(\@groups),"\n----\n" if $verbose;

						my @tagged_groups	= $sup->dbh->_tagger( @groups );
						print "d. Tagged Groups:\n", Dumper(\@tagged_groups),"\n----\n" if $verbose;

		# 				skip("Because the re-done selector had errors for statement $textnum.", 1);
						skip("Because the re-done selector had errors for statement $textnum.");

					}

					is($selector3->{where},$selector2->{where}, "re-done \'where\' should be same as secondary, at statement $textnum\n\t$selector3->{where}");
				}
			}
###			
		}
	}
	
# 	my $selector3	= $sup->dbh->make_selector($selector2->{where});
# 	
# 	SKIP: {
# 		if ($selector2->{error}) {	
# # 			skip( "because secondary selector had errors for statement $textnum.", 2);
# 			skip( "because secondary selector had errors for statement $textnum.");
# 		} 
# 		is( $selector3->{error}, "0", "Should be no errors in re-done selector from secondary selector for statement $textnum.");
# 		
# 		SKIP: {
# 			if ($selector3->{error}) { 
# 				print $selector1->{where}, "\n";
# 
# 				my @parts	= $sup->dbh->_parser($selector1->{where});
# 				#die join( ' | ' => grep { $_ } @parts), "\n";
# 
# 				print "a. Parts:\n", Dumper(\@parts),"\n--\n" if $verbose;
# 
# 				my @chunks	= $sup->dbh->_chunker(@parts);
# 				print "b. Chunks:\n", Dumper(\@chunks),"\n----\n" if $verbose;
# 
# 				my @groups	= $sup->dbh->_grouper(@chunks);
# 				print "c. Groups:\n", Dumper(\@groups),"\n----\n" if $verbose;
# 
# 				my @tagged_groups	= $sup->dbh->_tagger( @groups );
# 				print "d. Tagged Groups:\n", Dumper(\@tagged_groups),"\n----\n" if $verbose;
# 
# # 				skip("Because the re-done selector had errors for statement $textnum.", 1);
# 				skip("Because the re-done selector had errors for statement $textnum.");
# 
# 			}
# 
# 			is($selector3->{where},$selector2->{where}, "re-done \'where\' should be same as secondary, at statement $textnum\n\t$selector3->{where}");
# 		}
# 	}




#	push @tests => $selector1,$selector2,$selector3;	
}

done_testing();

#print join( "\n" => map { $_->[0]{where}||"Sumpin'" . "\nTO\n" . $_->[1]{where}||"_Nuttin'" . "\n-----\n" } @tests) if $verbose;


__END__
1,last=jones
1,last=smith AND home_city=santa Cruz AND address+ ^ H 
1,(last=smith AND (home_city=Santa Cruz OR (home_zip=95060 OR home_zip=95062))) AND (last=jones AND (home_city=Capitola OR home_zip=95010)) OR ?=whatever
1,last=jones AND (home_city=Capitola OR home_zip=95010)
0,last=jones AND (home_city=Capitola OR home_zip=95010
1,last=jones AND (home_city=Capitola OR home_zip=95010) OR ?=whatever
1,last=smith AND (home_city=Santa Cruz OR home_zip=95060) OR last=jones AND (home_city=Capitola OR home_zip=95010) OR ?=whatever
1,(last=smith AND (home_city=Santa Cruz OR home_zip=95060)) OR (last=jones AND (home_city=Capitola OR home_zip=95010)) OR ?=whatever
1,(home_city=Santa Cruz OR home_zip=95060) OR last=jones AND (home_city=Capitola OR home_zip=95010)
0,(city+=santa Cruz OR city+=capitola) AND lastname=smith
1,rec_id !* AND (first=Tex OR mid=Tex) AND (home_city=santa cruz OR work_city=santa cruz) AND (home_zip ^ 950 OR work_zip ^ 95)
1,last=smith AND ((home_city=santa Cruz OR work_city=santa Cruz OR alt_city=santa Cruz) OR (home_city=capitola OR work_city=capitola OR alt_city=capitola))
1,last=smith AND (city+=santa Cruz OR city+=capitola)
1,(home_city = santa Cruz OR work_city = santa Cruz OR alt_city = santa Cruz) AND (home_city = capitola OR work_city = capitola OR alt_city = capitola)
1,((home_city = santa Cruz OR work_city = santa Cruz OR alt_city = santa Cruz) OR (home_city = capitola OR work_city = capitola OR alt_city = capitola))
1,city+ ^ san AND home_zip+ ^ 95
0,city+ ^ san AND home_zip+ ^ 95)
0,(city+ ^ san AND home_zip+ ^ 95
1,last ^ van AND ((home_city = santa Cruz OR work_city = santa Cruz OR alt_city = santa Cruz) OR (home_city = capitola OR work_city = capitola OR alt_city = capitola))
1,alerts=~(Yes|No|Maybe)
1,city+~(san|gil|wat) OR rec_id*
1,( home_city~(san|gil|wat) OR work_city~(san|gil|wat) OR alt_city~(san|gil|wat) ) OR rec_id*
1,(home_city^san OR work_city^san OR alt_city^san) AND (email* OR alt_email* OR bad_email*)
1,(home_city=~(San .*|Los .*) OR work_city=~(San .*|Los .*) OR alt_city=~(San .*|Los .*))
1,home_city=~(San .*|Los .*) OR work_city=~(San .*|Los .*) OR alt_city=~(San .*|Los .*)
1,city+=~(San .*|Los .*)
1,city+ ^ san
1,city+ ^ san AND first ^ B
0,(city+ ^ san AND home_zip+ ^ 95
1,last=smith
1,last=smith,first^b
1,last=smith AND home_city=santa Cruz AND address+ ^ H 
1,(home_city ^san OR work_city ^san OR alt_city ^san) AND (home_zip ^ 95 OR home_zip_four ^ 95 OR home_zip_plus_four ^ 95 OR work_zip ^ 95 OR work_zip_four ^ 95 OR work_zip_plus_four ^ 95 OR alt_zip ^ 95 OR alt_zip_four ^ 95 OR alt_zip_plus_four ^ 95 OR mail_zip ^ 95) 
1,((home_city ^san OR work_city ^san OR alt_city ^san) AND (home_zip ^ 95 OR home_zip_four ^ 95 OR home_zip_plus_four ^ 95 OR work_zip ^ 95 OR work_zip_four ^ 95 OR work_zip_plus_four ^ 95 OR alt_zip ^ 95 OR alt_zip_four ^ 95 OR alt_zip_plus_four ^ 95 OR mail_zip ^ 95))
1,last=smith AND first^W AND (home_city=santa cruz OR work_city=santa cruz OR alt_city=santa cruz) 
1,(first=Tex OR mid=Tex) AND (home_city=santa cruz OR work_city=santa cruz OR alt_city=santa cruz) 
1,((last = smith AND (home_city = Santa Cruz OR home_zip = 95060)) OR (last = jones AND (home_city = Capitola OR home_zip = 95010)) OR ? = whatever)
1,(last=smith AND (home_city=Santa Cruz AND (home_zip=95060 OR home_zip=95062))) OR (last=jones AND (home_city=Capitola OR home_zip=95010)) OR ?=whatever
1,(last=smith AND (home_city=Santa Cruz OR home_zip=95060)) OR (last=jones AND (home_city=Capitola OR home_zip=95010)) OR ?=whatever
1,(last=smith AND (home_city=Santa Cruz OR home_zip=95060)) OR (last=jones AND home_city=Capitola) OR ?=whatever
1,last=smith AND (home_city=Santa Cruz OR home_zip=95060)
1,last=smith AND (home_city=Santa Cruz OR home_zip=95060) OR ?=whatever
