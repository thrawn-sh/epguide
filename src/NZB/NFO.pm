#!/usr/bin/perl -w

package NZB::NFO;

use strict;
use warnings FATAL => 'all';

use Crypt::SSLeay;
use LWP::ConnCache;
use WWW::Mechanize;

my $WWW = WWW::Mechanize->new(ssl_opts => { verify_hostname => 0 });
$WWW->agent_alias('Windows IE 6');
$WWW->conn_cache(LWP::ConnCache->new);
$WWW->default_header('Accept-Encoding' => 'deflate,gzip');

sub parse_imdb_nr { #{{{1
	my ($self, $url) = @_;

	$WWW->get($url);
	if ($WWW->success) {
		if ($WWW->content() =~ /([\w:\/\.]*imdb\.[\w]{2,3}\/[\?\.\/\w\d]+)/) {
			my $imdb_nr = $1;
			$imdb_nr =~ s/[^\d]+//g;
			return $imdb_nr;
		}
	} else {
		print STDERR 'Can\'t retrieve ' . $url . ': ' . $! . "\n";
	}
	return undef;
} # }}}1

1;
