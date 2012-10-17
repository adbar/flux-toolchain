#!/usr/bin/python


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


from __future__ import print_function
from __future__ import division
from collections import defaultdict
from urlparse import urlparse
import re
import optparse
import sys


# TODO:
## split lines of the kind '.htmlhttp://'
## more banned hostnames (Alexa list)
## english link text



# Parse arguments and options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')
parser.add_option("-i", "--input-file", dest="inputfile", help="input file name", metavar="FILE")
parser.add_option("-o", "--output-file", dest="outputfile", help="output file name", metavar="FILE")
parser.add_option("-l", "--spamlist-file", dest="spamlistfile", help="name of the spamlist file (containing domain names)", metavar="FILE")
parser.add_option("-s", "--spam-urls-file", dest="spamurls", help="name of the file to write the spam urls", metavar="FILE")

options, args = parser.parse_args()

if options.inputfile is None or options.outputfile is None:
	parser.error('Input AND output file mandatory (-h or --help for more information).')


# Main regexes
protocol = re.compile(r'^http')
hostnames_filter = re.compile(r'last\.fm|soundcloud\.com|youtube\.com|youtu\.be|vimeo\.com|instagr\.am|instagram\.com|imgur\.com/|flickr\.com|google\.|twitter\.com|twitpic\.com', re.IGNORECASE)
mediafinal = re.compile(r'\.jpg$|\.jpeg$|\.png$|\.gif$|\.pdf$|\.ogg$|\.mp3$|\.avi$|\.mp4$|\.css$', re.IGNORECASE)
notsuited = re.compile(r'^http://add?\.|^http://banner\.|feed$', re.IGNORECASE)
mediaquery = re.compile(r'\.jpg[&?]|\.jpeg[&?]|\.png[&?]|\.gif[&?]|\.pdf[&?]|\.ogg[&?]|\.mp3[&?]|\.avi[&?]|\.mp4[&?]', re.IGNORECASE)


# Open and load spam-list file, if there is one
if options.spamlistfile is not None:
	try:
		spamlistfile = open(options.spamlistfile, 'r')
		spamdict = defaultdict(int)
		# there should be domains names in the file
		for domain in spamlistfile:
			domain = domain.rstrip()
			spamdict[domain] += 1
		spamlistfile.close()
		print('Length of the spam list: {:,}' . format(len(spamdict)))
	except IOError:
		print('Could not open the file containing the spam-list:', options.spamlistfile, '\nThe URLs will not be checked for spam.')
	# fall-back if there is nowhere to write the urls seen as spam
	if options.spamurls is None:
		print('No spam-urls file given, defaulting to "spam-detected-urls".')
		options.spamurls = 'spam-detected-urls'
	try:
		spamurls = open(options.spamurls, 'w')
		sflag = 1
	except IOError:
		print('Could not open or write to the spam-urls file.')
		sflag = 0
else:
	print('No spam-list given, the URLs will not be checked for spam.')


# Open source and destination files
try:
	sourcefile = open(options.inputfile, 'r')
except IOError:
	sys.exit("Could not open the input file.")
try:
	destfile = open(options.outputfile, 'w')
except IOError:
	sys.exit("Could not open or write to the output file.")


# MAIN LOOP
total_urls = 0
dropped_urls = 0
for candidate in sourcefile:
	total_urls += 1
	candidate = candidate.rstrip()
	# regexes tests : a bit heavy...
	## check HTTP and length
	if protocol.search(candidate) and len(candidate) > 10:
		## http://docs.python.org/library/stdtypes.html#boolean-operations-and-or-not
		if not hostnames_filter.search(candidate) and not mediafinal.search(candidate) and not notsuited.search(candidate) and not mediaquery.search(candidate):
			# domain spam check
			domain = urlparse(candidate).netloc
			if domain not in spamdict:
				destfile.write(candidate + "\n")
			else:
				spamurls.write(candidate + "\n")
				dropped_urls += 1
		else:
			dropped_urls += 1


# close files
if sflag == 1:
	spamurls.close()
sourcefile.close()
destfile.close()

# print final results
## http://docs.python.org/library/string.html#format-specification-mini-language
print('Total URLs seen: {:,}' . format(total_urls))
print('Total URLs dropped: {:,}' . format(dropped_urls))
print('Ratio: {0:.2f}' . format((dropped_urls/total_urls)*100), '%')