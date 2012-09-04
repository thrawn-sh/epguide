#!/usr/bin/perl -w

package NZB::IMDB;

use strict;
use warnings FATAL => 'all';

use Crypt::SSLeay;
use File::Basename;
use File::Path;
use HTML::Entities;
use LWP::ConnCache;
use Log::Log4perl;
use Storable;
use WWW::Mechanize::GZip;

my $LOGGER = Log::Log4perl->get_logger();

sub new {
	my $class  = shift;
	my %params = @_;

	my $www = WWW::Mechanize::GZip->new(autocheck => 1, ssl_opts => { verify_hostname => 0 });
	$www->agent_alias('Windows IE 6');
	$www->conn_cache(LWP::ConnCache->new);
	$www->default_header('Accept-Language' => 'en');

	my $self = {
		dir => dirname($0) . '/.imdb',
		www => $www,
	};

	my $dir = $params{'dir'};
	$self->{'dir'} = $dir . '/.imdb' if defined $dir;

	bless $self, $class;
	return $self;
}

sub extract_first_release_date($$) { # {{{1
	my ($self, $imdb_number) = @_;

	my $url = 'http://www.imdb.com/title/tt' . $imdb_number . '/releaseinfo';
	$LOGGER->debug('url: ' . $url);

	my $www = $self->{'www'};
	$www->get($url);
	unless ($www->success) {
		$LOGGER->error('Can\'t retrieve ' . $url . ': ' . $!);
		return undef;
	}

	my $release = undef;
	for (split("\n", $www->content())) {
		# <td align="right"><a href="/date/10-29/">29 October</a> <a href="/year/2003/">2003</a></td>
		if (/.*<a href="\/date\/(\d{2})-(\d{2})\/">.*<a href="\/year\/(\d{4})\/">.*/) {
			$release = $3 . '-' . $1 . '-' . $2;
			last;
		}
	}

	$LOGGER->warn('could not determine release for ' . $url) unless $release;
	return $release;
}  # }}}1
sub extract_imdb_data($$) { # {{{1
	my ($self, $imdb_number) = @_;

	my $dir = $self->{'dir'};
	if ( ! -d $dir) {
		File::Path::make_path($dir);
	}

	my $cache = $dir . '/' . $imdb_number . '.dat';
	if ( -f $cache) {
		my $imdb = Storable::lock_retrieve($cache);
		return $imdb if defined $imdb;
		$LOGGER->info('Could not retrieve data from store: ' . $cache . ' (=> must refetch)');
	}

	my $url = 'http://www.imdb.com/title/tt' . $imdb_number . '/';
	$LOGGER->debug('url: ' . $url);

	my $www = $self->{'www'};
	$www->get($url);
	unless ($www->success) {
		$LOGGER->error('Can\'t retrieve ' . $url . ': ' . $!);
		return undef;
	}

	my $title  = undef;
	my $year   = undef;
	my @genres = ();
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
		while (s{<a [^>]*href=\"/genre/([^"]+)"}{}) {
			push(@genres, HTML::Entities::decode($1));
		}
	}

	my $release = extract_first_release_date($self, $imdb_number);

	my $imdb = {id => $imdb_number, title => $title, year => $year, genres => \@genres, rating => $rating, raters => $raters, release => $release, url => $url};
	if (check_imdb($imdb, $url)) {
		Storable::lock_store($imdb, $cache);
	}
	return $imdb;
} # }}}1

sub check_imdb($$) { # {{{1
	my ($imdb, $url) = @_;

	unless ($imdb->{'title'}) {
		$LOGGER->warn('could not determine title  for ' . $url);
		return 0;
	}

	unless ($imdb->{'year'}) {
		$LOGGER->warn('could not determine year   for ' . $url);
		return 0;
	}

	unless ($imdb->{'genres'}) {
		$LOGGER->warn('could not determine genres for ' . $url);
		$LOGGER->debug("$imdb->{'genres'}");
		return 0;
	}

	unless ($imdb->{'rating'}) {
		$LOGGER->warn('could not determine rating for ' . $url);
		return 0;
	}

	unless ($imdb->{'raters'}) {
		$LOGGER->warn('could not determine raters for ' . $url);
		return 0;
	}

	return 1;
} # }}}1

1;
