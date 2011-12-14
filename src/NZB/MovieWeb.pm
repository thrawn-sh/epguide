#!/usr/bin/perl -w

package NZB::MovieWeb;

use strict;
use warnings FATAL => 'all';

use Date::Calc qw( Add_Delta_Days Today Week_of_Year );
use LWP::ConnCache;
use WWW::Mechanize;

my $WWW = WWW::Mechanize->new(ssl_opts => { verify_hostname => 0 });
$WWW->agent_alias('Windows IE 6');
$WWW->conn_cache(LWP::ConnCache->new);
$WWW->default_header('Accept-Encoding' => 'deflate,gzip');
$WWW->default_header('Accept-Language' => 'en');

sub getMovieTitles($$$) { #{{{1
	my ($self, $release_weeks, $search_weeks) = @_;

	my @titles;
	my @today = Today();

	for (my $count = 0; $count <= $search_weeks; $count++) {
		my @date         = Add_Delta_Days(@today, ($release_weeks + $count) * -7);
		my ($week,$year) = Week_of_Year(@date);

		my $url = 'http://www.movieweb.com/movies/' . $year . '/week/' . $week;
		$WWW->get($url);

		if (! $WWW->success) {
			print STDERR "Can't retrieve $url: $!";
			next;
		}

		for (split("\n", $WWW->content())) {
			if (/\s+<h4><a[^>]+>([^<]+)<\/a><\/h4>/) {
				my $title = $1;
				push(@titles, $title);
			}
		}
	}

	return \@titles;
} #}}}1

1;
