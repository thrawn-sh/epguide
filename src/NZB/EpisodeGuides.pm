#!/usr/bin/perl -w

package NZB::EpisodeGuides;

use strict;
use warnings FATAL => 'all';

use Date::Calc qw( Add_Delta_Days Today Date_to_Time );
use Date::Parse;
use LWP::ConnCache;
use Log::Log4perl qw(:easy);
use WWW::Mechanize;

my $LOGGER = get_logger();

sub new {
	my $class  = shift;
	my %params = @_;

	my $www = WWW::Mechanize->new(ssl_opts => { verify_hostname => 0 });
	$www->agent_alias('Windows IE 6');
	$www->conn_cache(LWP::ConnCache->new);
	$www->default_header('Accept-Encoding' => 'deflate,gzip');
	$www->default_header('Accept-Language' => 'en');

	my $self = {
		www => $www,
	};

	bless $self, $class;
	return $self;
}

sub getEpisodes($$$) { #{{{1
	my ($self, $serie, $search_weeks) = @_;

	my @episodes;
	my @today = Today();
	my $nzb_end_date   = Date_to_Time(@today, 0, 0, 0);
	my $nzb_start_date = Date_to_Time(Add_Delta_Days(@today, $search_weeks * -7), 0, 0, 0);

	my $url = 'http://epguides.com/' . $serie . '/';

	my $www = $self->{'www'};
	$www->get($url);
	if (! $www->success) {
		$LOGGER->error('Can\'t retrieve ' . $url . ': ' . $!);
		return undef;
	}

	for (split("\n", $www->content())) {
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
