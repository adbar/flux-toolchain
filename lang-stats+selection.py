#!/usr/bin/python


###	This script is part of the FLUX Toolchain project (https://github.com/adbar/flux-toolchain).
###	Copyright (C) Adrien Barbaresi, 2014.
###	The FLUX Toolchain is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

# This script is to be used with the output of a language identification system (https://github.com/saffsd/langid.py).


from __future__ import division
from __future__ import print_function
from collections import defaultdict
import optparse
import sys
import random


## Parse arguments and options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')

parser.add_option('-l', '--language-codes', dest="lcodes", help="comma-separated language codes (in order to output the corresponding links)")
parser.add_option("-i", "--input-file", dest="inputfile", help="input file name", metavar="FILE")
parser.add_option("-o", "--output-file", dest="outputfile", help="output file name (default : output to STDOUT)", metavar="FILE")
parser.add_option("-w", "--wiki-friendly", dest="wikifriendly", default=False, action="store_true", help="wiki-friendly output (table format)")
parser.add_option("-d", "--dictionary", dest="dictionary", help="name of the dictionary file", metavar="FILE")
parser.add_option("-s", "--sample", dest="sample", help="number of sample urls of the chosen language-codes")
# parser.add_option("-p", "--path", dest="path", help="path to the files")

options, args = parser.parse_args()

if options.inputfile is None:
	parser.error('No input file given (-h or --help for more information)')

if options.sample is not None:
	if options.lcodes is None:
		parser.error('Language-codes are required for sampling')
	if options.dictionary is None:
		parser.error('Dictionary file required for sampling')
	samplesize = int(options.sample)


## Initialize
langd, urld, intd = (defaultdict(int) for i in range(3))
codes, ipdict, presample, sample = (dict() for i in range(4))


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

if options.lcodes is not None:
	langlist = options.lcodes.split(',')
	for lc in langlist:
		if lc not in codes:
			print ('Warning : unknown language code: ', lc)
			#print ('Currently supported language codes: ', sorted(lcodes.keys()))
			#sys.exit()


try:
	infh = open(options.inputfile, 'r')
except IOError:
	sys.exit("could not open input file")


## Parse input file
for line in infh:
	columns = line.split('\t')
	if len(columns) > 3:
		## expects the language codes to be in the second column and URL-id to be in the first one
		if columns[0] not in urld:
			langd[columns[1]] += 1
			urld[columns[0]] = columns[1]
			
			if options.lcodes is not None:
				#marker += 1
				intd[columns[0]] = columns[2].rstrip()

			# store IPs for a better sampling
			if options.sample is not None:
				ipdict[columns[0]] = columns[8]

infh.close()


# Display and print the results
if options.sample is None:
	if options.wikifriendly is False:
		print (len(urld), 'total unique urls')
		print ('-Language-\t', '-Code-', '-Docs-', '-%-', sep='\t')
	else:
		print ('|   ', len(urld), 'total unique urls   ||||')
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


# Print the selected results (-l option) and eventually save them in a file (-o option) and/or sample them (-s option)
if options.lcodes is not None:
	# open output file
	if options.outputfile is not None:
		try:
			out = open(options.outputfile, 'w')
		except IOError:
			sys.exit("could not open output file")

	# load url hashes dictionary
	if options.dictionary is not None:
		try:
			dictfh = open(options.dictionary, 'r')
		except IOError:
			sys.exit("could not open dictionary file")
		hashd = dict()
		for line in dictfh:
			columns = line.split('\t')
			hashd[columns[0]] = columns[1]
		dictfh.close()

	# iterate
	for lang in langlist:
		for key in urld:
			if urld[key] == lang:
				# lc option
				if urld[key] in codes:
					code = codes[urld[key]]
				else:
					code = urld[key]
				# dict option
				if options.dictionary is not None:
					firstinfo = hashd[key]
				else:
					firstinfo = key
				# sampling option
				# presample necessary if there are several languages in the selection (alternative solution : the size is in langd)
				if options.sample is not None:
					#try:
						if ipdict[key] not in presample:
							presample[key] = hashd[key] # was presample[ipdict[key]]
						else:
							# ensure pseudo-randomness, and not only alphabetical sorting biases
							if random.random() > 0.5:
								presample[key] = hashd[key] # was presample[ipdict[key]]
					#except KeyError:
					#	print (key, ipdict[key])
				else:
					if options.outputfile is not None:
						out.write(firstinfo + '\n')
					else:
						print (firstinfo)
	# print the sample
	if options.sample is not None:
		# ensure the dictionary is long enough
		if len(presample) >= samplesize:
			for key in random.sample(presample.keys(), samplesize):
				sample[presample[key]] = key
		else:
			print ('Warning : sample size too high (', samplesize, '), taking all URLs instead (', len(presample), ')')
			sample = presample.copy()
		# iterate through the sample
		for key in sample.keys():
			if options.outputfile is not None:
				out.write(sample[key] + '\t' + key + '\n')
			else:
				print (sample[key], key, sep='\t')

	if options.outputfile is not None:	
		out.close()
