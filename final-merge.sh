#!/bin/bash


###	This script is part of the FLUX Toolchain project (https://github.com/adbar/flux-toolchain).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


# create a temporary file
tempfile() {
    tempprefix=$(basename "$0")
    mktemp /tmp/${tempprefix}.XXXXXX
}
TMP1=$(tempfile)
trap 'rm -f $TMP1' EXIT


# RESULTS

find . -type f -name "RESULTS" -exec cat {} >> $TMP1 \;
echo -e "Total results before uniq :\t"$(wc -l ${TMP1} | cut -d " " -f1)


sort $TMP1 | uniq > global-results
echo -e "Total results after uniq :\t"$(wc -l global-results | cut -d " " -f1)


# URL-COUPLES

find . -type f -name "URL-COUPLES" -exec cat {} >> $TMP1 \;
echo -e "Total URL couples before uniq :\t"$(wc -l ${TMP1} | cut -d " " -f1)

sort $TMP1 | uniq > global-url-couples
echo -e "Total URL couples after uniq :\t"$(wc -l global-url-couples | cut -d " " -f1)


# URL-DICT

find . -type f -name "URL-DICT" -exec cat {} >> $TMP1 \;
echo -e "Dictionary size before uniq :\t"$(wc -l ${TMP1} | cut -d " " -f1)

sort $TMP1 | uniq > global-dictionary
echo -e "Dictionary size after uniq :\t"$(wc -l global-dictionary | cut -d " " -f1)


# display statistics if there is a corresponding file
if [ ! -f lang-stats+selection.py ]
then
	python lang-stats+selection.py -i global-results | head -12
fi
