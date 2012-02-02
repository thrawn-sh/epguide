#!/usr/bin/perl -w

package NZB::IMDB;

use strict;
use warnings FATAL => 'all';

use Crypt::SSLeay;
use HTML::Entities;
use LWP::ConnCache;
use Log::Log4perl;
use WWW::Mechanize::GZip;

my $LOGGER = Log::Log4perl->get_logger();

sub new {
	my $class  = shift;
	my %params = @_;

	my $www = WWW::Mechanize::GZip->new(autocheck => 1, ssl_opts => { verify_hostname => 0 });
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

sub extract_imdb_data($$) { # {{{1
	my ($self, $imdb_number) = @_;

	my $url = 'http://www.imdb.com/title/tt' . $imdb_number . '/';
	$LOGGER->debug('url: ' . $url);

	my $www = $self->{'www'};
	$www->get($url);
	unless ($www->success) {
		$LOGGER->error('Can\'t retrieve ' . $url . ': ' . $!);
		return undef;
	}

	my $title = undef;
	my $year = undef;
	my @genres;
	my $rating = undef;
	my $raters = undef;

	for (split("\n", $www->content())) {
		# <title>Contagion (2011) - IMDb</title>
		# <title>IMDb - Thor (2011)</title>
		# <title>John Grin&#x27;s Christmas (TV 1986) - IMDb</title>
		if (/<title>(?:IMDb - )?(.+) \((?:.+ )?(\d{4})\)(?: - IMDb)?<\/title>/) {
			$title = HTML::Entities::decode($1);
			$LOGGER->debug('title: ' . $title);
			$year = $2;
			$LOGGER->debug('year: ' . $year);
		}

		# 23,542 IMDb users have given an average vote of 7.0/10
		if (/([\d,]+) IMDb users have given an average vote of (\d\.\d)\/10/) {
			$raters = $1;
			$rating = $2;
			$raters =~ s/,//;
			$LOGGER->debug('rating: ' . $rating);
			$LOGGER->debug('raters: ' . $raters);
		}

		# <a href="/genre/Drama" itemprop="genre">Drama</a>&nbsp;<span>|</span> <a href="/genre/Sci-Fi" itemprop="genre">Sci-Fi</a>
		while (s{<a href=\"/genre/([^"]+)"}{}) {
			push(@genres, HTML::Entities::decode($1));
		}
	}

	$LOGGER->debug("@genres");
	return {title => $title, year => $year, genres => \@genres, rating => $rating, raters => $raters, url => $url};
} # }}}1

1;
