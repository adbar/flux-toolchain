#!/usr/bin/perl


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


use strict;
use warnings;
use Getopt::Long;
use Fcntl qw(:flock SEEK_END);
use Encode qw(encode);
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
use String::CRC32; # on Debian/Ubuntu package libstring-crc32-perl

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

# TODO :
# hash + undef links that are already processed ?
# pack crc
# change 'hostnames' name
# hostreduce -> hostsampling with just 1 url ? or 1,2,3,... option ?
# make host sampling external
# program structure
# write files sub ?
# redirection check : http/https


# command-line options
my ($help, $seen, $hostreduce, $wholelist, $fileprefix, $filesuffix, $links_count, $put_ip, $port, $timeout);
usage() if ( @ARGV < 1
	or ! GetOptions ('help|h' => \$help, 'putip|ip=s' => \$put_ip, 'port|p=i' => \$port, 'timeout|t=i' => \$timeout, 'seen|s=s' => \$seen, 'fileprefix|fp=s' => \$fileprefix, 'filesuffix|fs=s' => \$filesuffix, 'hostreduce|hr' => \$hostreduce, 'all|a' => \$wholelist, 'links|l=i' => \$links_count)
	or defined $help
	or (defined $wholelist && defined $links_count)
);

sub usage {
	print "Unknown option: @_\n" if ( @_ );
	print "Usage: perl XX.pl [--help|-h] [--putip|-ip] X.X.X.X [--port|-p] [--timeout|-t] [--seen|-s] [--fileprefix|-fp] prefix [--filesuffix|-fs] suffix [--all|-a] [--links|-l] number [--hostreduce|-hr] \n\n";
	print "putip : ip of the langid server (default : 127.0.0.1)\n";
	print "port : port of the langid server (default : 9008)\n";
	print "timeout : timeout limit for the requests (default: 10)\n";
	print "seen : file containing the urls to skip\n";
	print "prefix : used to identify the files corresponding to different threads\n";
	print "suffix : all the same\n";
	print "EITHER --all OR a given number of links\n";
	print "hostreduce : keep only the hostname & evt. a random full URL for each hostname\n\n";
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
## set alarm accordingly
my $alarm_timeout = 20 + $timeout;

## Agent here
my $agent = "Microblog-Explorer/0.3";

## Most global variables here
my (@urls, %seen, %hostnames, $clean_text, $confidence, $lang, $suspicious, $join, $scheme, $auth, $path, $query, $frag, $crc, $furl, $lwp_ua);

## Files
### bound to change by command-line option
my $todo = 'LINKS-TODO';
my $done = 'RESULTS-langid'; # may change
my $tocheck = 'LINKS-TO-CHECK';

my $errfile = 'ERRORS';
open (my $errout, ">>", $errfile) or die "Cannot open ERRORS file : $!\n";

my $logfile = 'LOG';
open (my $log, ">>", $logfile) or die "Cannot open LOG file : $!\n";

if (defined $fileprefix) {
	$todo = $fileprefix . "_" . $todo;
	$done = $fileprefix . "_" . $done; # may change
	$tocheck = $fileprefix . "_" . $tocheck;
}

if (defined $filesuffix) {
	$todo = $todo . "." . $filesuffix;
	$done = $done . "." . $filesuffix; # may change
	$tocheck = $tocheck . "." . $filesuffix;
}

# Process the 'seen' file, if there is one
if ((defined $seen) && (-e $seen)) {
	open (my $ldone, '<', $seen) or die "Cannot open LINKS-DONE file : $!\n";;
	while (<$ldone>) {
		chomp;
		if ($_ =~ m/\t/) {
			my @temp = split ("\t", $_);
			#$_ =~ s/^http:\/\///;	# spare memory space
			$_ =~ s/\/$//;		# avoid duplicates like www.mestys-starec.eu and www.mestys-starec.eu/
			($scheme, $auth, $path, $query, $frag) = uri_split($_);
			$crc = crc32($auth);
			$hostnames{$crc}++;
			# two possibilities according to the 'host-reduce' option : deleted
		}
		# if it's just a 'simple' list of urls
		else {
			$_ =~ s/\/$//;		# avoid duplicates like www.mestys-starec.eu and www.mestys-starec.eu/
			$crc = crc32($_);
			$hostnames{$crc}++;
		}
	}
	close($ldone);
}

# Process the 'todo' file (required)
if (-e $todo) {
	open (my $ltodo, '<', $todo) or die "Cannot open LINKS-TODO file : $!\n";;
	my ($identifier, @tempurls);
	while (<$ltodo>) {
		chomp;
		unless ($_ =~ m/^http/) {
		$_ = "http://" . $_; # consequence of sparing memory space in the "todo" files
		}

		# url splitting
		## REDIRECT PART DELETED, EXECUTE SPECIALLY DESIGNED SCRIPT BEFORE THIS ONE
		($scheme, $auth, $path, $query, $frag) = uri_split($_);
		next if (($auth !~ m/\./) || ($scheme =~ m/^ftp/));
		my $red_uri;
		if ($_ =~ m/^https:\/\//) {
			$red_uri = uri_join($scheme, $auth);
		}
		else {
			$red_uri = $auth;
		}
		# without query ? necessary elements might be lacking
		my $ext_uri = uri_join($scheme, $auth, $path);
		# spare memory space
		$red_uri =~ s/^http:\/\///;
		$ext_uri =~ s/^http:\/\///;
		
		# find out if the url has already been stored
		## do this before in a separate script ?
		if ( (defined $hostreduce) || (length($ext_uri) == length($auth)+1) ) {
			## sampling : reduction from many urls with the same hostname to hostname & sample (random) url
			if ((defined $identifier) && ($red_uri eq $identifier)) {
				push (@tempurls, $ext_uri);
			}
			else {
				## add a random url including the path (to get a better glimpse of the website)
				if (@tempurls) {
					%seen = ();
					@tempurls = grep { ! $seen{ $_ }++ } @tempurls;
					my $rand = int(rand(scalar(@tempurls)));
					push (@urls, $tempurls[$rand]);
					@tempurls = ();
				}
				$crc = crc32($red_uri); # spare memory
				unless (exists $hostnames{$crc}) {
					push (@urls, $red_uri);
					$hostnames{$crc}++;
					$identifier = $red_uri;
				}
				else {
					$identifier = ();
				}
			}
		}
		else {
			$crc = crc32($ext_uri); # spare memory
			unless (exists $hostnames{$crc}) {
				push (@urls, $ext_uri);
				$hostnames{$crc}++;
			}
		}
	}
	# ? last one ?
	close($ltodo);
}
else {
	die 'No to-do list found under this file name: ' . $todo;
}

%seen = ();
%hostnames = ();
@urls = grep { ! $seen{ $_ }++ } @urls;
die 'not enough links in the list, try --all ?' if ((defined $links_count) && (scalar(@urls) < $links_count));

if ($furl_loaded == 1) {
	$furl = Furl::HTTP->new(
        	agent   => $agent,
        	timeout => $timeout,
	);
}

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

my ($req, $res);
$lwp_ua = LWP::UserAgent->new; # another possibility : my $lwp_ua = LWPx::ParanoidAgent->new;
my $can_accept = HTTP::Message::decodable;
$lwp_ua->agent($agent);
$lwp_ua->timeout($timeout);


# MAIN LOOP

my ($stack, $visits, $i, $suspcount, $skip, $url_count) = (0) x 6;

open (my $out_fh, '>>', $done) or die "Cannot open RESULTS file : $!\n";
open (my $check_again_fh, '>>', $tocheck) or die "Cannot open TO-CHECK file : $!\n";

## this is experimental
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
		}
	};
	return;
}

