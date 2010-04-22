#!/usr/bin/perl -w

use strict;
use warnings FATAL => 'all';

use lib '../lib';

use Date::Format;
use Date::Parse;
use File::Basename;
use File::Path;
use NZB::Binsearch;
use NZB::Check;
use NZB::Common;
use WWW::Mechanize::GZip;

my $AGE	    = 50;
my $NZB_DIR = '/tmp/nzbdata';
my $END     = str2time(time2str("%Y-%m-%d", time()));
my $START   = $END - ($AGE * 86400);
my $WWW     = WWW::Mechanize::GZip->new();

my $KEEP_ALL = 1;

$WWW->agent_alias('Windows IE 6');

# list of posters, we don't want nzbs from {{{1
my @blacklist =
(
	'ficken',
);
my %bp = map { $_ => 1 } @blacklist;
#}}}1

# id    = folder name on http://epguides.com/
# query = series names to search for on http://binsearch.info/
# group = newsgroup to search for posts
# min   = minimal size of nzb collection
# max   = maximal size of nzb collection
# hd    = search for x264 or xvid content
my @series = #{{{1
(
  { id => '24',                   query => '24',                       group => 'alt.binaries.multimedia', min =>  350, max =>  500, hd => 0 },
  { id => '24',                   query => '24',                       group => 'alt.binaries.multimedia', min => 1000, max => 1500, hd => 1 },
  { id => 'CSI',                  query => 'CSI',                      group => 'alt.binaries.multimedia', min =>  350, max =>  500, hd => 0 },
  { id => 'CSI',                  query => 'CSI',                      group => 'alt.binaries.multimedia', min => 1000, max => 1500, hd => 1 },
  { id => 'CSIMiami',             query => 'CSI.Miami',                group => 'alt.binaries.multimedia', min =>  350, max =>  500, hd => 0 },
  { id => 'CSIMiami',             query => 'CSI.Miami',                group => 'alt.binaries.multimedia', min => 1000, max => 1500, hd => 1 },
  { id => 'CSINY',                query => 'CSI.New.York',             group => 'alt.binaries.multimedia', min =>  350, max =>  500, hd => 0 },
  { id => 'CSINY',                query => 'CSI.New.York',             group => 'alt.binaries.multimedia', min => 1000, max => 1500, hd => 1 },
  { id => 'NCIS',                 query => 'NCIS',                     group => 'alt.binaries.multimedia', min =>  350, max =>  500, hd => 0 },
  { id => 'NCIS',                 query => 'NCIS',                     group => 'alt.binaries.multimedia', min => 1000, max => 1500, hd => 1 },
  { id => 'StarWarsTheCloneWars', query => 'Star.Wars.The.Clone.Wars', group => 'alt.binaries.multimedia', min =>  200, max =>  300, hd => 0 },
  { id => 'StarWarsTheCloneWars', query => 'Star.Wars.The.Clone.Wars', group => 'alt.binaries.multimedia', min =>  500, max =>  800, hd => 1 },
  { id => 'StargateUniverse',     query => 'Stargate.Universe',        group => 'alt.binaries.multimedia', min =>  350, max =>  500, hd => 0 },
  { id => 'StargateUniverse',     query => 'Stargate.Universe',        group => 'alt.binaries.multimedia', min => 1000, max => 1500, hd => 1 },
); #}}}1

for my $serie (@series) {
	my $url = 'http://epguides.com/' . $serie->{id} . '/';
	$WWW->get($url);
	
	if (! $WWW->success) {
		print  "Can't retrieve $url: $!";
		next;
	}

	for (split("\n", $WWW->content())) {
		if (/\s+(\d{1,2})-(\d{1,2})\s+(?:\S+\s+){0,1}(\d{2}.\w{3}.\d{2})/) {
			my $season   = $1;
			my $episode  = $2;
			my $released = $3;
			$released =~ s# #/#g;
			$released = str2time($released);

			if (($START <= $released) && ($released <= $END)) {
				my $episodeID = sprintf("S%02dE%02d", $season, $episode);
				my @nzbs = NZB::Binsearch->searchNZB($serie, $episodeID, $AGE);

				my $file = $NZB_DIR . '/' . $serie->{id} . '/' . $serie->{id} . '_' . $episodeID;
				if ($serie->{hd}) {
					$file .= '-HD';
				}
				$file .= '.nzb';

				mkpath(dirname($file));
				if (! -e $file) {
					for my $nzb (@nzbs) {
						if (NZB::Check->checkNZB($nzb, %bp)) {
							NZB::Binsearch->downloadNZB($nzb, $file);
							last;
						}
					}
				}
			}
		}
	}
}
