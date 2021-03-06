#!/usr/bin/perl


###	This script is part of the FLUX Toolchain project (https://github.com/adbar/flux-toolchain).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The FLUX Toolchain is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


use strict;
use warnings;
use Getopt::Long;
use Fcntl qw(:flock SEEK_END);
use Encode qw(encode); # decode_utf8
# use Encoding::FixLatin qw(fix_latin); # may be a fix for Perl 5.10
require Compress::Zlib;
use base 'HTTP::Message';
use LWP::UserAgent;
require LWP::Protocol::https;
#require LWPx::ParanoidAgent; # on Debian/Ubuntu package liblwpx-paranoidagent-perl
use IO::Socket::SSL;
#use Net::IDN::Encode ':all';
use URI::Split qw(uri_split uri_join);
use HTML::Strip;
use HTML::Clean;
use Time::HiRes qw( time sleep );
use Try::Tiny; # on Debian/Ubuntu package libtry-tiny-perl
use Socket;
use Digest::MD5 qw(md5_base64);
use Time::Piece;

use Devel::Size qw(size total_size);


# test for Furl, use LWP as a fallback
my $furl_loaded = 1;
try {
    require Furl;
}
catch {
    $furl_loaded = 0;
}


# IMPORTANT : to avoid possible traps, use the clean_urls python script before this one to filter the list and spare memory (NB: the bash script does so).
# This script is to be used in combination with a language identification system (https://github.com/saffsd/langid.py) normally running as a server on port 9008 : python langid.py -s
# Please adjust the host and port parameters to your configuration (see below).

# NO SHORTENED URLS RESOLUTION ANYMORE IN THIS SCRIPT


## Issues to file : languages to exclude

# TODO :
# hash + undef links that are already processed ?
# hostreduce -> hostsampling with just 1 url ? or 1,2,3,... option ?
# make host sampling external
# program structure
# write files sub ?
# redirection check : http/https
## CC-Inhalt, Quelle ?
## DNS queries auf externe Domains ?
## filter the links ?
# hostname checking option
# add text if hr
# shorter seen urls than the md5 ?
# performance test for marker detection
# improve url seen buffer # url buffer, what for ?
# unicode chars handling in put request
# LWP Curl / HTTP Lite



# command-line options
my ($help, $seen, $hostreduce, $fileprefix, $filesuffix, $links_count, $put_ip, $port, $timeout, $all_links, $raw_size_limit, $clean_size_limit, $markers, $source, $sleep);
usage() if ( @ARGV < 1
	or ! GetOptions ('help|h' => \$help, 'putip|ip=s' => \$put_ip, 'port|p=i' => \$port, 'timeout|t=i' => \$timeout, 'seen=s' => \$seen, 'fileprefix|fp=s' => \$fileprefix, 'filesuffix|fs=s' => \$filesuffix, 'hostreduce|hr' => \$hostreduce, 'all|a' => \$all_links, 'links|l=i' => \$links_count, 'rsl=i' => \$raw_size_limit, 'csl=i' => \$clean_size_limit, 'markers|m' => \$markers, 'source|s=s' => \$source, 'sleep=f' => \$sleep)
	or defined $help
	or (defined $all_links && defined $links_count)
);

sub usage {
	print "Unknown option: @_\n" if ( @_ );
	print "Usage: perl XX.pl [--help|-h] [--putip|-ip] X.X.X.X [--port|-p] [--timeout|-t] [--seen|-s] [--fileprefix|-fp] prefix [--filesuffix|-fs] suffix [--all|-a] [--links|-l] number [--hostreduce|-hr] [--rsl] number [--csl] number\n\n";
	print "putip : ip of the langid server (default: 127.0.0.1)\n";
	print "port : port of the langid server (default: 9008)\n";
	print "timeout : timeout limit for the requests (default: 10)\n";
	print "seen : file containing already seen hostnames\n";
	print "prefix : used to identify the files corresponding to different threads\n";
	print "suffix : all the same\n";
	print "EITHER --all OR a given number of links\n";
	print "hostreduce : keep only the hostname & evt. a random full URL for each hostname\n";
	print "raw and clean size limits : text length before and after HTML stripping (default: 1000 and 500)\n";
	print "markers : expects two directories, 'discourse-markers' and 'temporal-markers' with files following the languages codes\n";
	print "source : indicate the source (printed as is as a column of the output file)\n";
	print "sleep : time between two requests (can be a floating point value)\n\n";
	exit;
}


