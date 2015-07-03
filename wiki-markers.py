#!/usr/bin/python


###	This script is part of the FLUX Toolchain project (https://github.com/adbar/flux-toolchain).
###	Copyright (C) Adrien Barbaresi, 2014.
###	The FLUX Toolchain is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

from __future__ import print_function
import re
import socket
from urllib2 import Request, urlopen, URLError, quote, unquote
from StringIO import StringIO
import gzip
import time
import optparse
import sys
#import atexit


# parse options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')
parser.add_option("-i", "--input-file", dest="inputfile", help="input file name", metavar="FILE")
parser.add_option("-o", "--output-file", dest="outputfile", help="output file name", metavar="FILE")
parser.add_option('-l', '--language-codes', dest="lcodes", help="comma-separated language codes (in order to output the corresponding links)")
parser.add_option("--separated", dest="separated", action="store_true", default=False, help="print the results separately (one file per language)")
parser.add_option("--suggest", dest="suggest", action="store_true", default=False, help="suggest and explore related words")

options, args = parser.parse_args()

# exit cases
if options.inputfile is None:
	parser.error('No input file given, I need fresh urls (-h or --help for more information)')
if options.separated is False and options.outputfile is None:
	parser.error('No output file given (-h or --help for more information)')

# codes
if options.lcodes is None:
	lcodes = ['da', 'de', 'es', 'fi', 'fr', 'hu', 'id', 'it', 'nl', 'no', 'pl', 'pt', 'sv', 'tr']
else:
	lcodes = options.lcodes.split(',')

##
inputwords = list()
## language codes
problems = ['de', 'tr']


# Open and read source file
try:
	sourcefile = open(options.inputfile, 'r')	# options.inputfile
except IOError:
	sys.exit("could not open the input file")

for line in sourcefile:
	line = line.rstrip('\n')
	inputwords.append(line)
sourcefile.close()

# Open output file if necessary
if options.separated is False:
	try:
		outputfile = open(options.outputfile, 'w')	# options.outputfile
	except IOError:
		sys.exit("could not open the output file")
else:
	pass


### FUNCTIONS

# fetch URL
def req(url):
	req = Request(url)
	req.add_header('Accept-encoding', 'gzip')
	req.add_header('User-agent', 'wikt-markers/0.2')

	try:
		response = urlopen(req, timeout = 10)
	except Exception as e:
		print ("Unclassified error: %r" % e, url)
        	return 'error'

	if response.info().get('Content-Encoding') == 'gzip':
		try:
			buf = StringIO( response.read())
			gzf = gzip.GzipFile(fileobj=buf)
			htmlcode = gzf.read()
		except Exception as e:
			print ("Unclassified error: %r" % e, url)
			return 'error'
	elif response.info().gettype() == 'text/html':
		try:
			htmlcode = response.read()
		except Exception as e:
			print ("Unclassified error: %r" % e)
			return 'error'
	else:
		print ('no gzip or text/html content: ', url)
		return 'error'

	return htmlcode


# Find translations
def findtrans(sourcehtml):
	# for each language
	for code in lcodes:
		translations = list()
		lcoderegex = '<li class="interwiki-' + code + '">'
		# re.compile(r'')
		if code not in problems and re.search(lcoderegex, sourcehtml):
			# init
			url = 'http://' + code + '.wiktionary.org/wiki/' + iw
			html = req(url)
	
			for candidate in re.findall(r'<li><a href="/wiki/[A-Za-z0-9%]+?".+?</li>', html):	
				# filter
				if not re.search (r'<span', candidate):
					# stripping
					candidate = re.sub('<.+?>', '', candidate)
					# , split
					candidates = re.split('[,;]', candidate)

					for w in candidates:
						# cleaning
						w = re.sub('^.+?:', '', w)
						w = re.sub('[+(].+?$', '', w)
						w = w.strip(' ,;.()0123456789')
						# append
						translations.append(w.lower())
			
		secondchance = '<span class="Latn" lang="' + code + '">(.+?)</span>'
		m = re.search(secondchance, sourcehtml)
		if m:
			temp = m.group(1)
			temp = re.sub('<.+?>', '', temp)
			if temp not in translations:
				if options.separated is False:
					temp = temp + " (R)"
				translations.append(temp)

		if len(translations) > 0:
			translations = list(set(translations))
			if options.separated is False:
				outputfile.write(code + ": " + "/".join(translations) + "\n")
			else:
				writefile(code, translations)


# Append to a file
def writefile(filename, listname):
	try:
		out = open(filename, 'w')
	except IOError:
		sys.exit("could not open output file")
	for element in listname:
		if len(element) >= 1:
			out.write(element + "\n")
	out.close()

### END FUNCTIONS


# Main loop
for iw in inputwords:
	url = 'http://en.wiktionary.org/wiki/' + iw
	sourcehtml = req(url)
	if options.separated is False:
		outputfile.write("\n### " + iw + "\n")
	findtrans(sourcehtml)

	# find suggestions :
	if options.suggest is True:
		for suggestion in re.findall(r'<li><a href="/wiki/.+?</li>', sourcehtml):
			m = re.search(r'<a.+?>([A-Za-z ]+)</a>', suggestion)
			if m:
				sword = m.group(1)
				if sword not in inputwords:
					mbis = re.search(r'<a href="([A-Za-z_/-]+?)"', suggestion)
					if mbis:
						compurl = 'http://en.wiktionary.org' + mbis.group(1)
						time.sleep(1)
						sourcehtml = req(compurl)
						if options.separated is False:
							outputfile.write("\n### " + sword + " (S)\n")
						findtrans(sourcehtml)

	# do not hammer the server
	time.sleep(1)


if options.separated is False:
	outputfile.close()
