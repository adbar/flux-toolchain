#!/usr/bin/python


###	This script is part of the FLUX Toolchain project (https://github.com/adbar/flux-toolchain).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


from __future__ import print_function
from __future__ import division
from urlparse import urlparse
import re
import optparse
import sys


# TODO:
## split lines of the kind '.htmlhttp://'
## more banned hostnames (Alexa list)
## english link text
#### spamdict problem
#### check options
# clean <> and {} ?


# Parse arguments and options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')
parser.add_option("-i", "--input-file", dest="inputfile", help="input file name", metavar="FILE")
parser.add_option("-o", "--output-file", dest="outputfile", help="output file name", metavar="FILE")
parser.add_option("-l", "--spamlist-file", dest="spamlistfile", help="name of the spamlist file (containing domain names)", metavar="FILE")
parser.add_option("-s", "--spam-urls-file", dest="spamurls", help="name of the file to write the spam urls", metavar="FILE")
parser.add_option("--adult-filter", dest="adultfilter", default=False, action="store_true", help="basic adult filter (not always useful)")

options, args = parser.parse_args()

if options.inputfile is None or options.outputfile is None:
	parser.error('Input AND output file mandatory (-h or --help for more information).')


# Main regexes : media filters
# avoid getting trapped
protocol = re.compile(r'^http')
extensions = re.compile(r'\.atom$|\.json$|\.css$|\.xml$|\.js$|\.jpg$|\.jpeg$|\.png$|\.gif$|\.tiff$|\.pdf$|\.ogg$|\.mp3$|\.m4a$|\.aac$|\.avi$|\.mp4$|\.mov$|\.webm$|\.flv$|\.ico$|\.pls$|\.zip$|\.tar$|\.gz$|\.iso$|\.swf$', re.IGNORECASE)
notsuited = re.compile(r'^http://add?s?\.|^http://banner\.|doubleclick|tradedoubler\.com|livestream|live\.|videos?\.|feed$|rss$', re.IGNORECASE)
mediaquery = re.compile(r'\.jpg[&?]|\.jpeg[&?]|\.png[&?]|\.gif[&?]|\.pdf[&?]|\.ogg[&?]|\.mp3[&?]|\.avi[&?]|\.mp4[&?]', re.IGNORECASE)
# avoid these websites
hostnames_filter = re.compile(r'last\.fm|soundcloud\.com|youtube\.com|youtu\.be|vimeo\.com|instagr\.am|instagram\.com|imgur\.com|flickr\.com|google\.|twitter\.com|twitpic\.com|gravatar\.com|akamai\.net|amazon\.com|cloudfront\.com', re.IGNORECASE)



# Open and load spam-list file, if there is one
if options.spamlistfile is not None:
	try:
		spamlistfile = open(options.spamlistfile, 'r')
		spamset = set()
		# there should be domains names in the file
		for domain in spamlistfile:
			domain = domain.rstrip()
			spamset.add(domain)
		spamlistfile.close()
		# '{} format' not supported before Python 2.7
		try:
			print('Length of the spam list: {:,}' . format(len(spamset)))
		except ValueError:
			print('Length of the spam list:', len(spamset))
	except IOError:
		print('Could not open the file containing the spam-list:', options.spamlistfile, '\nThe URLs will not be checked for spam.')
else:
	print('No spam-list given, the URLs will not be checked for spam.')
	sflag = 0


# Open source and destination files
try:
	sourcefile = open(options.inputfile, 'r')
except IOError:
	sys.exit("Could not open the input file.")
try:
	destfile = open(options.outputfile, 'w')
except IOError:
	sys.exit("Could not open or write to the output file.")

# fall-back if there is nowhere to write the urls seen as spam
if options.spamurls is None:
	options.spamurls = options.inputfile + '_spam-detected-urls'
	print('No spam-tagged file given, defaulting to', options.spamurls)
try:
	spamurls = open(options.spamurls, 'w')
	sflag = 1
except IOError:
	print('Could not open or write to the spam-urls file.')
	sflag = 0


# MAIN LOOP
total_urls = 0
dropped_urls = 0
for line in sourcefile:
	total_urls += 1
	line = line.rstrip()
	candidates = list()

	# clean the input string
	line = line.replace('[ \t]+', '')
	match = re.search(r'^http.+?(https?://.+?$)', line)
	if match:
		candidates.append(match.group(1))
		match2 = re.search(r'^http.+?(https?://.+?$)', line)
		if match2:
			candidates.append(match2.group(1))
	else:
		candidates.append(line)

	for candidate in candidates:
		passing_test = 1
		# regexes tests : a bit heavy...
		## check HTTP and length
		if not protocol.search(candidate) or len(candidate) < 11:
			passing_test = 0
		else:
			## http://docs.python.org/library/stdtypes.html#boolean-operations-and-or-not
			candidate = candidate.lower()
			## compiled filters
			if hostnames_filter.search(candidate) or extensions.search(candidate) or notsuited.search(candidate) or mediaquery.search(candidate):
				passing_test = 0
			else:
				# https
				candidate = candidate.replace('^https', 'http')				
				# domain spam check
				try:
					if 'spamset' in globals():
						domain = urlparse(candidate).netloc
						if domain in spamset:
							passing_test = 0
				except ValueError:
					passing_test = 0
				## (basic) adult spam filter
				if options.adultfilter is True:
					#if re.search(r'[\./]sex|[\./-](adult|porno?|cash|xxx|fuck)', candidate) or re.search(r'(sex|adult|porno?|cams|cash|xxx|fuck)[\./-]', candidate) or re.search(r'gangbang|incest', candidate) or re.search(r'[\./-](ass|sex)[\./-]', candidate):
					if re.search(r'[\./_-](porno?|xxx)', line.lower()) or re.search(r'(cams|cash|porno?|sex|xxx)[\./_-]', line.lower()) or re.search(r'gangbang|incest', line.lower()) or re.search(r'[\./_-](adult|ass|sex)[\./_-]', line.lower()):
						passing_test = 0
		
		if passing_test == 1:
			destfile.write(candidate + "\n")
		else:
			spamurls.write(candidate + "\n")
			dropped_urls += 1


# close files
if sflag == 1:
	spamurls.close()
sourcefile.close()
destfile.close()

# print final results
## http://docs.python.org/library/string.html#format-specification-mini-language
## '{} format' not supported before Python 2.7
try:
	print('Total URLs seen: {:,}' . format(total_urls))
	print('Total URLs dropped: {:,}' . format(dropped_urls))
	print('Ratio: {0:.2f}' . format((dropped_urls/total_urls)*100), '%')	
except ValueError:
	print('Total URLs seen:', total_urls)
	print('Total URLs dropped:', dropped_urls)
	#print('Total URLs dropped: %d' dropped_urls)
	print('Ratio:', ((dropped_urls/total_urls)*100), '%')
	#print('Ratio: %.02f' ((dropped_urls/total_urls)*100), '%')
