#!/usr/bin/perl -w

package NZB::NNTPI;

use strict;
use warnings FATAL => 'all';

use Crypt::SSLeay;
use File::Basename;
use File::Path;
use JSON qw( decode_json );
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
	$www->credentials('nntpi', 'an1Knip4cogikFav6');
	$www->default_header('Accept-Language' => 'en');

	my $self = {
		base => 'https://nntpi.shadowhunt.de:8443/api?apikey=3f7929559f2e198e8f0f03f9cac5198e',
		www  => $www,
	};

	bless $self, $class;
	return $self;
}

sub downloadNZB($$$) { #{{{1
	my ($self, $nzb, $file) = @_;

	my $url = $self->{'base'} . '&t=get&id=' . $nzb->{'id'};

	my $www = $self->{'www'};
	mkpath(dirname($file));
	$www->get($url);
	unless ($www->success) {
		$LOGGER->error('Can\'t retrieve ' . $url . ': ' . $!);
	}

	open (FH, ">$file");
	print FH $www->response->content();
	close (FH);
} #}}}1
sub searchNZB($$) { #{{{1
	my ($self, $url) = @_;
	$LOGGER->debug('url: ' . $url);

	my @nzbs;

	my $www = $self->{'www'};
	$www->get($url);
	unless ($www->success) {
		$LOGGER->error('Can\'t retrieve ' . $url . ': ' . $!);
		return undef;
	}

	my $data = $www->content;
	my $decoded_json = decode_json($data);

	foreach my $j ( @$decoded_json ) {
		my $nfo = 0;
		$nfo = 1 if (defined $j->{'nfoID'});

		next if ($j->{'completion'} < 100);
		my $nzb = { id => $j->{'guid'}, subject => $j->{'name'}, size => $j->{'size'}, password => 0, nfo => $nfo, poster => $j->{'fromname'} };
		push (@nzbs, $nzb);
	}

	@nzbs= sort { $a->{'id'} cmp $b->{'id'}; } @nzbs;
	return \@nzbs;
} #}}}1
sub searchNZBQuery($$$$$$) { #{{{1
	my ($self, $query, $age) = @_;
	$query =~ s/\W+/+/g;

	my $url = $self->{'base'} . '&o=json&t=search' .
	          '&q=' . $query .
		  '&maxage=' . $age;

	return $self->searchNZB($url);
} #}}}1 
sub searchNZBSerie($$$$$) { #{{{1
	my ($self, $serie, $season, $episode, $hd, $age) = @_;

	my $name = $serie->{'name'};
	$name =~ s/\W+/%20/g;

	my $url = $self->{'base'} . '&o=json&t=tvsearch&q=' . $name .
	          '&season=' . $season .
	          '&ep=' . $episode .
		  '&maxage=' . $age;
	if ($hd) {
		$url .= '&cat=5040';
	} else {
		$url .= '&cat=5030';
	}

	return $self->searchNZB($url);
} #}}}1

1;