# INITIALIZING
my $start_time = time();
if (!defined $put_ip) {
	$put_ip = "127.0.0.1";
}
if (!defined $port) {
	$port = 9008;
}
if (!defined $timeout) {
	$timeout = 10;
}
if (!defined $raw_size_limit) {
	$raw_size_limit = 1000;
}
if (!defined $clean_size_limit) {
	$clean_size_limit = 1000;
}
## set alarm accordingly
my $alarm_timeout = 20 + $timeout;

## Agent here
my $agent = "";

## MD5 digest length
my $md5length = 12;	# enough below at least 200 millions of URLs

## Markers
my %discourse_markers;
my %temporal_markers;
my @lcodes = ('da', 'de', 'en', 'es', 'fi', 'fr', 'hu', 'id', 'it', 'nl', 'no', 'pl', 'pt', 'sv', 'tr');

sub open_load_discourse {
	my (@list, %hash);
	my $lcode = shift;
	my $filename = "discourse-markers/" . $lcode;
	open (my $fh, "<", $filename) or die "Cannot open markers file : $!\n";
	while (<$fh>) {
		chomp;
		{ no warnings 'uninitialized';
			if (length($_) > 1) {
				push (@list, $_);
			}
		}
	}
	close($fh);
	@list = grep { ! $hash{ $_ }++ } @list;
	
	return (@list);
}

sub open_load_temporal {
	my (@list, %hash);
	my $lcode = shift;

	my $filename = "temporal-markers/" . $lcode;
	open (my $fh, "<", $filename) or die "Cannot open markers file : $!\n";
	while (<$fh>) {
		chomp;
		{ no warnings 'uninitialized';
			if (length($_) > 1) {
				push (@list, $_);
			}
		}
	}
	close($fh);
	@list = grep { ! $hash{ $_ }++ } @list;
	
	return (@list);
}

if (defined $markers) {
	foreach my $lc (@lcodes) {
		$discourse_markers{$lc} = [ open_load_discourse($lc) ];
		#print $lc . " " . scalar(@{ $discourse_markers{$lc} }) . "\n";
		$temporal_markers{$lc} = [ open_load_temporal($lc) ];
		#print $lc . " " . scalar(@{ $temporal_markers{$lc} }) . "\n";
	}
}

## Most global variables here
my (@urls, %seen, %hostnames, %seen_hostnames, $clean_text, $confidence, $lang, $suspicious, $join, $scheme, $auth, $path, $query, $frag, $furl, $lwp_ua, $body, $final_red, $length_a, $length_b, $wordcount);
my ($ext_uri, $red_uri, $digest, $last_url, $last_red_uri, $last_digest);
my $inner_loop_time = 0;


## Files
### bound to change by command-line option
my $todo = 'LINKS-TODO';
my $done = 'RESULTS-langid'; # may change
my $tocheck = 'LINKS-TO-CHECK';
my $urlseenfile = 'URL-SEEN';
my $urlseen_bufferfile = 'URL-SEEN-BUFFER';
my $urldictfile = 'URL-DICT';
my $urlcouplesfile = 'URL-COUPLES';

my $errfile = 'ERRORS';
open (my $errout, ">>", $errfile) or die "Cannot open ERRORS file : $!\n";

my $logfile = 'LOG';
open (my $log, ">>", $logfile) or die "Cannot open LOG file : $!\n";

if (defined $fileprefix) {
	$todo = $fileprefix . "_" . $todo;
	$done = $fileprefix . "_" . $done; # may change
	$tocheck = $fileprefix . "_" . $tocheck;
	$urlseenfile = $fileprefix . "_" . $urlseenfile;
	$urlseen_bufferfile = $fileprefix . "_" . $urlseen_bufferfile;
	$urldictfile = $fileprefix . "_" . $urldictfile;
	$urlcouplesfile = $fileprefix . "_" . $urlcouplesfile;
}

if (defined $filesuffix) {
	$todo = $todo . "." . $filesuffix;
	$done = $done . "." . $filesuffix; # may change
	$tocheck = $tocheck . "." . $filesuffix;
	$urlseenfile = $urlseenfile . "." . $filesuffix;
	$urlseen_bufferfile = $urlseen_bufferfile . "." . $filesuffix;
	$urldictfile = $urldictfile . "." . $filesuffix;
	$urlcouplesfile = $urlcouplesfile . "." . $filesuffix;
}

# Process the 'seen' file, if there is one
# may be a db some day
if ((defined $seen) && (-e $seen)) {
	open (my $ldone, '<', $seen) or die "Cannot open 'seen hostnames' file : $!\n";
	while (<$ldone>) {
		chomp;
		# expected : first column hash, second one whole url without protocol, rest whatever
		if ($_ =~ m/\t/) {
			my @temp = split ("\t", $_);
			$seen_hostnames{$temp[0]} = ();	# = $temp[1];
		}
		# if it's just a 'simple' list of urls
		## add url parser support
		else {
			trim_url($_);
			$digest = substr(md5_base64($_), 0, $md5length);
			$seen_hostnames{$digest} = ();	# = $_
		}
	}
	close($ldone);
}

