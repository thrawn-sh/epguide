#!/usr/bin/perl -w

package NZB::IMDB;

use strict;
use warnings FATAL => 'all';

use Crypt::SSLeay;
use LWP::ConnCache;
use WWW::Mechanize;

my $DEBUG = 0;

my $WWW = WWW::Mechanize->new(ssl_opts => { verify_hostname => 0 });
$WWW->agent_alias('Windows IE 6');
$WWW->conn_cache(LWP::ConnCache->new);
$WWW->default_header('Accept-Encoding' => 'deflate,gzip');

sub extract_imdb_data($$) { # {{{1
	my ($self, $imdb_number) = @_;

	my $url = 'http://www.imdb.com/title/tt' . $imdb_number . '/';

	print STDERR 'url: ' . $url . "\n" if $DEBUG;

	$WWW->get($url);
	if ($WWW->success) {
		my $title = undef;
		my $year = undef;
		my @genres;
		my $rating = undef;
		my $raters = undef;

		for (split("\n", $WWW->content())) {
			# <title>Contagion (2011) - IMDb</title>
			if (/<title>(.+) \((?:.+ )?(\d{4})\) - IMDb<\/title>/) {
				$title = $1;
				print STDERR 'title: ' . $title . "\n" if $DEBUG;
				$year = $2;
				print STDERR 'year: ' . $year . "\n" if $DEBUG;
			}

			# 23,542 IMDb users have given an average vote of 7.0/10
			if (/([\d,]+) IMDb users have given an average vote of (\d\.\d)\/10/) {
				$raters = $1;
				$rating = $2;
				$raters =~ s/,//;
				print STDERR 'rating: ' . $rating . "\n" if $DEBUG;
				print STDERR 'raters: ' . $raters . "\n" if $DEBUG;
			}

			# <a href="/genre/Drama" itemprop="genre">Drama</a>&nbsp;<span>|</span> <a href="/genre/Sci-Fi" itemprop="genre">Sci-Fi</a>
			while (s{<a href=\"/genre/([^"]+)"}{}) {
				push(@genres, $1);
			}
		}

		if ($DEBUG) {
			print STDERR 'genres:';
			for my $genre (@genres) {
				print STDERR ' ' . $genre;
			}
			print STDERR "\n";
		}
		return {title => $title, year => $year, genres => \@genres, rating => $rating, raters => $raters, url => $url};
	} else {
		print STDERR 'Can\'t retrieve ' . $url . ': ' . $! . "\n";
	}
return undef;
} # }}}1

sub debug($$)     { my($self, $debug) = @_; $DEBUG       = $debug; }

1;
