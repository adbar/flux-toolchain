#!/bin/bash


###	This script is part of the FLUX Toolchain project (https://github.com/adbar/flux-toolchain).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

# This script is to be used with the output of a language identification system (https://github.com/saffsd/langid.py).

## example of use:
## (python langid.py -s --host=localhost -l en,cs,de,sk,fr,pl,it,es,ja,nl,ru,he,hu,sl,hr,pt,sv,fi,et,no,lt,da,ro,bs,tr,ar,ka,ca,el,uk,is,bg,lv,vi,sw,sr,eo,nb,ga,eu &> lang-id.log &)
## (bash langcheck_threads.sh list-of-links 50000 6 SOURCE1 &> logfile.log &)
## all links : (bash langcheck_threads.sh list-of-links 0 10 SOURCE1 &> logfile.log &)



#####	RESOLVE THE SHORT URLS BEFORE EXECUTING THIS SCRIPT !

# TODO:
## check URLs to check... and store them in 'RESULTS'
## advanced divide and conquer and/or URL pool
## more than 10 threads
### pool file = one half of the links, if n > 100, take the tenth of the list, export thread number
# url-dict-seen vs. url-dict-done...


if (($# < 4)) || (($# > 5))
then
	echo "Usage : [list of urls] [number of requests] [number of threads] [source] [seen urls file (optional)]"
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
source=$4


# Existing files check
if [ ! -f clean_urls.py ];
then
	echo "File clean_urls.py not found"
	exit 3
fi
if [ ! -f spam-domain-blacklist ];
then
	echo "Spam domains list not found"
	exit 3
fi


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
python clean_urls.py -i $TMP1 -o cleaned-url-list -l spam-domain-blacklist -s SPAM2 --adult-filter
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
split -a 2 -d --lines=${lines_per_file} ${listfile} LINKS-TODO.

# Debug information
echo -e "Total lines : ${total_lines}"
echo -e "Lines per file : ${lines_per_file}"


## starting the threads
i=0
for f in LINKS-TODO.*
do

	# port check
	port="9008"
	if (($i % 3 == 0))
	then
		if nc -vz localhost 9010 &> /dev/null
		then
			port="9010"
		fi
	else
		if (($i % 2 == 0))
		then
			if nc -vz localhost 9009 &> /dev/null
			then
				port="9009"
			fi
		fi
	fi
	

	# prepend "0" to match split results
	if (($i < 10))
	then
		j="0"$i
	else
		j=$i
	fi

	# launch the script
	# rsl = raw-size-limit | csl = clean-size-limit
	if (($# == 5))
	then
		perl fetch+lang-check.pl -t 12 --port $port --seen $5 --hostreduce --all --filesuffix $j --source $source --rsl 1000 --csl 1000 $f &
	else
		perl fetch+lang-check.pl -t 12 --port $port --hostreduce --all --filesuffix $j --source $source --rsl 1000 --csl 1000 $f &
	fi
	sleep 5	# was 2
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
tar -cjf backup.tar.bz2 RESULTS TO-CHECK TODO URL-DICT URL-COUPLES URL-SEEN SPA* *RRORS

# Clean up
rm URL-SEEN-BUFFER.*
# rm BAD-HOSTS ERRORS LINKS-TODO-redchecked LOG RED-LINKS-TODO RESULTS SPAM1 SPAM2 TO-CHECK TODO URL-COUPLES URL-DICT cleaned-url-list fs.log red-ERRORS rr.log URL-SEEN URL-SEEN-BUFFER.*
# rm spam-domain-blacklist