# Process the 'todo' file (required)
if (-e $todo) {
	open (my $ltodo, '<', $todo) or die "Cannot open LINKS-TODO file : $!\n";
	my ($last_red_uri, @tempurls);
        # print digests on the go
        open (my $urlbuffer, ">>", $urlseen_bufferfile) or die "Cannot open URL-SEEN-BUFFER file : $!\n";
        # loop (file lines)
	while (<$ltodo>) {
		chomp;
		unless ($_ =~ m/^http/) {
		$_ = "http://" . $_;	# consequence of sparing memory space in the "todo" files
		}

		# url splitting
		## REDIRECT PART DELETED, EXECUTE SPECIALLY DESIGNED SCRIPT BEFORE THIS ONE
		($scheme, $auth, $path, $query, $frag) = uri_split($_);
		next if ($auth !~ m/\./);	# || ($scheme =~ m/^ftp/) : the scheme should be already checked
		$red_uri = $auth;
		#$red_uri =~ s/^www[0-9]?\.//;
		$_ =~ s/^(www)[0-9]+?(\.)/$1$2/;	# remove digits after www
		
		# no https support wanted
		#if ($_ =~ m/^https:\/\//) {
		#	$red_uri = uri_join($scheme, $auth);
		#}

		# without query ? necessary elements might be lacking
		if (defined $query) {
			if ( ($query =~ /page=/) || ($query =~ /p=/) || ($query =~ /id=/) || ($query =~ /category=/) ) {
				$ext_uri = uri_join($scheme, $auth, $path, $query);
			}
			else {
				$ext_uri = uri_join($scheme, $auth, $path);
			}
		}
		else {
			$ext_uri = uri_join($scheme, $auth, $path);
		}
		# spare memory space ?
		trim_url($ext_uri);
		
		## find out if the url has already been stored (do this before in a separate script ?)
		# second part : if the hostname differs just by one last character (??)
		if ( (defined $hostreduce) || (length($ext_uri) == length($auth)+1) ) {
			## sampling : reduction from many urls with the same hostname to hostname & sample (random) url
			# digest used for existence tests to spare memory
			$digest = substr(md5_base64($red_uri), 0, $md5length);
			next if (exists $seen_hostnames{$digest});

			# just for the first URL of the list
			if (defined $last_red_uri) {
				# if the 'hostname' is equal to the last one
				if ($red_uri eq $last_red_uri) {
					push (@tempurls, $ext_uri);
				}
				else {
					## add a random url including the path (to get a better glimpse of the website)
					if (@tempurls) {
						%seen = ();
						@tempurls = grep { ! $seen{ $_ }++ } @tempurls;
						my $rand = int(rand(scalar(@tempurls)));
						my $chosen_url = $tempurls[$rand];
						push (@urls, $chosen_url);
						$hostnames{$last_digest} = $last_red_uri;
                                                print $urlbuffer "$last_digest\n";
							# may not be necessary : the reduced url is the filter
							# my $chosen_digest = substr(md5_base64($chosen_url), 0, $md5length)
							# $hostnames{$chosen_digest}++;
						@tempurls = ();
					}
					else {
						push (@urls, $last_url);
						$hostnames{$last_digest} = $last_red_uri;
                                                print $urlbuffer "$last_digest\n";
					}
				}
			}
			$last_url = $ext_uri;
			$last_red_uri = $red_uri;
			$last_digest = $digest;
		}
		else {
			# whole URL digest, spare memory
			$digest = substr(md5_base64($ext_uri), 0, $md5length);
			unless (exists $seen_hostnames{$digest}) {
				push (@urls, $ext_uri);
				$hostnames{$digest} = ();
                                print $urlbuffer "$digest\n";
			}
		}
	}

	# last URL
	if (defined $hostreduce) {
		$digest = substr(md5_base64($red_uri), 0, $md5length);
		if (defined $last_red_uri) {
			# if the 'hostname' is equal to the last one
			if ($red_uri eq $last_red_uri) {
				unless (exists $seen_hostnames{$digest}) {
					push (@tempurls, $ext_uri);
					%seen = ();
					@tempurls = grep { ! $seen{ $_ }++ } @tempurls;
					my $rand = int(rand(scalar(@tempurls)));
					my $chosen_url = $tempurls[$rand];
					push (@urls, $chosen_url);
					$hostnames{$last_digest} = $last_red_uri;
					@tempurls = ();
				}
			}
			else {
				unless (exists $seen_hostnames{$last_digest}) {
					push (@urls, $last_url);
					$hostnames{$last_digest} = $last_red_uri;
                                        print $urlbuffer "$last_digest\n";
				}
				unless (exists $seen_hostnames{$digest}) {
					push (@urls, $ext_uri);
					$hostnames{$digest} = $red_uri;
                                        print $urlbuffer "$digest\n";
				}
			}
		}
	}

        print "todo file loaded\n";
        close($urlbuffer);
	close($ltodo);
}
else {
	die 'No to-do list found under this file name: ' . $todo;
}