foreach my $url (@urls) {
	# end the loop if the given number of urls was reached
	if (defined $links_count) {
		last if ($stack == $links_count);
	}
	# end the loop if there is no server available
	last if ($skip == 1);

	# try to fetch and to send the page
	$url_count++;
	process_url($url);
	## undef ?
}


# SUBROUTINES

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

sub fetch_url {
	my $finaluri = shift;
	$stack++;
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
		# check if the request was redirected to a URL that has already been seen
		my $final_red = $res->request()->uri();
		($scheme, $auth, $path, $query, $frag) = uri_split($final_red);
		my $final_short;
		if ($final_red =~ m/^https:\/\//) {
			$final_short = uri_join($scheme, $auth);
		}
		else {
			$final_short = $auth;
		}
		$crc = crc32($final_short);
		if (exists $hostnames{$crc}) {
			alarm 0;
			die "Dropped (redirect already seen):\t" . $finaluri;
		}

		$visits++;
		$crc = crc32($final_red);
		$hostnames{$crc}++;
		# check the size of the page (to avoid a memory overflow)
		my $testheaders = $res->headers;
		if ($testheaders->content_length) {
			if ($testheaders->content_length > 1000000) { # was 500000, too low
				alarm 0;
				die "Dropped (by content-size):\t" . $finaluri;
			}
		}
		my $body = $res->decoded_content(charset => 'none');

		{ no warnings 'uninitialized';
			if (length($body) < 1000) { # was 100, could be another value
				alarm 0;
				die "Dropped (by body size):\t\t" . $finaluri;
			}
			my $h = new HTML::Clean(\$body);
			$h->strip();
			my $data = $h->data();

			my $hs = HTML::Strip->new();
			$clean_text = $hs->parse( $$data );
			$hs->eof;

			if (length($clean_text) < 500) { # was 100, could also be another value
				alarm 0;
				die "Dropped (by clean size):\t" . $finaluri;
			}
		}
	}
	else {
		alarm 0;
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

		my $output_result = $finaluri . "\t" . $lang . "\t" . $confidence;
		if ($suspicious == 1) {
			$suspcount++;
			print $check_again_fh $output_result . "\n";
			#lock_and_write($check_again_fh, $output_result, $tocheck);
		}
		else {
			$i++;
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
unless ($skip == 1) {
	splice(@urls, 0, $url_count);
}
# rest of the todo links (can be 0)
open (my $ltodo, '>', $todo);
print $ltodo join("\n", @urls);
close($ltodo);

# Print infos
if (defined $filesuffix) {
	print "### thread number:\t" . $filesuffix . "\n";
}
print "seen:\t\t" . $url_count . "\n";
print "tried:\t\t" . $stack . "\n";
print "visited:\t" . $visits . "\n";
print "positive:\t" . $i . "\n";
print "suspicious:\t" . $suspcount . "\n";
my $end_time = time();
print "execution time:\t" . sprintf("%.2f\n", $end_time - $start_time);