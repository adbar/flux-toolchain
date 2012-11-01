#!/bin/bash


###	This script is part of the FLUX Toolchain project (https://github.com/adbar/flux-toolchain).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

# This script is to be used with the output of a language identification system (https://github.com/saffsd/langid.py).

## example of use:
## (python langid.py -s --host=localhost -l en,cs,de,sk,fr,pl,it,es,ja,nl,ru,he,hu,sl,hr,pt,sv,fi,et,no,lt,da,ro,bs,tr,ar,ka,ca,el,uk,is,bg,lv,vi,sw,sr,eo,nb,ga,eu &> lang-id.log &)
## (bash langcheck_threads.sh list-of-links 50000 6 &> logfile.log &)



#####	RESOLVE THE SHORT URLS BEFORE EXECUTING THIS SCRIPT !

# TODO:
## check URLs to check... and store them in 'RESULTS'
## advanced divide and conquer and/or URL pool
## more than 10 threads
### pool file = one half of the links, if n > 100, take the tenth of the list, export thread number
## test langid-server port
### if nc -vz localhost 9008 &> /dev/null
### then
### echo 'Port is open'
### else
### echo 'Port is closed'
### fi


if (($# < 3)) || (($# > 4))
then
	echo "Usage : [list of urls] [number of requests] [number of threads] [seen urls file (optional)]"
	exit 1
fi

if (($3 > 10))
then
	echo "No more than 10 threads please."
	exit 1
fi

listfile=$1
req=$2
num_files=$3


# Create a temporary file
tempfile() {
    tempprefix=$(basename "$0")
    mktemp /tmp/${tempprefix}.XXXXXX
}
TMP1=$(tempfile)
TMP2=$(tempfile)
trap 'rm -f $TMP1 $TMP2' EXIT


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
python clean_urls.py -i $TMP1 -o cleaned-url-list -l spam-domain-blacklist -s SPAM2
listfile="cleaned-url-list"
#mv $TMP1 $listfile


# Find a mean number of lines per file
total_lines=$(wc -l ${listfile} | cut -d " " -f1)

if (($req == 0))
then
	((lines_per_file = (total_lines + num_files - 1) / num_files))
else
	if (($req < $total_lines))
	then
		head -${req} ${listfile} > $TMP2
		listfile=$TMP2
		((lines_per_file = (req + num_files - 1) / num_files))
	else
		((lines_per_file = (total_lines + num_files - 1) / num_files))
	fi
fi


# Split the actual file, maintaining lines
## splitting trick found here : http://stackoverflow.com/questions/7764755/unix-how-do-a-split-a-file-into-equal-parts-withour-breaking-the-lines
split -a 1 -d --lines=${lines_per_file} ${listfile} LINKS-TODO.

# Debug information
echo -e "Total lines : ${total_lines}"
echo -e "Lines per file : ${lines_per_file}"

i=0
for f in LINKS-TODO.*
do
	### starting the threads
	if (($# == 4))
	then
		perl fetch+lang-check.pl -t 15 --seen $4 --hostreduce --all --filesuffix $i $f &
		#perl fetch-send-furl.pl --port 9009 --seen $4 --hostreduce --all --filesuffix $i $f &
	else
		perl fetch+lang-check.pl -t 15 --hostreduce --all --filesuffix $i $f &
		#perl fetch-send-furl.pl --port 9009 --hostreduce --all --filesuffix $i $f &
	fi
	sleep 2
	((i++))
done

wait


# Merge the files
cat RESULTS-langid.* >> RESULTS
rm RESULTS-langid.*
cat LINKS-TODO.* > TODO
rm LINKS-TODO.*
cat LINKS-TO-CHECK.* >> TO-CHECK
rm LINKS-TO-CHECK.*

cat URL-DICT.* >> URL-DICT
rm URL-DICT.*
cat URL-COUPLES.* >> URL-COUPLES
rm URL-COUPLES.*


# Make sure all lines are unique

sort RESULTS | uniq > $TMP1
mv $TMP1 RESULTS
sort TO-CHECK | uniq > $TMP1
mv $TMP1 TO-CHECK

sort URL-DICT | uniq > $TMP1
mv $TMP1 URL-DICT
sort URL-COUPLES | uniq > $TMP1
mv $TMP1 URL-COUPLES


# problem !!!
#if (( $listfile == "TEMP1" ))
#then
#	tailpart=`expr $total_lines - $req`
#	tail -${tailpart} ${listfile} >> TODO
#	rm TEMP1
#fi

sort TODO | uniq > $TMP1
mv $TMP1 TODO



# Check the dubious URLs


# review links (re-sampling)


# Backup the final result
tar -cjf backup.tar.bz2 RESULTS TO-CHECK TODO URL-DICT URL-COUPLES

