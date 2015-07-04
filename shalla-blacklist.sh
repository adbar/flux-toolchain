#!/bin/bash


###	This script is part of the FLUX Toolchain project (https://github.com/adbar/flux-toolchain).
###	Copyright (C) Adrien Barbaresi, 2012-2015.
###	The FLUX Toolchain is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

### For licensing issues please refer to http://www.shallalist.de/licence.html


tempfile() {
    tempprefix=$(basename "$0")
    mktemp /tmp/${tempprefix}.XXXXXX
}
TMP=$(tempfile)


# download
wget http://www.shallalist.de/Downloads/shallalist.tar.gz

tar -xzf shallalist.tar.gz

# searchengines
rmdirs="BL/aggressive/ BL/alcohol/ BL/automobile/ BL/chat/ BL/education/ BL/finance/ BL/forum/ BL/government/ BL/hobby/ BL/homestyle/ BL/hospitals/ BL/library/ BL/military/ BL/news/ BL/politics/ BL/recreation/ BL/religion/ BL/science/ BL/socialnet/ BL/urlshortener/ BL/weapons/"
for dir in $rmdirs
do
	rm -r $dir
done

# extract and sort
find -name domains | xargs cat >> spam-domain-blacklist

sort -u spam-domain-blacklist > $TMP
mv $TMP spam-domain-blacklist
