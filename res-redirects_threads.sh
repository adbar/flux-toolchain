#!/bin/bash


###	This script is part of the FLUX Toolchain project (https://github.com/adbar/flux-toolchain).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

# example  : (bash res-red-threads.sh backup_links 500000 10 &> rr.log &)

# TODO:
## advanced divide and conquer and/or URL pool


# create a temporary file
tempfile() {
    tempprefix=$(basename "$0")
    mktemp /tmp/${tempprefix}.XXXXXX
}
TMP1=$(tempfile)
TMP2=$(tempfile)
TMP3=$(tempfile)
trap 'rm -f $TMP1 $TMP2 $TMP3' EXIT


# Parse the options and store the values
if (($# < 3)) || (($# > 4))
then
	echo "Usage : [list of urls] [number of requests] [number of threads] [seen urls file (optional)]"
	exit 1
fi

if (($3 > 50))
then
	echo "No more than 50 threads please."
	exit 1
fi

listfile=$1
req=$2
num_files=$3


# Sort and uniq
echo -e "Total lines in input file : "$(wc -l ${listfile} | cut -d " " -f1)

sort $listfile | uniq > $TMP1

echo -e "Total lines after uniq : "$(wc -l ${TMP1} | cut -d " " -f1)


# Remove the unsafe/unwanted urls
if [ ! -f clean_urls.py ];
then
	echo "File clean_urls.py not found"
	exit 0
fi
if [ ! -f spam-domain-blacklist ];
then
	echo "Spam domains list not found"
	exit 0
fi
python clean_urls.py -i $TMP1 -o cleaned-url-list -l spam-domain-blacklist -s SPAM1
#mv $TMP1 $listfile


# Shuffle the links in the input file
shuf cleaned-url-list -o $TMP2
listfile=$TMP2


# Find a mean number of lines per file
total_lines=$(wc -l ${listfile} | cut -d " " -f1)

if (($req == 0))
then
	((lines_per_file = (total_lines + num_files - 1) / num_files))
else
	if (($req < $total_lines))
	then
		head -${req} ${listfile} > $TMP3
		listfile=$TMP3
		((lines_per_file = (req + num_files - 1) / num_files))
	else
		((lines_per_file = (total_lines + num_files - 1) / num_files))
	fi
fi


# Split the actual file, maintaining lines
## splitting trick found here : http://stackoverflow.com/questions/7764755/unix-how-do-a-split-a-file-into-equal-parts-withour-breaking-the-lines
split -a 2 -d --lines=${lines_per_file} ${listfile} LINKS-TODO.

# Debug information
echo -e "Total lines : ${total_lines}"
echo -e "Lines per file : ${lines_per_file}"

i=0
for f in LINKS-TODO.*
do
	### starting the threads

	# prepend "0" to match split results
	if (($i < 10))
	then
		j="0"$i
	else
		j=$i
	fi

	perl resolve-redirects.pl -t 10 --all --filesuffix $j $f &

	sleep 2
	((i++))
done

wait


# Merge the files
cat LINKS-TODO.* > RED-LINKS-TODO
rm LINKS-TODO.*
cat BAD-HOSTS.* >> BAD-HOSTS
rm BAD-HOSTS.*
cat OTHERS.* >> LINKS-TODO-redchecked
rm OTHERS.*
cat REDIRECTS.* >> LINKS-TODO-redchecked
rm REDIRECTS.*
cat red-ERRORS.* >> red-ERRORS
rm red-ERRORS.*


# Make sure all lines are unique
sort BAD-HOSTS | uniq > $TMP1
mv $TMP1 BAD-HOSTS
sort LINKS-TODO-redchecked | uniq > $TMP1
mv $TMP1 LINKS-TODO-redchecked


# Backup the final result
tar -cjf backup-redirects.tar.bz2 BAD-HOSTS LINKS-TODO-redchecked red-ERRORS RED-LINKS-TODO
