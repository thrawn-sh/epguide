#!/usr/bin/perl -w

package NZB::MovieWeb;

use strict;
use warnings FATAL => 'all';

use Date::Calc qw( Add_Delta_Days Today Week_of_Year );
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

sub getMovieTitles($$$) { #{{{1
	my ($self, $release_weeks, $search_weeks) = @_;

	my @titles;
	my @today = Today();

	for (my $count = 0; $count <= $search_weeks; $count++) {
		my @date         = Add_Delta_Days(@today, ($release_weeks + $count) * -7);
		my ($week,$year) = Week_of_Year(@date);

		my $url = 'http://www.movieweb.com/movies/' . $year . '/week/' . $week;

		my $www = $self->{'www'};
		$www->get($url);
		if (! $www->success) {
			$LOGGER->warn('Can\'t retrieve ' . $url . ': ' . $!);
			next;
		}

		for (split("\n", $www->content())) {
			if (/\s+<h4><a[^>]+>([^<]+)<\/a><\/h4>/) {
				my $title = $1;
				push(@titles, $title);
			}
		}
	}

	return \@titles;
} #}}}1

1;