# empty list case
die 'empty list' if (scalar(@urls) == 0);

# clear the hashes
%seen = ();
@urls = grep { ! $seen{ $_ }++ } @urls;
die 'not enough links in the list, try --all ?' if ((defined $links_count) && (scalar(@urls) < $links_count));



## FURL init. with switch
if ($furl_loaded == 1) {
	$furl = Furl::HTTP->new(
        	agent   => $agent,
        	timeout => $timeout,
	);
}

## LWP init.
my ($req, $res);
$lwp_ua = LWP::UserAgent->new; # another possibility : my $lwp_ua = LWPx::ParanoidAgent->new;
my $can_accept = HTTP::Message::decodable;
$lwp_ua->agent($agent);
$lwp_ua->timeout($timeout);


# MAIN LOOP

my ($tried_urls, $visits, $successes, $suspcount, $skip, $errors, $dropped) = (0) x 7;

open (my $out_fh, '>>', $done) or die "Cannot open RESULTS file : $!\n";
open (my $check_again_fh, '>>', $tocheck) or die "Cannot open TO-CHECK file : $!\n";
open (my $urldict, '>>', $urldictfile) or die "Cannot open URL-DICT file : $!\n";
open (my $urlcouples, '>>', $urlcouplesfile) or die "Cannot open URL-COUPLES file : $!\n";
open (my $seenfh, '>>', $urlseenfile) or die "Cannot open URL-SEEN file : $!\n"; # was buffer_file

# print the hostnames hash in a temporary buffer to clear the values from memory
#while ( my ($j, $k) = each %hostnames ) {
#	{ no warnings 'uninitialized';
#		print $urlbuffer "$j\t$k\n";
#	}
#}
#while ( my ($j, $k) = each %hostnames ) {
#	{ no warnings 'uninitialized';
#		$hostnames{$k} = ();
#	}
#}


## MAIN  instructions

foreach my $loopvar (1 .. scalar(@urls)) {
#foreach my $url (@urls) {
	# end the loop if the given number of urls was reached
	if (defined $links_count) {
		last if ($tried_urls == $links_count);
	}
	# end the loop if there is no server available
	last if ($skip == 1);

	# try to fetch and to send the page
        my $url = shift @urls;

	process_url($url);
        print $loopvar . "\t" . total_size(\@urls) . "\t" . total_size(\%seen_hostnames) . "\t" . total_size(\%hostnames) . "\t" . total_size(\%seen) . "\n";
}


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

# URL processing subroutine
sub process_url {
	my $sub_url = shift;
	lock_and_write($log, $sub_url, $logfile);
	try {
		fetch_url($sub_url);
	}
	catch {
		if ($_ =~ m/no server/) {
			$skip = 1;
			return;
		}
		# catch and print all types of errors
		else {
			$_ =~ s/ at .+?\.$//;
			lock_and_write($errout, $_, $errfile);
                        # $errors++;
		}
	};
	return;
}


# Necessary if there are several threads
sub lock_and_write {
	# ERRORS FILE ONLY ?
	my ($fh, $text, $filetype) = @_;
	chomp ($text);
	# http://perldoc.perl.org/functions/flock.html
	flock($fh, LOCK_EX) or die "Cannot lock " . $filetype . " file : $!\n";
	# in case something appended while we were waiting...
	seek($fh, 0, SEEK_END) or die "Cannot seek " . $filetype . " file : $!\n";
	print $fh $text . "\n" or die "Cannot write to " . $filetype . " file : $!\n";
	flock($fh, LOCK_UN) or die "Cannot unlock " . $filetype . " file : $!\n";
	return;
}


## PUT request subroutine
my ($code, $put_response);
sub put_request {
	my $text = shift;
	my ( $minor_version, $sub_code, $msg, $headers, $response );
	if ($furl_loaded == 1) {
		( $minor_version, $sub_code, $msg, $headers, $response ) = $furl->request(
			method  => 'PUT',
			host    => $put_ip,
			port    => $port,
			path_query => 'detect',
			content	=> $text,
		);
	}
	else {
		my $sendreq = HTTP::Request->new('PUT', 'http://' . $put_ip . ':' . $port . '/detect', undef, $clean_text );
		my $resp = $lwp_ua->request($sendreq);

		if ($resp->is_success) {
			$response = $resp->decoded_content(charset => 'none');
			$sub_code = 200;
		}
		else {
			$sub_code = 500;
		}
	}
	return ( $sub_code, $response );
}


