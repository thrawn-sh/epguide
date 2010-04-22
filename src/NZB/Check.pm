#!/usr/bin/perl -w

package NZB::Check;

use strict;
use warnings FATAL => 'all';

use File::Spec;
use File::Temp;
use NZB::Binsearch;
use NZB::Common;

File::Temp->safe_level(File::Temp::HIGH);

my $NET_SPEED = 1000*1000; # download speed (byte per second)
my $NZB_BIN   = 'nzb';
my $RAR_BIN   = 'unrar';
my $TMP_DIR   = File::Temp->newdir(File::Spec->tmpdir() . '/nzb_XXXXX', UNLINK => 1);

sub checkNZB #{{{1
{
	my ($self, $nzb, %blacklist) = @_;

	# nzb from blacklisted poster
	if (defined $blacklist{$nzb->{poster}}) {
		return 0;
	}

	#  password and rar in rar
	my $rar = $self->getFirstRAR($nzb);
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

	return 1;
}#}}}1 

sub determineFirstRAR #{{{1
{
	my ($self, @files) = @_;

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

sub getFirstRAR #{{{1
{
	my ($self, $nzb) = @_;
	my $tmp = File::Temp->new(TEMPLATE => 'temp_XXXXX', DIR => $TMP_DIR, SUFFIX => '.nzb', UNLINK => 1);
	NZB::Binsearch->downloadNZB($nzb, $tmp);

	my @files = NZB::Common->parseNZB($tmp);
	unlink($tmp);

	my $first = $self->determineFirstRAR(@files);
	if (defined $first) {
		my $firstNZB = File::Temp->new(TEMPLATE => 'min_XXXXX', DIR => $TMP_DIR, SUFFIX => '.nzb', UNLINK => 1);
		NZB::Common->writeNZB($first, $firstNZB);

		my $size = 0;
		my $sections = $firstNZB->{sections};
		for my $section (@$sections) {
			$size += $section->{size};
		}

		my $firstRAR = undef;
		$first->{subject} =~ m/"(.+)"/; 
		if ((defined $1) && ( -e $1)) {
			$firstRAR = File::Spec->rel2abs($TMP_DIR . '/' . $1);
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
				if (-e $firstRAR) {
					unlink($firstRAR);
				}
			}
		}

		return $firstRAR;
	}
} #}}}1

1;
