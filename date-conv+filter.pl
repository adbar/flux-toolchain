#!/usr/bin/perl


###	This script is part of the FLUX Toolchain project (https://github.com/adbar/flux-toolchain).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The FLUX Toolchain is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


use strict;
use warnings;
use Getopt::Long;
use Time::Piece;
use Try::Tiny;


my ($help, $inputfile, $outputfile, $mergedfile);
usage() if ( @ARGV < 1
	or ! GetOptions ('help|h' => \$help, 'input|i=s' => \$inputfile, 'output|o=s' => \$outputfile, 'merged|m=s' => \$mergedfile)
	or defined $help
	or ( (! defined $inputfile) || (! defined $outputfile) )
);

sub usage {
	print "Unknown option: @_\n" if ( @_ );
	print "Usage: perl XX.pl [--help|-h] [--inputfile|-i] filename [--outputfile|-o] filename [--merged|-m] merged results file (not required)\n\n";
	exit;
}


my (%hash, %deletions);

open (my $input, "<", $inputfile) or die "Cannot open input file : $!\n";
open (my $converted, ">", $outputfile) or die "Cannot open output file : $!\n";

while (<$input>) {
	chomp;
	my @line = split("\t", $_);
	my $timexp = $line[9];
	$timexp =~ s/,//;
	unless ( ($timexp eq "ø") || ($timexp =~ /^[0-9]+$/) || ($timexp =~ /^!/) ) {
		my $time;
		try {
			# UTC workaround
			if ($timexp =~ m/GMT|UTC/) {
				if ($timexp =~ "UTC") {
					$timexp =~ s/UTC/GMT/;
				}
				$time = Time::Piece->strptime($timexp, '%a %d %b %Y %H:%M:%S %Z');
			}
			else {
				$time = Time::Piece->strptime($timexp, '%a %d %b %Y %H:%M:%S %z');
			}
			my $timestamp = $time->strftime('%s');
			$line[9] = $timestamp;
		}
		catch {
			$line[9] = "! " . $timexp;
		}
	}
	else {
		$line[9] = $timexp;
	}

	my $convline = join("\t", @line);
	print $converted $convline . "\n";

	# if the lines are to be merged
	if ( (defined $mergedfile) && ($line[9] =~ /^[0-9]+$/) ) {
		unless (exists $hash{$line[0]}) {
			$hash{$line[0]} = $line[9];
		}
		# if the hashed URL has already been seen
		else {
			# create deletion key
			if (! exists $deletions{$line[0]}) {
				$deletions{$line[0]} = ();
			}
			# update the hash : keep the most recent date as hash value
			# if the line contains a UNIX-style date : optimize [ø!] ?
			if ( ($line[9] =~ /^[0-9]+$/) && ($hash{$line[0]} =~ /^[0-9]+$/) ) {
				if ($line[9] > $hash{$line[0]}) {
					$hash{$line[0]} = $line[9];
				}
			}
		}
	}
}

close($input);
close($converted);


# merge the results, keeping only the most recent one
if (defined $mergedfile) {

	open (my $input2, "<", $outputfile) or die "Cannot open conversion file : $!\n";
	open (my $merged, ">", $mergedfile) or die "Cannot open merging file : $!\n";
	while (<$input2>) {
		chomp;
		my @line = split("\t", $_);
		if ( $line[9] =~ /^[0-9]+$/ ) {
			# check if the line has been marked for deletion
			if (exists $deletions{$line[0]}) {
				# check the time stamp against the highest seen for this URL
				if ($line[9] >= $hash{$line[0]}) {
					# avoid duplicates
					unless (defined $deletions{$line[0]}) {
						print $merged $_ . "\n";
						$deletions{$line[0]} = 1;
					}
				}
			}
			else {
				print $merged $_ . "\n";
			}
		}
		else {
			# check if there is a numerical date value somewhere (= stored in the hash)
			unless (exists $hash{$line[0]}) {
				print $merged $_ . "\n";
				# avoid duplicates (could also use the deletions hash)
				$hash{$line[0]} = ();
			}
		}
	}

	close($merged);
	close($input2);

}
