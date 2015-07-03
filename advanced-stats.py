#!/usr/bin/python


###	This script is part of the FLUX Toolchain project (https://github.com/adbar/flux-toolchain).
###	Copyright (C) Adrien Barbaresi, 2014.
###	The FLUX Toolchain is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


from __future__ import division
from __future__ import print_function
# from collections import defaultdict
import argparse
import sys
import numpy


## TODO:
# keep the most recent one by duplicates


## Parse arguments and options
parser = argparse.ArgumentParser()
parser.add_argument('-i', '--inputfile', dest='inputfile', help='name of the input file', required=True)
parser.add_argument('-l', '--language', dest='language', help='target language', required=True)
args = parser.parse_args()

if len(args.language) != 2:
    parser.error('language code is not 2 characters long')

## Initialize
line_count = 0
page_sum = 0
lengths = list()
words_sum = 0
ipset = set()
hashset = set()


try:
    infh = open(args.inputfile, 'r')
except IOError:
    sys.exit("could not open input file")


## Parse input file
for line in infh:
    columns = line.split('\t')
    if columns[0] not in hashset:
        hashset.add(columns[0])
        line_count += 1
        ## expects the language codes to be in the second column, and so forth
        if str(columns[1]) == str(args.language):
            page_sum += 1
            lengths.append(int(columns[4]))
            words_sum += int(columns[5])
            ipset.add(columns[8])

infh.close()


# Print stats
print ('Lines:', line_count)
print ('Pages:', page_sum, '\t(ratio: {0:.1f}' . format((page_sum/line_count)*100) + ')')
print ('Mean length:', int(numpy.mean(lengths)), '\tmedian:', int(numpy.median(lengths)))
print ('Total words:', words_sum)
print ('IPs:', len(ipset), '\t(ratio: {0:.1f}' . format((len(ipset)/line_count)*100) + ')')




