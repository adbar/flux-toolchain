#!/usr/bin/perl
use strict;
use warnings;

use URI::Split qw(uri_split uri_join);
use Digest::MD5 qw(md5_base64);

use Time::HiRes qw( time sleep );
use Try::Tiny; # on Debian/Ubuntu package libtry-tiny-perl

use Devel::Size qw(size total_size);

use Bloom::Faster;
use DBI;



my $dbh = DBI->connect( "dbi:SQLite:test.db","","" );
$dbh->{AutoCommit} = 0;
# Problem here
$dbh->do("DROP TABLE hashes");
$dbh->do("CREATE TABLE hashes (id INTEGER PRIMARY KEY, value UNIQUE)"); # value TEXT


## Most global variables here
my (@urls, %seen, %hostnames, %seen_hostnames, $clean_text, $confidence, $lang, $suspicious, $join, $scheme, $auth, $path, $query, $frag, $furl, $lwp_ua, $body, $final_red, $length_a, $length_b, $wordcount);
my ($ext_uri, $red_uri, $digest, $last_url, $last_red_uri, $last_digest);
my $inner_loop_time = 0;

my $start_time = time();
my $md5length = 12;
my $hostreduce = ();

my $bloomsize = 500000;
my $bloomfilter = new Bloom::Faster({n => $bloomsize, e => 0.0001});
my $bloomcseen = 0;
my $bloomctodo = 0;


## Files
### bound to change by command-line option
my $todo = 'LINKS-TODO';
my $urlseenfile = 'URL-SEEN';
my $urlseen_bufferfile = 'URL-SEEN-BUFFER';


# Process the 'seen' file, if there is one
# may be a db some day
my $insert = $dbh->prepare( "INSERT OR IGNORE INTO hashes (value) VALUES (?)" );
my (%tempvalues, $tobestored);

open (my $ldone, '<', 'URL-SEEN-BUFFER') or die "Cannot open 'seen hostnames' file : $!\n";;
	while (<$ldone>) {
		chomp;
		# expected : first column hash, second one whole url without protocol, rest whatever
		if ($_ =~ m/\t/) {
			my @temp = split ("\t", $_);
			# $seen_hostnames{$temp[0]} = ();	# = $temp[1];
                        $tobestored = $temp[0];
		}
		# if it's just a 'simple' list of urls or hashes
		## add url parser support
		else {
			#trim_url($_);
			#$digest = substr(md5_base64($_), 0, $md5length);
			# $seen_hostnames{$digest} = ();	# = $_
                        #$tobestored = $digest;
                        $tobestored = $_;
		}
                # store it
                store($tobestored);
	}
        # store the rest
        while ( my ($key, $value) = each(%tempvalues))  {
            $insert->execute($key);
        }
        $dbh->commit();
        # $dbh->finish();
        %tempvalues = ();

	close($ldone);

# $dbh->do("DELETE FROM hashes WHERE id NOT IN (SELECT MAX(id) FROM hashes GROUP BY value");
print "seen file loaded\n";


# Process the 'todo' file (required)
open (my $ltodo, '<', 'LINKS-TODO') or die "Cannot open LINKS-TODO file : $!\n";

# print digests on the go
open (my $urlbuffer, ">>", $urlseen_bufferfile) or die "Cannot open URL-SEEN-BUFFER file : $!\n";

# db prepare
my $select = $dbh->prepare( "SELECT id FROM hashes WHERE value is ?" );

# loop (file lines)
while (<$ltodo>) {
	chomp;
        trim_url($_);
        # whole URL digest, spare memory
        $digest = substr(md5_base64($_), 0, $md5length);
        if (lookup($digest) == 0) {
            push (@urls, $_);
            print $urlbuffer "$digest\n";
            store($digest);
        }

}

print "todo file loaded\n";
close($urlbuffer);
close($ltodo);


# empty list case
die 'empty list' if (scalar(@urls) == 0);



$dbh->disconnect;


# Print infos
# foreach my $url (@urls) {
#    print $url . "\n";
#}
my $total_time = time() - $start_time;
print "exec. time:\t" . sprintf("%.2f\n", $total_time);



# SUBROUTINES

# trim URLs (unified processing)
sub trim_url {
	my $url_string = shift;
	$url_string =~ s/\/$//;			# avoid duplicates like www.mestys-starec.eu and www.mestys-starec.eu/
	$url_string =~ s/^https?:\/\///;		# remove protocol
	# $_ =~  s/^www[0-9]?\.//;		# remove www
	$url_string =~ s/^(www)[0-9]+?(\.)/$1$2/;	# remove digits after www
	return $url_string;
}


# store the value in the databases
sub store {
    my $tempdigest = shift;
    $bloomfilter->add($tempdigest);
    $tempvalues{$tempdigest} = ();
    if (keys %tempvalues >= 100000) {
        while ( my ($key, $value) = each(%tempvalues))  {
            $insert->execute($key);
        }
        $dbh->commit();
        # $dbh->finish();
        %tempvalues = ();
    }
}

## bloomfilter + SQLite lookup subroutine
sub lookup {
    my $tempdigest = shift;
    my $select = $dbh->prepare( "SELECT id FROM hashes WHERE value is ?" );
    if (exists $tempvalues{$tempdigest}) {
        return "1";
    }
    else {
        #if ($bloomfilter->add($tempdigest)) {
        if ($bloomfilter->check($tempdigest)) {
            print "in bloomfilter\t";
            my $timetest = time();
            my $timeresult;
            $select->execute($tempdigest);
            if (defined ( my $r = $select->fetchrow_arrayref )) {
                $select->finish();
                $timeresult = time() - $timetest;
                print "SQLite query time: " . sprintf("%.2f", $timeresult) . "\t in DB\n";
                return "1";
            }
            else {
                $select->finish();
                $timeresult = time() - $timetest;
                print "SQLite query time: " . sprintf("%.2f", $timeresult) . "\t not in DB\n";
                return "0";
            }
        }
        else {
            print "Not in bloomfilter\n";
            return "0";
        }
    }
}

