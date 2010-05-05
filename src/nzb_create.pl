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

my %CFG;
eval `cat $HOME/.ficken` || die "could not slurp in $HOME/.ficken: $!";

my $END     = str2time(time2str("%Y-%m-%d", time()));
my $START   = $END - ($CFG{'age'} * 86400);
my $WWW     = WWW::Mechanize::GZip->new();

$WWW->agent_alias('Windows IE 6');

NZB::Check->debug($CFG{'debug'});
NZB::Check->net_speed($CFG{'speed'});

my %bp = map { $_ => 1 } @{$CFG{'blacklist'}}

for my $serie (@series) {
	my $url = 'http://epguides.com/' . $serie->{'id'} . '/';
	$WWW->get($url);

	if (! $WWW->success) {
		print STDERR "Can't retrieve $url: $!";
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
				my $nzbs_ref = NZB::Binsearch->searchNZB($serie, $episodeID, $CFG{'age'});

				my $file = $CFG{'nzbdir'} . '/' . $serie->{'id'} . '_' . $episodeID;
				if ($serie->{'hd'}) {
					$file .= '-HD';
				}
				$file .= '.nzb';

				if (! -e $file) {
					for my $nzb (@$nzbs_ref) {
						if ($CFG{'debug'}) { print STDERR $serie->{'id'} . ': ' . $episodeID . ($serie->{'hd'} ? '-HD' : '') ."\n"; }
						if (NZB::Check->checkNZB($nzb, %bp)) {
							mkpath(dirname($file));
							NZB::Binsearch->downloadNZB($nzb, $file);
							last;
						}
					}
				}
			}
		}
	}
}
