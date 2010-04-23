#!/usr/bin/perl -w

package NZB::Binsearch;

use strict;
use warnings FATAL => 'all';

use WWW::Mechanize::GZip;

my $WWW = WWW::Mechanize::GZip->new();
$WWW->agent_alias('Windows IE 6');

sub downloadNZB #{{{1
{
	my ($self, $nzb, $file) = @_;
	my $url = 'http://binsearch.info/fcgi/nzb.fcgi';

	$WWW->agent_alias('Windows IE 6');
	$WWW->default_header('Accept-Encoding' => 'deflate,gzip');

	$WWW->post($url, { $nzb->{'id'} => 'on', action => 'nzb' });
	if ($WWW->success) {
		open (FH, ">$file");
		print FH $WWW->content();
		close (FH);
	} else {
		print STDERR "Can't retrieve $url: $!";
	}
} #}}}1

sub searchNZB #{{{1
{
	my ($self, $serie, $episode, $age) = @_;
	my @nzbs;

	my $url = 'http://binsearch.info/index.php?adv_sort=date&adv_col=on' .
	          '&m=&max=25&adv_g=' . $serie->{'group'} .
	          '&adv_age=' . $age .
	          '&minsize=' . $serie->{'min'} .
	          '&maxsize=' . $serie->{'max'} .
	          '&q=' . $serie->{'query'} . '+' . $episode . '+HDTV';

	if ($serie->{'hd'}) {
		$url .= '+x264';
	} else {
		$url .= '+xvid';
	}

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
				.*>([^<]+)<\/a><td><a                    # poster
				//mxi
			)
			{
				my $parts_available = $4;
				my $parts_complete  = $5;
				if ($4 == $5) {
					my $nzb = { id => $1, subject => $2, size => $3, poster => $6 };
					push (@nzbs, $nzb);
				}
			}
		}
	} else {
		print  "Can't retrieve $url: $!";
	}

	return \@nzbs;
} #}}}1

1;