# fetch and send URL
sub fetch_url {
	my $finaluri = shift;
	$tried_urls++;
	unless ($finaluri =~ m/^http/) {
		$finaluri = "http://" . $finaluri; # consequence of sparing memory space
	}
	#($scheme, $auth, $path, $query, $frag) = uri_split($finaluri);

	# time process
	## http://stackoverflow.com/questions/1165316/how-can-i-limit-the-time-spent-in-a-specific-section-of-a-perl-script
	## http://stackoverflow.com/questions/3427401/perl-make-script-timeout-after-x-number-of-seconds
	try {
	local $SIG{ALRM} = sub { die "TIMEOUT\n" };
	alarm $alarm_timeout;

	# download, strip and put
	$req = HTTP::Request->new(GET => $finaluri);
	$req->header(
			'Accept' => 'text/html',
			'Accept-Encoding' => $can_accept,
		);
	# send request
  	$res = $lwp_ua->request($req);
	if ($res->is_success) {
		$visits++;

                # SLEEP HERE
                if (defined $sleep) {
                    unless ($inner_loop_time == 0) {
                        # measure elapsed time
                        my $sleep_correction = time() - $inner_loop_time;
                        print "sleep correction:\t" . $sleep_correction . "\n";

                        # apply correction
                        if ($sleep_correction < $sleep) {
                            sleep($sleep - $sleep_correction);
                        }
                        $inner_loop_time = time();
                    }
                    else {
                        $inner_loop_time = time();
                        sleep($sleep);
                    }
                }

		# check if the request was redirected to a URL that has already been seen
		$final_red = $res->request()->uri();
		($scheme, $auth, $path, $query, $frag) = uri_split($final_red);
		my $final_ext = uri_join($scheme, $auth, $path);
		$final_ext =~ s/\/$//;		# avoid duplicates like www.mestys-starec.eu and www.mestys-starec.eu/
		$final_ext =~ s/^http:\/\///;		# remove protocol
		$final_ext =~ s/^https:\/\///;	# remove protocol
		# $final_ext =~  s/^www[0-9]?\.//;
		
		if (defined $hostreduce) {
			# use shortened hostname
			my $final_hostname = $auth;
			$final_hostname =~ s/^www[0-9]?\.//;
			$digest = substr(md5_base64($final_hostname), 0, $md5length);
		}
		else {
			# use shortened whole URL
			$digest = substr(md5_base64($final_ext), 0, $md5length);
		}

		if (exists $seen_hostnames{$digest}) {
			alarm 0;
                        $dropped++;
			die "Dropped (redirect in the 'seen' file):\t" . $finaluri;
		}


		if (! exists $hostnames{$digest}) {
			print "Just saw a new redirect:\t" . $final_red . "\n";
		}
		# store hostname or full redirect according to the options
		$seen_hostnames{$digest} = ();
                print $seenfh $digest . "\n";

		# big problem here
		#else {
		#	alarm 0;
		#	die "Dropped (redirect already seen):\t" . $finaluri;
		#}

		# check the size of the page (to avoid a memory overflow)
		my $testheaders = $res->headers;
		if ($testheaders->content_length) {
			if ($testheaders->content_length > 1000000) { # was 500000, too low
				alarm 0;
                                $dropped++;
				die "Dropped (by content-size):\t" . $finaluri;
			}
		}
		$body = $res->decoded_content(charset => 'none');
		$length_a = length($body);

		{ no warnings 'uninitialized';
			# user-defined raw text size
			if ($length_a < $raw_size_limit) {
				alarm 0;
                                $dropped++;
				die "Dropped (by html size):\t\t" . $finaluri;
			}
			my $h = new HTML::Clean(\$body);

			# $h->strip();
                        $h->strip({whitespace => 0});
			my $data = $h->data();

			my $hs = HTML::Strip->new();
			$clean_text = $hs->parse( $$data );
			$hs->eof;

			$length_b = length($clean_text);
			# user-defined clean text size
			if ($length_b < $clean_size_limit) {
				alarm 0;
                                $dropped++;
				die "Dropped (by clean size):\t" . $finaluri;
			}
		}
	}
	else {
		alarm 0;
                $errors++;
		die "Dropped (no response):\t\t" . $finaluri;
	}
	} # end of try
	catch {
		if ($_ eq "TIMEOUT\n") {
			alarm 0;
			die "Handling timeout problem:\t" . $finaluri;
		}
		else {
			die $_;
		}
	};
	alarm 0;
	#return $clean_text;
#}

#sub langid {
	#my ($text, $finaluri) = @_;
	my $text = $clean_text; # should be changed
	my $tries = 0;
	$code = 0;
	until ( ($code == 200) || ($tries >= 5) ) {
		if ($tries > 0) {
			sleep(0.5);
			#print "thread " . $filesuffix . " tries for the " . $tries . "time\n";
		}
		# Furl + LWP switch on
		# WIDESTRING ERROR if no re-encoding, but re-encoding may break langid
		# my $text3 = utf8::upgrade( $text ); # utf8::encode
		try {
			( $code, $put_response ) = put_request($text);
		}
		catch {
			$text = encode('UTF-8', $text);
			try {
				( $code, $put_response ) = put_request($text);
			}
			catch {
				alarm 0; # not necessary ?
				die "langid error: $@" . ", url:\t" . $finaluri;
			};
		};
		$tries++;
	}

	if ($code == 500) {
		# Make sure the langid server is really down (may still be an issue with multi-threading)
		print "no langid server available\n";
		alarm 0;
		die "no server";
	}
	elsif ($code == 200) {
		$suspicious = 0;
		$put_response =~ m/"confidence": (.+?), "language": "([a-z]+?)"/;
		$confidence = $1;
		$lang = $2;

		# problems with encoding changes, these codes can also be bg, ja, ru, etc.
		if ($confidence < 0.5) {
			$suspicious = 1;
		}
		# latin, amharic, etc. : too rare to be plausible
		elsif ( ($lang eq "la") || ($lang eq "lo") || ($lang eq "an") || ($lang eq "am") || ($lang eq "kw") ) {
			$suspicious = 1;
		}
		elsif ( ($lang eq "zh") || ($lang eq "qu") || ($lang eq "ps") ) {
		# sadly, it has to be that way...
			# Russian
			if ($auth =~ m/\.ru$/) {
				$lang = "ru";
				$confidence = "0.111"
			}
			# Japanese
			elsif ($auth =~ m/\.jp$/) {
				$lang = "ja";
				$confidence = "0.111"
			}
			# Korean
			elsif ($auth =~ m/\.kr$/) {
				$lang = "ko";
				$confidence = "0.111"
			}
			# Chinese : the real one...
			elsif ($auth =~ m/\.cn$/) {
				$suspicious = 0;
			}
			# Others ? ua, bg, kz, belarus, etc. ?
			else {
				$suspicious = 1;
			}
		}
		# Greek
		elsif ( ($lang eq "el") && ($auth !~ m/\.gr$/) && ($confidence != 1) ) {
			$suspicious = 1;
		}
		# Luxemburgish (too rare to be true)
		elsif ( ($lang eq "lb") && ($auth !~ m/\.lu$/) ) {
			$suspicious = 1;
		}

		# round the confidence
		unless ($confidence eq "1.0") {
			$confidence = sprintf ("%.3f", $confidence);
		}
		else {
			$confidence = "1";
		}


		## INFOS (section recently added)
		# digest
		my $final_digest = substr(md5_base64($final_red), 0, $md5length);
		if ($final_red eq $finaluri) {
			print $urldict $final_digest . "\t" . $final_red . "\t0\n";
		}
		else {
			print $urldict $final_digest . "\t" . $final_red . "\t" . $finaluri . "\n";
		}

		# HTTP last-modified
		my $httplast;
		if ($res->header( 'last-modified' )) {
			my $timexp = $res->header( 'last-modified' );
			# try to parse the date
			$timexp =~ s/,//;
			my $time;
			try {
				if ($timexp =~ m/GMT|UTC/) {
					# UTC workaround
					if ($timexp =~ "UTC") {
						$timexp =~ s/UTC/GMT/;
					}
					$time = Time::Piece->strptime($timexp, '%a %d %b %Y %H:%M:%S %Z');
					}
				else {
					$time = Time::Piece->strptime($timexp, '%a %d %b %Y %H:%M:%S %z');
				}
				my $timestamp = $time->strftime('%s');
				$httplast = $timestamp;
			}
			# default if parsing fails
			catch {
				$httplast =~ s/\t+/ /g;
				$httplast = "! " . $httplast;
			}
		}
		# default if no date
		else {
			$httplast = "0";
		}

		# domain name
		my $uri = URI->new( $final_red );
		my $domain = $uri->host;
		my $domain_short;
		# try short name
		if ($domain =~ m/[a-z]+\.[a-z]+\/?$/) {
			$domain_short = $&;
		}
		
		# IPs
		my (@addresses, $dnsflag);
		if ($domain_short) {
			try {
				@addresses = gethostbyname($domain_short) or die;
				@addresses = map { inet_ntoa($_) } @addresses[4 .. $#addresses];
				$dnsflag = 1;
			}
			catch {
				@addresses = gethostbyname($domain) or print "Can't resolve $domain: $!\n";
				@addresses = map { inet_ntoa($_) } @addresses[4 .. $#addresses];
			}
		}
		else {
			@addresses = gethostbyname($domain) or print "Can't resolve $domain: $!\n";
			@addresses = map { inet_ntoa($_) } @addresses[4 .. $#addresses];
		}
		# result of the test : determine which version of the domain name to store
		my $domainmem;
		if ( ($dnsflag) && ($dnsflag == 1) ) {
			$domainmem = $domain_short;
		}
		else {
			$domainmem = $domain;
		}

		# parse the links of the page
		my (@inlinks, @outlinks);
		while ( $body =~ m/href="(https?:\/\/.+?)"/g ) {
			my $testurl = $1;
			# https
			$testurl =~ s/^https/http/;
			# basic media filter
			## extensions
			if ($testurl !~ m/\.atom$|\.json$|\.css$|\.xml$|\.js$|\.jpg$|\.jpeg$|\.png$|\.gif$|\.tiff$|\.pdf$|\.ogg$|\.mp3$|\.m4a$|\.aac$|\.avi$|\.mp4$|\.mov$|\.webm$|\.flv$|\.ico$|\.pls$|\.zip$|\.tar$|\.gz$|\.iso$|\.swf$/io) {
			## not wanted
			if ($testurl !~ m/^http:\/\/add?s?\.|^http:\/\/banner\.|doubleclick|tradedoubler\.com|livestream|live\.|videos?\.|feed$|rss$/io) {
			## frequent hostnames with nearly no text
			if ($testurl !~ m/last\.fm|soundcloud\.com|youtube\.com|youtu\.be|vimeo\.com|instagr\.am|instagram\.com|imgur\.com|flickr\.com|google\.|twitter\.com|twitpic\.com|gravatar\.com|akamai\.net|amazon\.com|cloudfront\.com/io) {
			## media queries
			if ($testurl !~ m/\.jpg[&?]|\.jpeg[&?]|\.png[&?]|\.gif[&?]|\.pdf[&?]|\.ogg[&?]|\.mp3[&?]|\.avi[&?]|\.mp4[&?]/io) {
			## (basic) adult spam filter
			# if ( ($testurl !~ m/[\.\/]sex|[\.\/-](adult|porno?|cash|xxx|fuck)/io) && ($testurl !~ m/(sex|adult|porno?|cams|cash|xxx|fuck)[\.\/-]/io) && ($testurl !~ m/gangbang|incest/io) && ($testurl !~ m/[\.\/-](ass|sex)[\.\/-]/io) ) {

				# find the outlinks
				$uri = URI->new( $testurl );
				$domain = $uri->host;
				if ($domain =~ m/[a-z]+\.[a-z]+\/?$/) {
					$domain = $&;
				}
				# print $domain . "\t" . $domainmem . "\t" . $auth . "\n";
				# store the links in two categories
				if ($domainmem eq $domain) {
					push (@inlinks, $testurl);
				}
				else {
					push (@outlinks, $testurl);
				}
			}}}}#}
		}
		# uniq
		%seen = ();
		@inlinks = grep { ! $seen{ $_ }++ } @inlinks;
		%seen = ();
		@outlinks = grep { ! $seen{ $_ }++ } @outlinks;
		# hash the links and add them to the dictionary : filter them before ?
		foreach my $inlink (@outlinks) {
			print $urldict substr(md5_base64($inlink), 0, $md5length) . "\t" .  $inlink . "\t0\n";
		}
		foreach my $outlink (@outlinks) {
			my $tempoutdig = substr(md5_base64($outlink), 0, $md5length);
			print $urldict $tempoutdig . "\t" .  $outlink . "\t0\n";
			print $urlcouples $final_digest . "\t" . $tempoutdig . "\n";
		}

		# number of words (approximation)
		## use feature 'unicode_strings'; not before Perl 5.12
		## unicode flag, does not work before Perl 5.14 : my $nwords = () = $clean_text =~ /\w+ /giu;
		# my $nwords = () = $clean_text =~ /\p{L}+ |\p{L}+\p{P}|\p{L}+$/gi;
		my $nwords = () = $clean_text =~ /\b\p{L}+\b|\b\p{L}+\p{P}\b/gi;
		my $nwords_u;
		try {
		    ## Unicode version (Perl 5.14 minimum): $nwords_u = () = $clean_text =~ /\w+\b/giu;
			$nwords_u = () = $clean_text =~ /\w+\b/gi;
		}
		catch {
			$nwords_u = "0";
		}

		# markers in the text
		my ($discourse_score, $temporal_score, $testscore, $testu, $discourse);
		if (defined $markers) {
			$discourse = 0;
			if (exists $discourse_markers{$lang}) {
				foreach my $testword (@{ $discourse_markers{$lang} }) {
					# regex matching
					$discourse += () = $clean_text =~ /\b${testword}\b/gi;
					# combined regex
					#my $testcomb .= join("|", @{ $discourse_markers{$lang} });
					#$testscore = () = $clean_text =~ /\b(${testcomb})\b/gi;
					#$testcomb =~ s/ //g;
					#$testu = () = $clean_text =~ /\b(${testcomb})\b/giu;
				}
				$discourse_score = sprintf "%.3f", (($discourse/$nwords)*100);
			}
			else {
				$discourse_score = "0";
			}

			my $temporal = 0;
			if (exists $temporal_markers{$lang}) {
				foreach my $testword (@{ $temporal_markers{$lang} }) {
					# regex matching
					$temporal += () = $clean_text =~ /\b${testword}\b/gi;
				}
				$temporal_score = sprintf "%.3f", (($temporal/$nwords)*100);
			}
			else {
				$temporal_score = "0";
			}

			# ratio ignoring multi-word expressions
			#print (($discourse/$nwords)*100) . "\t" .  (($testscore/$nwords)*100) . "\t" . (($testu/$nwords)*100) . "\n";
		}
		else {
			$discourse_score = "0";
			$temporal_score = "0";
		}


		# text hash to ensure texts are unique
		my $textdigest = substr(md5_base64($text), 0, $md5length);

                # creative commons test
                my $ccflag = "0";
                if ($body =~ m/creativecommons.org\/licenses\//) {
                    $ccflag = "1";
                }

		# output string
		my $output_result = $final_digest . "\t" . $lang . "\t" . $confidence . "\t" . $length_a . "\t" . $length_b . "\t" . $nwords . "\t" . scalar(@inlinks) . "\t" . scalar(@outlinks) . "\t" . join(",", @addresses) . "\t" . $httplast . "\t" . $discourse_score . "\t" . $temporal_score . "\t" . $textdigest . "\t" . $nwords_u . "\t" . $source . "\t" . $ccflag;
		# . "\t" . $discourse . "\t" . $testscore . "\t" . $testu

		# counters and printers
		if ($suspicious == 1) {
			$suspcount++;
			print $check_again_fh $output_result . "\n";
			#lock_and_write($check_again_fh, $output_result, $tocheck);
		}
		else {
			$successes++;
			print $out_fh $output_result . "\n";
			#lock_and_write($out_fh, $output_result, $done);
		}
	}
	else {
		alarm 0;
		die "Dropped (not found):\t" . $finaluri;
	}

	return;
} # end of subroutine


close($out_fh);
close($check_again_fh);
close($errout);
close($log);



## THE END

# no server found option
#unless ($skip == 1) {
#	splice(@urls, 0, $url_count);
#}

# rest of the todo links (can be 0)
open (my $ltodo, '>', $todo);
print $ltodo join("\n", @urls);
close($ltodo);


# print seen hostnames (corrected hostnames → seen_hostnames)
#while ( my ($j, $k) = each %seen_hostnames ) {
#	#print $seenfh "$j\t$k\n";
#	if (defined $k) {
#		print $urlbuffer "$j\t$k\n";
#	}
#}
# close ($urlbuffer);

open (my $final_buffer, '<', $urlseen_bufferfile);
while (<$final_buffer>) {
    chomp;
    # lock_and_write($seenfh, $_, $urlseenfile)
    print $seenfh "$_\n";
}

close ($final_buffer);
close($seenfh);


# Print infos
if (defined $filesuffix) {
	print "### thread number:\t" . $filesuffix . "\n";
}
print "## END of processing\n";
print "tried:\t\t" . $tried_urls . "\n";
print "visited:\t" . $visits . "\n";
print "errors:\t\t" . $errors . "\n";
print "----------\n";
print "positive:\t" . $successes . "\n";
print "suspicious:\t" . $suspcount . "\n";
print "dropped:\t" . $dropped . "\n";
print "----------\n";
my $total_time = time() - $start_time;
print "exec. time:\t" . sprintf("%.2f\n", $total_time);
print "secs per try:\t" . sprintf("%.2f\n", ( $total_time / $visits ));
print "secs per pos.:\t" . sprintf("%.2f\n", ( $total_time / $successes ));
