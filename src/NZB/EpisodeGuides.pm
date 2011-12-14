#!/usr/bin/perl -w

package NZB::EpisodeGuides;

use strict;
use warnings FATAL => 'all';

use Date::Calc qw( Add_Delta_Days Today Date_to_Time );
use LWP::ConnCache;
use WWW::Mechanize;

my $WWW = WWW::Mechanize->new(ssl_opts => { verify_hostname => 0 });
$WWW->agent_alias('Windows IE 6');
$WWW->conn_cache(LWP::ConnCache->new);
$WWW->default_header('Accept-Encoding' => 'deflate,gzip');

sub crawl_series($$$) { #{{{1
	my ($self, $serie, $search_weeks) = @_;

	my @episodes;
	my @today = Today();
	my $nzb_end_date   = Date_to_Time(@today, 0, 0, 0);
	my $nzb_start_date = Date_to_Time(Add_Delta_Days(@today, $search_weeks * -7), 0, 0, 0);

	my $url = 'http://epguides.com/' . $serie . '/';
	$WWW->get($url);

	if (! $WWW->success) {
		print STDERR "Can't retrieve $url: $!";
		return undef;
	}

	for (split("\n", $WWW->content())) {
		if (/\s+(\d{1,2})-(\d{1,2})\s+(?:\S+\s+){0,1}(\d{2}.\w{3}.\d{2})/) {
			my $season   = $1;
			my $episode  = $2;
			my $released = $3;
			$released =~ s# #/#g;
			my @dateparts = split(/\//,$released);
			if ($dateparts[2] < 100) {
				$dateparts[2] += 2000;
			}
			$released = join('/', @dateparts);
			$released = str2time($released);

			if (($nzb_start_date <= $released) && ($released <= $nzb_end_date)) {
				my $episodeID = sprintf("S%02dE%02d", $season, $episode);
				push(@episodes, $episodeID);
			}
		}
	}

	return \@episodes;
} #}}}1

1;
