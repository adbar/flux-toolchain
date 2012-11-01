Filtering and Language-identification for URL Crawling Seeds (FLUCS) a.k.a. FLUX-Toolchain
------------------------------------------------------------------------------------------


The language-identification scripts are to be used with the [langid.py language identification system](https://github.com/saffsd/langid.py).


### [langid.py](https://github.com/saffsd/langid.py) server

The langid.py server can be started as follows :

    python langid.py -s
    python langid.py -s --host=localhost &> langid-log &	# as a background process on localhost


### Check a list of URLs for redirections

Send a HTTP HEAD request to see where the link is going.

    perl resolve-redirects.pl --timeout 10 --all FILE
    perl resolve-redirects.pl -h			# display all the options

Prints a report on STDOUT and creates X files.


### Clean the list of URLs

Removes non-http protocols, images, PDFs, audio and video files, ad banners, feeds and unwanted hostnames like twitter.com, google.something, youtube.com or flickr.com :

    python clean_urls.py -i INPUTFILE -o OUTPUTFILE
    python clean_urls.py -h				# for help

Spam filtering using a list : to be documented.


### Fetch the pages, clean them and send them as a PUT request to the server

This Perl script fetches the webpages of a list, strips the HTML code, sends raw text to a server instance of langid.py and retrieves the answer.
Usage : takes a number of links to analyze as argument. Example (provided there is a list named `LINKS_TODO`) :

    perl fetch+lang-check.pl 200
    perl fetch+lang-check.pl -h		# display all the options

Prints a report on STDOUT and creates X files.

Sampling approach (option --hostreduce) : to be explained.


### Multi-threading

Parallel threads are implemented, the bash script starts several instances of the scripts, merges and saves the results.

Following syntax : filename + number of links to check + number of threads

Resolve redirections :

     bash res-red-threads.sh FILE 100000 10 &> rr.log &

Fetch and send the pages to lang-id :
* Expects the langid-server to run on port 9008.
* Expects the clean_urls.py python script (in order to avoid crawler traps).
* Results already collected can be skipped (not required)

    (bash threads.sh FILE 100000 8 &> fs.log &)		# as a detached background process


### Get statistics and interesting links

The list written by the Perl script can be examined using a Python script which features a summary of the languages concerned (language code, number of links and percentage). It also to gather a selection of links by choosing relevant language codes.

Usage: lang-stats+selection.py [options]

Getting the statistics of a list named `RESULTS_langid` :

    python lang-stats+selection.py --input-file=RESULTS_langid

Getting the statistics as well as a prompt of the languages to select and store them in a file :

    python lang-stats+selection.py -l --input-file=... --output-file=...

Wiki-friendly output : -w option.

