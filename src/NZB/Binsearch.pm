#!/usr/bin/perl -w

package NZB::Binsearch;

use strict;
use warnings FATAL => 'all';

use Crypt::SSLeay;
use LWP::ConnCache;
use WWW::Mechanize;

my $WWW = WWW::Mechanize->new(ssl_opts => { verify_hostname => 0 });
$WWW->agent_alias('Windows IE 6');
#$WWW->conn_cache(LWP::ConnCache->new);

my $DEBUG       = 0;

sub downloadNZB #{{{1
{
	my ($self, $nzb, $file) = @_;
	my $url = 'https://binsearch.info/fcgi/nzb.fcgi';

	$WWW->agent_alias('Windows IE 6');
	$WWW->default_header('Accept-Encoding' => 'deflate,gzip');

	$WWW->post($url, { $nzb->{'id'} => 'on', action => 'nzb' });
	if ($WWW->success) {
		open (FH, ">$file");
		print FH $WWW->content();
		close (FH);
	} else {
		print STDERR 'Can\'t retrieve ' . $url . ': ' . $! . "\n";
	}
} #}}}1
sub searchNZB #{{{1
{
	my ($url) = @_;

	print STDERR $url . "\n" if $DEBUG;

	my @nzbs;

	$WWW->get($url);
	if ($WWW->success) {
		my $data = $WWW->content;
		while ( $data =~ s/(name=\"\d{8,}\".*?)<input\ //xmsi ) {
			my $line = $1;
			while (
				$line =~ s/
				\"(\d{8,})\".*?                          # id
				\<span\ class=\"s\"\>([^<]+).*?          # subject
				\>\ size:\ ([^,]*)                       # size
				,\ parts\ available:.*? (\d+)\ \/\ (\d+) # parts_available parts_complete
				(.*requires\ password.*)?                # password_required
                                .*href=\"(https?:\/\/binsearch\.info\/viewNFO\.php\?[^"]+)\" # nfo link
				.*>([^<]+)<\/a><td><a                    # poster
				//mxi
			)
			{
				my $password = 0;
				if (defined $6) {
					$password = 1;
				}
				if ($4 == $5) {
					my $nzb = { id => $1, subject => $2, size => $3, password=> $password, nfo => $7, poster => $8 };
					push (@nzbs, $nzb);
				}
			}
		}
	} else {
		print STDERR 'Can\'t retrieve ' . $url . ': ' . $! . "\n";
	}

	@nzbs= sort { $a->{'id'} cmp $b->{'id'}; } @nzbs;
	return \@nzbs;
} #}}}1
sub searchNZBMovie #{{{1
{
	my ($self, $movie, $year, $group, $min, $max, $age) = @_;
	$movie =~ s/\W+/+/g;

	my $url = 'http://binsearch.info/index.php?adv_sort=date&adv_col=on' .
	          '&m=&max=250&adv_g=' . $group .
	          '&adv_age=' . $age .
	          '&minsize=' . $min .
	          '&maxsize=' . $max .
	          '&q=' . $movie . '+' . $year;

	return searchNZB($url);
} #}}}1
sub searchNZBSerie #{{{1
{
	my ($self, $serie, $hd, $episode, $age) = @_;

	my $url = 'http://binsearch.info/index.php?adv_sort=date&adv_col=on' .
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

	return searchNZB($url);
} #}}}1

sub debug { my($self, $debug) = @_; $DEBUG = $debug; }

1;
