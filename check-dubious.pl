#!/usr/bin/perl
use strict;
use warnings;


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


my (@temp, $url, $number, $lang, $confidence, $final);

my $input = 'CHECKED';
open (my $infh, "<", $input) or die "Cannot open INPUT file : $!\n";
my $output = 'CHECKED-FILTERED';
open (my $outfh, ">", $output) or die "Cannot open OUTPUT file : $!\n";


while(<$infh>) {
	chomp;
	$_ =~ m/^(.+?) ([0-9]+) \('([a-z]+)', ([0-9\.]+)\)$/;	
	$url = $1;
	$number = $2;
	$lang = $3;
	$confidence = $4;

	# Character size limit
	if ($number > 2000) {
		if ( ($url =~ m/\.ru$/) && ($lang eq "zh") ) {
			$lang = "ru";
			$confidence = "0.111"
		}
		print $outfh $url . "\t" . $lang . "\t" . $confidence . "\n";
	}
}


close($infh);
close($outfh);
