#!/usr/bin/perl -w

package NZB::NZB;

use strict;
use warnings FATAL => 'all';

use XML::DOM;

sub parseNZB($$) { #{{{1
	my ($self, $nzbfile) = @_;
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

		push(@files, { date => $date, poster => $poster, subject => $subject, groups_ref => \@groups , segments_ref => \@segments });
	}
	$nzbdoc->dispose;

	# sort files by subject
	@files = sort { $a->{'subject'} cmp $b->{'subject'}; } @files;
	return \@files;
}#}}}1
sub writeNZB($$$) { #{{{1
	my ($self, $nzbFile, $output) = @_;

	my $xml = XML::DOM::Document->new;
	my $nzbElement  = $xml->createElement('nzb');
	my $fileElement = $xml->createElement('file');
	$fileElement->setAttribute('date',    $nzbFile->{'date'});
	$fileElement->setAttribute('poster',  $nzbFile->{'poster'});
	$fileElement->setAttribute('subject', $nzbFile->{'subject'});

	my $groupsElement = $xml->createElement('groups');
	for my $group (@{$nzbFile->{'groups_ref'}}) {
		my $groupElement = $xml->createElement('group');
		$groupElement->appendChild($xml->createTextNode($group));
		$groupsElement->appendChild($groupElement);
	}
	$fileElement->appendChild($groupsElement);

	my $segmentsElement = $xml->createElement('segments');
	for my $segment (@{$nzbFile->{'segments_ref'}}) {
		my $segmentElement = $xml->createElement('segment');
		$segmentElement->setAttribute('bytes',  $segment->{'size'});
		$segmentElement->setAttribute('number', $segment->{'number'});
		$segmentElement->appendChild($xml->createTextNode($segment->{'id'}));
		$segmentsElement->appendChild($segmentElement);
	}
	$fileElement->appendChild($segmentsElement);
	$nzbElement->appendChild($fileElement);

	open (FH, ">$output");
	print FH $nzbElement->toString;
	close (FH);
} #}}}1

1;
