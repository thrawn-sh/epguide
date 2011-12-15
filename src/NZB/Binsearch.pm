#!/usr/bin/perl -w

package NZB::Binsearch;

use strict;
use warnings FATAL => 'all';

use Crypt::SSLeay;
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
		base => 'https://www.binsearch.info',
		www  => $www,
	};

	bless $self, $class;
	return $self;
}

sub downloadNZB($$$) { #{{{1
	my ($self, $nzb, $file) = @_;
	my $url = $self->{'base'} . '/fcgi/nzb.fcgi';

	my $www = $self->{'www'};
	$www->post($url, { $nzb->{'id'} => 'on', action => 'nzb' });
	if (! $www->success) {
		$LOGGER->error('Can\'t retrieve ' . $url . ': ' . $!);
	}

	open (FH, ">$file");
	print FH $www->content();
	close (FH);
} #}}}1
sub searchNZB($$) { #{{{1
	my ($self, $url) = @_;
	$LOGGER->debug('url: ' . $url);

	my @nzbs;

	my $www = $self->{'www'};
	$www->get($url);
	if (! $www->success) {
		$LOGGER->error('Can\'t retrieve ' . $url . ': ' . $!);
		return undef;
	}

	my $data = $www->content;
	while ( $data =~ s/(name=\"\d{8,}\".*?)<input\ //xmsi ) {
		my $line = $1;
		while (
			$line =~ s/
			\"(\d{8,})\".*?                                # id
			\<span\ class=\"s\"\>([^<]+).*?                # subject
			\>\ size:\ ([^,]*)                             # size
			,\ parts\ available:.*? (\d+)\ \/\ (\d+)       # parts_available parts_complete
			(.*requires\ password.*)?                      # password_required
			(?:.*\<a\ href=\"([^"]+viewNFO[^"&]+)[^"]*\")? # nfo
			.*>([^<]+)<\/a><td><a                          # poster
			//mxi
		)
		{
			my $password = 0;
			if (defined $6) {
				$password = 1;
			}

			my $nfo = undef;
			if (defined $7) {
				$nfo = $self->{'base'} . $7;
			}

			if ($4 == $5) {
				my $nzb = { id => $1, subject => $2, size => $3, password=> $password, nfo => $nfo, poster => $8 };
				push (@nzbs, $nzb);
			}
		}
	}

	@nzbs= sort { $a->{'id'} cmp $b->{'id'}; } @nzbs;
	return \@nzbs;
} #}}}1
sub searchNZBQuery($$$$$$) { #{{{1
	my ($self, $query, $group, $min, $max, $age) = @_;
	$query =~ s/\W+/+/g;

	my $url = $self->{'base'} . '/index.php?adv_sort=date&adv_col=on' .
	          '&m=&max=250&adv_g=' . $group .
		  '&adv_nfo=on' .
	          '&adv_age=' . $age .
	          '&minsize=' . $min .
	          '&maxsize=' . $max .
	          '&q=' . $query;

	return $self->searchNZB($url);
} #}}}1
sub searchNZBSerie($$$$$) { #{{{1
	my ($self, $serie, $episode, $hd, $age) = @_;

	my $url = $self->{'base'} . '/index.php?adv_sort=date&adv_col=on' .
	          '&m=&max=250&adv_g=' . $serie->{'group'} .
	          '&adv_age=' . $age;
	if ($hd) {
		$url .= '&minsize=' . $serie->{'threshold'} .
		        '&maxsize=' . $serie->{'max'};
	} else {
		$url .= '&minsize=' . $serie->{'min'} .
		        '&maxsize=' . $serie->{'threshold'};
	}
	$url .= '&q=' . $serie->{'query'} . '+' . $episode;

	return $self->searchNZB($url);
} #}}}1

1;
