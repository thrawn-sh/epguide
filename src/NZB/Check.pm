#!/usr/bin/perl -w

package NZB::Check;

use strict;
use warnings FATAL => 'all';

use File::Spec;
use File::Temp;
use NZB::Binsearch;
use NZB::Common;

File::Temp->safe_level(File::Temp::HIGH);

my $NET_SPEED = undef;
my $TMP_DIR   = File::Temp->newdir(File::Spec->tmpdir() . '/nzb_XXXXX', UNLINK => 1);

sub checkNZB #{{{1
{
	my ($self, $nzb, $nzb_bin, $rar_bin, %blacklist) = @_;

	# nzb from blacklisted poster
	if (defined $blacklist{$nzb->{'poster'}}) {
		return 0;
	}

	#  password and rar in rar
	my $rar = $self->getFirstRAR($nzb, $nzb_bin);
	if ((! defined $rar) || (! -r $rar)) {
		# no rar to check => fail
		return 0;
	}

	# lt  : technical filelist
	# lb  : list bare file names
	# -p- : don't ask for password
	my @bare_files = `$rar_bin lb -p- $rar 2> /dev/null`;
	my @technical  = `$rar_bin lt -p- $rar 2> /dev/null`;
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

	return 1;
}#}}}1

sub determineFirstRAR #{{{1
{
	my ($self, $files_ref) = @_;

	my @rars;
	for my $file (@$files_ref) {
		if ($file->{'subject'} =~ m/\.rar/) {
			push(@rars, $file);
		}
	}

	if ((scalar @rars) > 1) {
		sub rar_sort #{{{2
		{
			$a->{'subject'} =~ m/(\d+)\.rar/;
			my $part_a = $1;

			$b->{'subject'} =~ m/(\d+)\.rar/;
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

sub getFirstRAR #{{{1
{
	my ($self, $nzb, $nzb_bin) = @_;
	my $tmp = File::Temp->new(TEMPLATE => 'temp_XXXXX', DIR => $TMP_DIR, SUFFIX => '.nzb', UNLINK => 1);
	NZB::Binsearch->downloadNZB($nzb, $tmp);

	my $files_ref = NZB::Common->parseNZB($tmp);

	my $first = $self->determineFirstRAR($files_ref);
	if (defined $first) {
		my $firstNZB = File::Temp->new(TEMPLATE => 'min_XXXXX', DIR => $TMP_DIR, SUFFIX => '.nzb', UNLINK => 1);
		NZB::Common->writeNZB($first, $firstNZB);

		my $size = 0;
		my $segments_ref = $first->{'segments_ref'};
		for my $segment (@$segments_ref) {
			$size += $segment->{'size'};
		}

		my $firstRAR = undef;
		$first->{'subject'} =~ m/\"(.+)\"/;
		if (defined $1) {
			$firstRAR = File::Spec->rel2abs($TMP_DIR . '/' . $1);
		}

		my $pid = fork();
		if (not defined $pid) {
			print STDERR "can't fork\n";
		} elsif ($pid == 0) {
			my $absFile = File::Spec->rel2abs($firstNZB);

			# run nzb for $firstNZB
			chdir $TMP_DIR;
			`$nzb_bin $absFile > /dev/null 2> /dev/null`;
			exit 0;
		} else {
			# give the child time to download the nzb (factor 2 is
			# grace)
			my $sleepStep = 5;
			my $waitTime = (int (($size / $NET_SPEED) * 2 + $sleepStep));
			while ($waitTime > 0) {
				print "$waitTime\n";
				sleep($sleepStep);

				$waitTime -= $sleepStep;

				if (-e $firstRAR) {
					last;
				}
			}

			kill(-9, $pid);
			waitpid($pid, 1);

			if ($? != 0) {
				print STDERR "nzb download not complete\n";
				if (-e $firstRAR) {
					unlink($firstRAR);
				}
			}
		}

		return $firstRAR;
	}
} #}}}1

sub net_speed { my $($self, $speed) = @_; $NET_SPEED = $speed; }

1;
