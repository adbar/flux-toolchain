#!/usr/bin/perl


###	This script is part of the FLUX Toolchain project (https://github.com/adbar/flux-toolchain).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The FLUX Toolchain is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

# EXAMPLE: perl extract-urls.pl -c total-url-couples -d total-dictionary -r total-clean -o testout -l fr &


use strict;
use warnings;
use Getopt::Long;


my ($help, $couples, $dict, $results, $outputfile, $languages);
usage() if ( @ARGV < 1
	or ! GetOptions ('help|h' => \$help, 'couples|c=s' => \$couples, 'dict|d=s' => \$dict, 'results|r=s' => \$results, 'output|o=s' => \$outputfile, 'languages|l=s' => \$languages)
	or defined $help
	or ( (! defined $couples) || (! defined $dict) || (! defined $outputfile) )
);

sub usage {
	print "Unknown option: @_\n" if ( @_ );
	print "Usage: perl XX.pl [--help|-h] [--couples|-c] filename [--dict|-d] filename [--results|-r] filename [--outputfile|-o] filename [--languages|-l] comma-separated language codes\n\n";
	exit;
}


# languages
my (@languages, %urlhashes, %tofind);
if (defined $languages) {
	if ($languages =~ m/,/) {
		@languages = split (",", $languages);
	}
	else {
		@languages = [ $languages ];
	}
}


# results input
open (my $input1, "<", $results) or die "Cannot open results file : $!\n";
while (<$input1>) {
	chomp;
	my @line = split("\t", $_);
	if (defined $languages) {
		# not that efficient
		if ($line[1] ~~ @languages) {
			$urlhashes{$line[0]} = ();
		}
	}
	else {
		$urlhashes{$line[0]} = ();
	}
}
close($input1);

# couples input
open (my $input2, "<", $couples) or die "Cannot open couples file : $!\n";
while (<$input2>) {
	chomp;
	my @line = split("\t", $_);
	if (exists $urlhashes{$line[0]}) {
		$tofind{$line[1]} = ();
	}
}
close($input2);


# dict input
open (my $input3, "<", $dict) or die "Cannot open dict file : $!\n";
open (my $output, ">", $outputfile) or die "Cannot open output file : $!\n";

while (<$input3>) {
	chomp;
	my @line = split("\t", $_);
	if (exists $tofind{$line[0]}) {
		print $output $line[1] . "\n";
	}
}

close($input3);
close($output);
