#!/bin/bash


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


# Create a temporary file
tempfile() {
    tempprefix=$(basename "$0")
    mktemp /tmp/${tempprefix}.XXXXXX
}
TMP1=$(tempfile)
trap 'rm -f $TMP1' EXIT


# sort
cut -f1 TO-CHECK | sort | uniq > $TMP1
mv $TMP1 BEING-CHECKED



## http://stackoverflow.com/questions/8314499/read-n-lines-at-a-time-using-bash

# Create new file handle 5
exec 5< BEING-CHECKED

# Now you can use "<&5" to read from this file
while read line1 <&5 ; do
	read line2 <&5

	python langid.py -u $line1 >> CHECKED &
	python langid.py -u $line2 >> CHECKED &
	wait
done

# Close file handle 5
exec 5<&-


# check CHECKED
perl check-dubious.pl

sort CHECKED-FILTERED | uniq >> RESULTS

