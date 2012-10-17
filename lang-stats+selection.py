#!/usr/bin/python


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

# This script is to be used with the output of a language identification system (https://github.com/saffsd/langid.py).


from __future__ import division
from __future__ import print_function
from collections import defaultdict
import optparse
import sys


## Parse arguments and options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')

parser.add_option('-l', '--language-codes', action="store_true", dest="lcodes", default=False, help="prompt for language codes and output of corresponding links")
parser.add_option("-i", "--input-file", dest="inputfile", help="input file name", metavar="FILE")
parser.add_option("-o", "--output-file", dest="outputfile", help="output file name (default : output to STDOUT)", metavar="FILE")
parser.add_option("-w", "--wiki-friendly", action="store_true", dest="wikifriendly", default=False, help="wiki-friendly output (table format)")

options, args = parser.parse_args()

if options.inputfile is None:
	parser.error('No input file given (-h or --help for more information)')

## Initialize
langd = defaultdict(int)
urld = defaultdict(int)
intd = defaultdict(int)
codes = dict()

# Load the language codes dictionary
try:
	langfile = open('ISO_639-1_codes', 'r')
except IOError:
	sys.exit("could not open the file containing the language codes")
# adapted from this source : https://gist.github.com/1262033
for line in langfile:
	columns = line.split(' ')
	codes[columns[0].strip("':")] = columns[1].strip("',\n")
langfile.close()

if options.lcodes is True:
	inp = raw_input('Languages wanted (comma-separated codes) : ')
	langlist = inp.split(',')

try:
	infh = open(options.inputfile, 'r')
except IOError:
	sys.exit("could not open input file")

## Parse input file
for line in infh:
	columns = line.split('\t')
	## two possibilities due to the 'hr' option of the Perl script in the same directory
	if len(columns) == 3 or len(columns) == 4:
		if len(columns) == 3:
			marker = 1
		if len(columns) == 4:
			marker = 2
		if columns[0] not in urld:
			langd[columns[marker]] += 1
			urld[columns[0]] = columns[marker]
			if options.lcodes is True:
				marker += 1
				intd[columns[0]] = columns[marker].rstrip()
infh.close()


# Display and print the results
if options.wikifriendly is False:
	print (len(urld), 'total unique urls')
	print ('-Language-\t', '-Code-', '-Docs-', '-%-', sep='\t')
else:
	print ('|   ', len(urld), 'total unique urls   |||')
	print ('|*Language*\t', '*Code*', '   *Docs*', '   *%*|', sep='|')

for l in sorted(langd, key=langd.get, reverse=True):
	if l in codes:
		code = codes[l]
	else:
		code = l
	if len(code) >= 8:
		code = code + "\t"
	else:
		code = code + "\t\t"
	pcent = (langd[l] / len(urld))*100
	if options.wikifriendly is False:
		print (code, l, langd[l], '%.1f' % round(pcent, 1), sep='\t')
	else:
		print ('|', code, '|  ', l, '  |   ', langd[l], '|   ', '%.1f' % round(pcent, 1), '|')

# Print the selected results in a file (-l option) and eventually save them (-o option)
if options.lcodes is True:
	if options.outputfile is not None:
		try:
			out = open(options.outputfile, 'w')
		except IOError:
			sys.exit("could not open output file")
	for lang in langlist:
		for key in urld:
			if urld[key] == lang:
				if urld[key] in codes:
					code = codes[urld[key]]
				else:
					code = urld[key]
				if options.outputfile is not None:
					out.write(key + '\t' + code + '\t' + urld[key] + '\t' + intd[key] + "\n")
				else:
					print (key, code, urld[key], intd[key], sep='\t')
	if options.outputfile is not None:	
		out.close()