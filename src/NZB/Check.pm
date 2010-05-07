#!/usr/bin/perl -w

package NZB::Check;

use strict;
use warnings FATAL => 'all';

# cleanup temporary files and directories on signals
$SIG{TERM} = $SIG{INT} = $SIG{QUIT} = $SIG{HUP} = sub { die; };

use File::Basename;
use File::Spec;
use File::Temp;
use NZB::Binsearch;
use NZB::Common;

File::Temp->safe_level(File::Temp::HIGH);

my $DEBUG     = 0;
my $NET_SPEED = 10 * 1000; # 10 kb/s
my $RAR_BIN   = 'unrar';
my $TMP_DIR   = File::Temp->newdir(File::Spec->tmpdir() . '/nzb_XXXXX', UNLINK => 1);

sub checkNZB #{{{1
{
	my ($self, $nzb,  %blacklist) = @_;

	# nzb from blacklisted poster
	if (defined $blacklist{$nzb->{'poster'}}) {
		if ($DEBUG) { print STDERR "blacklist\n"; }
		return 0;
	}

	#  password and rar in rar
	my $rar = $self->getFirstRAR($nzb);
	if (! -e $rar) {
		# no rar to check => fail
		if ($DEBUG) { print STDERR "no rar download\n"; }
		return 0;
	}

	# lt  : technical filelist
	# lb  : list bare file names
	# -p- : don't ask for password
	my @bare_files = `$RAR_BIN lb -p- $rar 2> /dev/null`;
	my @technical  = `$RAR_BIN lt -p- $rar 2> /dev/null`;

	# empty rar or encrypted headers
	if (scalar @bare_files == 0) {
		if ($DEBUG) { print STDERR "empty rar\n"; }
		return 0;
	}

	# check for encrypted data
	for my $line (@technical) {
		if ($line =~ m/^\*/) {
			if ($DEBUG) { print STDERR "encrypted rar\n"; }
			return 0;
		}
	}

	# check for rar-in-rar
	for my $file (@bare_files) {
		if ($file =~ m/\.rar$/) {
			if ($DEBUG) { print STDERR "rar-in-rar\n"; }
			return 0;
		}
	}

	if ($DEBUG) { print STDERR "nzb ok\n"; }
	return 1;
}#}}}1

sub determineFirstRAR #{{{1
{
	my ($self, $files_ref) = @_;

	my @rars;
	for my $file (@{$files_ref}) {
		if ($file->{'subject'} =~ m/\.rar"/) {
			push(@rars, $file);
		}
	}

	if ((scalar @rars) > 1) {
		sub rar_sort #{{{2
		{
			my $part_a = "";
			$a->{'subject'} =~ m/(\d+)\.rar"/;
			$part_a = $1;

			my $part_b = "";
			$b->{'subject'} =~ m/(\d+)\.rar"/;
			$part_b = $1;

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

	my $files_ref = NZB::Common->parseNZB($tmp);

	my $first = $self->determineFirstRAR($files_ref);
	if (defined $first) {
		my $firstNZB = File::Temp->new(TEMPLATE => 'min_XXXXX', DIR => $TMP_DIR, SUFFIX => '.nzb', UNLINK => 1);
		NZB::Common->writeNZB($first, $firstNZB);

		my $size = 0;
		for my $segment (@{$first->{'segments_ref'}}) {
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

			# download $firstNZB
			my $wrapper = dirname($0) . '/nzb_wrapper.sh';
			die 'no \'' . $wrapper . '\' available' unless -e $wrapper;

			`$wrapper $TMP_DIR $absFile > /dev/null 2> /dev/null`;
			exit 0;
		} else {
			# give the child time to download the nzb (factor 2 is
			# grace)
			my $sleepStep = 5;
			my $waitTime = (int (($size / $NET_SPEED) * 2 + $sleepStep));

			while (($waitTime > 0) && (waitpid($pid, 1) == 0) && (! -e $firstRAR)) {
				sleep($sleepStep);
				$waitTime -= $sleepStep;
			}

			kill(-9, $pid);
			waitpid($pid, 1);
		}

		return $firstRAR;
	}
} #}}}1

sub debug     { my($self, $debug) = @_; $DEBUG     = $debug; }
sub net_speed { my($self, $speed) = @_; $NET_SPEED = $speed; }
sub rar       { my($self, $rar  ) = @_; $RAR_BIN   = $rar  ; }

1;
