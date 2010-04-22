#!/usr/bin/perl -w

use strict;
use warnings FATAL => 'all';

use lib '../lib';

use Date::Format;
use Date::Parse;
use File::Basename;
use File::Path;
use File::Spec;
use File::Temp;
use WWW::Mechanize;
use XML::DOM;

File::Temp->safe_level(File::Temp::HIGH);

my $AGE       = 50;
my $NET_SPEED = 1000*1000; # download speed (byte per second)
my $NZB_BIN   = '';
my $NZB_DIR   = '/tmp/nzbdata';
my $RAR_BIN   = 'unrar';
my $TMP_DIR   = File::Temp->newdir(File::Spec->tmpdir() . '/nzb_XXXXX', UNLINK => 1);

my $END      = str2time(time2str("%Y-%m-%d", time()));
my $START    = $END - ($AGE * 86400);

my $WWW      = WWW::Mechanize->new();
$WWW->agent_alias('Windows IE 6');
$WWW->default_header('Accept-Encoding' => 'deflate,gzip');

sub checkNZB #{{{1
{
	my ($nzb, %blacklist) = @_;

	# nzb from blacklisted poster
	if (defined $blacklist{$nzb->{poster}}) {
		return 0;
	}

	#  password and rar in rar
	my $rar = getFirstRAR($nzb);
	if ((! defined $rar) || (! -r $rar)) {
		# no rar to check => fail
		return 0;
	}

	# lt  : technical filelist
	# lb  : list bare file names
	# -p- : don't ask for password
	my @bare_files = `$RAR_BIN lb -p- $rar 2> /dev/null`;
	my @technical  = `$RAR_BIN lt -p- $rar 2> /dev/null`;
	unlink($rar);

	# empty rar or encrypted headers
	if (scalar @bare_files == 0) {
		return 0;
	}

	# check for encrypted data
	for my $line (@technical) {
		if ($line =~ m/^\*/) {
			return 0;
		}
	}

	# check for rar-in-rar
	for my $file (@bare_files) {
		if ($file =~ m/\.rar$/) {
			return 0;
		}
	}

	print "good nzb\n";
	return 1;
}#}}}1 
sub determineFirstRAR #{{{1
{
	my (@files) = @_;

	my @rars;
	for my $file (@files) {
		if ($file->{subject} =~ m/\.rar/) {
			push(@rars, $file);
		}
	}

	if ((scalar @rars) > 1) {
		sub rar_sort #{{{2
		{
			$a->{subject} =~ m/(\d+)\.rar/;
			my $part_a = $1;

			$b->{subject} =~ m/(\d+)\.rar/;
			my $part_b = $1;

			return $part_a cmp $part_b;
		} #}}}2

		@rars = sort rar_sort @rars;
	}

	my $first = undef;
	if ((scalar @rars) >= 1) {
		$first = $rars[0];
	}

	return $first;
} #}}}1
sub downloadNZB #{{{1
{
	my ($nzb, $file) = @_;
	my $url = 'http://binsearch.info/fcgi/nzb.fcgi';

	my $data = $WWW->post( $url, { $nzb->{id} => 'on', action => 'nzb' } );
	if ($WWW->success) {
		open (FH, ">$file");
		print FH $data;
		close (FH);
	} else {
		print STDERR "Can't retrieve $url: $!";
	}
} #}}}1
sub getFirstRAR #{{{1
{
	my ($nzb) = @_;
	my $tmp = File::Temp->new(TEMPLATE => 'temp_XXXXX', DIR => $TMP_DIR, SUFFIX => '.nzb', UNLINK => 1);
	downloadNZB($nzb, $tmp);

	my @files = parseNZB($tmp);
	unlink($tmp);

	my $first = determineFirstRAR(@files);
	if (defined $first) {
		my $firstNZB = File::Temp->new(TEMPLATE => 'min_XXXXX', DIR => $TMP_DIR, SUFFIX => '.nzb', UNLINK => 1);
		writeNZB($first, $firstNZB);

		my $size = 0;
		my $sections = $firstNZB->{sections};
		for my $section (@$sections) {
			$size += $section->{size};
		}

		my $pid = fork();
		if (not defined $pid) {
			print STDERR "can't fork\n";
		} elsif ($pid == 0) {
			my $absFile = File::Spec->rel2abs($firstNZB);

			# run nzb for $firstNZB
			chdir $TMP_DIR;
			`$NZB_BIN $absFile`;
			exit 0;
		} else {
			# give the child time to download the nzb (factor 2 is
			# grace)
			sleep (($size / $NET_SPEED) * 2);

			kill(-9, $pid);
			waitpid($pid, 0); 

			if ($? != 0) {
				print STDERR "nzb download not complete\n";
				return;
			}
		}

		$first->{subject} =~ m/"(.+)"/; # FIXME pattern to nzb way
		if ((defined $1) && ( -e $1)) {
			return File::Spec->rel2abs($TMP_DIR . '/' . $1); 
		}
	}
} #}}}1
sub parseNZB #{{{1
{
	my ($nzbfile) = @_;
	my $parser = new XML::DOM::Parser;
	my @fileset;
	my $nzbdoc = $parser->parsefile($nzbfile);

	my @files;
	for my $fileNode ($nzbdoc->getElementsByTagName("file")) {
		my $date    = $fileNode->getAttributes()->getNamedItem('date')->getValue();
		my $poster  = $fileNode->getAttributes()->getNamedItem('poster')->getValue();
		my $subject = $fileNode->getAttributes()->getNamedItem('subject')->getValue();

		my @groups;
		for my $groupNode ($fileNode->getElementsByTagName('group')) {
			push(@groups, $groupNode->getFirstChild()->getNodeValue());
		}

		my @segments;
		for my $segment ($fileNode->getElementsByTagName('segment')) {
			my $id     = $segment->getFirstChild()->getNodeValue();
			my $number = $segment->getAttributes()->getNamedItem('number')->getValue();
			my $size   = $segment->getAttributes()->getNamedItem('bytes')->getValue();

			push(@segments, { id => $id, number => $number, size => $size });
		}

		# sort segments by number (if available)
		if (defined($segments[0]) && defined($segments[0]->{'number'})){
			@segments = sort { $a->{'number'} <=> $b->{'number'} } @segments;
		}

		push(@files, { date => $date, poster => $poster, subject => $subject, groups => \@groups , segments => \@segments });
	}
	$nzbdoc->dispose;

	# sort files by subject
	return sort { $a->{'subject'} cmp $b->{'subject'}; } @files;
}#}}}1
sub searchNZB #{{{1
{
	my ($serie, $episode) = @_;
	my @nzbs;

	my $url = 'http://binsearch.info/index.php?adv_sort=date&adv_col=on' . 
	          '&m=&max=25&adv_g=' . $serie->{group} . 
	          '&adv_age=' . $AGE . 
	          '&minsize=' . $serie->{min} . 
	          '&maxsize=' . $serie->{max} .
	          '&q=' . $serie->{query} . '+' . $episode . '+HDTV';

	if ($serie->{hd}) {
		$url .= '+x264';
	} else {
		$url .= '+xvid';
	}

	my $page = $WWW->get($url);
	if ($WWW->success) {
		my $data = $page->decoded_content;
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

	return @nzbs;
} #}}}1
sub writeNZB #{{{1
{
	my ($nzbFile, $output) = @_;

	my $xml = XML::DOM::Document->new;
	my $nzbElement  = $xml->createElement('nzb');
	my $fileElement = $xml->createElement('file');
	$fileElement->setAttribute('date',    $nzbFile->{date});
	$fileElement->setAttribute('poster',  $nzbFile->{poster});
	$fileElement->setAttribute('subject', $nzbFile->{subject});

	my $groupsElement = $xml->createElement('groups');
	my $groups = $nzbFile->{groups};
	for my $group (@$groups) {
		my $groupElement = $xml->createElement('group');
		$groupElement->appendChild($xml->createTextNode($group));
		$groupsElement->appendChild($groupElement);
	}
	$fileElement->appendChild($groupsElement);

	my $segmentsElement = $xml->createElement('segments');
	my $segments = $nzbFile->{segments};
	for my $segment (@$segments) {
		my $segmentElement = $xml->createElement('segment');
		$segmentElement->setAttribute('bytes',  $segment->{size});
		$segmentElement->setAttribute('number', $segment->{number});
		$segmentElement->appendChild($xml->createTextNode($segment->{id}));
		$segmentsElement->appendChild($segmentElement);
	}
	$fileElement->appendChild($segmentsElement);
	$nzbElement->appendChild($fileElement);

	open (FH, ">$output");
	print FH $nzbElement->toString;
	close (FH);
} #}}}1

# list of posters, we don't want nzbs from {{{1
my @blacklist =
(
	'ficken',
);
my %bp = map { $_ => 1 } @blacklist;
#}}}1

# id    = folder name on http://epguides.com/
# query = series names to search for on http://binsearch.info/
# group = newsgroup to search for posts
# min   = minimal size of nzb collection
# max   = maximal size of nzb collection
# hd    = search for x264 or xvid content
my @series = #{{{1
(
  { id => '24',                   query => '24',                       group => 'alt.binaries.multimedia', min =>  350, max =>  500, hd => 0 },
  { id => '24',                   query => '24',                       group => 'alt.binaries.multimedia', min => 1000, max => 1500, hd => 1 },
  { id => 'CSI',                  query => 'CSI',                      group => 'alt.binaries.multimedia', min =>  350, max =>  500, hd => 0 },
  { id => 'CSI',                  query => 'CSI',                      group => 'alt.binaries.multimedia', min => 1000, max => 1500, hd => 1 },
  { id => 'CSIMiami',             query => 'CSI.Miami',                group => 'alt.binaries.multimedia', min =>  350, max =>  500, hd => 0 },
  { id => 'CSIMiami',             query => 'CSI.Miami',                group => 'alt.binaries.multimedia', min => 1000, max => 1500, hd => 1 },
  { id => 'CSINY',                query => 'CSI.New.York',             group => 'alt.binaries.multimedia', min =>  350, max =>  500, hd => 0 },
  { id => 'CSINY',                query => 'CSI.New.York',             group => 'alt.binaries.multimedia', min => 1000, max => 1500, hd => 1 },
  { id => 'NCIS',                 query => 'NCIS',                     group => 'alt.binaries.multimedia', min =>  350, max =>  500, hd => 0 },
  { id => 'NCIS',                 query => 'NCIS',                     group => 'alt.binaries.multimedia', min => 1000, max => 1500, hd => 1 },
  { id => 'StarWarsTheCloneWars', query => 'Star.Wars.The.Clone.Wars', group => 'alt.binaries.multimedia', min =>  200, max =>  300, hd => 0 },
  { id => 'StarWarsTheCloneWars', query => 'Star.Wars.The.Clone.Wars', group => 'alt.binaries.multimedia', min =>  500, max =>  800, hd => 1 },
  { id => 'StargateUniverse',     query => 'Stargate.Universe',        group => 'alt.binaries.multimedia', min =>  350, max =>  500, hd => 0 },
  { id => 'StargateUniverse',     query => 'Stargate.Universe',        group => 'alt.binaries.multimedia', min => 1000, max => 1500, hd => 1 },
); #}}}1

for my $serie (@series) {
	my $url = 'http://epguides.com/' . $serie->{id} . '/';
	$WWW->get($url);
	
	if (! $WWW->success) {
		print  "Can't retrieve $url: $!";
		next;
	}

	for (split("\n", $WWW->content())) {
		if (/\s+(\d{1,2})-(\d{1,2})\s+(?:\S+\s+){0,1}(\d{2}.\w{3}.\d{2})/) {
			my $season   = $1;
			my $episode  = $2;
			my $released = $3;
			$released =~ s# #/#g;
			$released = str2time($released);

			if (($START <= $released) && ($released <= $END)) {
				my $episodeID = sprintf("S%02dE%02d", $season, $episode);
				my @nzbs = searchNZB($serie, $episodeID);

				my $file = $NZB_DIR . '/' . $serie->{id} . '/' . $serie->{id} . '_' . $episodeID;
				if ($serie->{hd}) {
					$file .= '-HD';
				}
				$file .= '.nzb';

				mkpath(dirname($file));
				if (! -e $file) {
					for my $nzb (@nzbs) {
						if (checkNZB($nzb, %bp)) {
							downloadNZB($nzb, $file);
							last;
						}
					}
				}
			}
		}
	}
}
