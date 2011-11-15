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

my $DEBUG       = 0;
my $NET_SPEED   = 10 * 1000; # 10 kb/s
my $NZB_WRAPPER = dirname($0) . '/nzb_wrapper.sh';
my $RAR_BIN     = 'unrar';
my $TMP_DIR     = File::Temp->newdir(File::Spec->tmpdir() . '/nzb_XXXXX', UNLINK => 1);

sub checkNZB #{{{1
{
	my ($self, $nzb,  %blacklist) = @_;
	
	# nzb from blacklisted poster
	if (defined $blacklist{$nzb->{'poster'}}) {
		print STDERR 'blacklist' . "\n" if $DEBUG;
		return 0;
	}

	# binsearch says this is a password protected nzb 
	if ($nzb->{'password'}) {
		print STDERR 'password (binsearch)' . "\n" if $DEBUG;
		return 0;
	}

	# password and rar in rar
	my $rar = $self->getFirstRAR($nzb);
	if (! -e $rar) {
		# no rar to check => fail
		print STDERR 'no rar download' . "\n" if $DEBUG;
		return 0;
	}

	# lt  : technical filelist
	# lb  : list bare file names
	# -p- : don't ask for password
	my @bare_files = `"$RAR_BIN" lb -p- "$rar" 2> /dev/null`;
	my @technical  = `"$RAR_BIN" lt -p- "$rar" 2> /dev/null`;

	# empty rar or encrypted headers
	if (scalar @bare_files == 0) {
		print STDERR 'empty rar' . "\n" if $DEBUG;
		unlink($rar);
		return 0;
	}

	# check for encrypted data
	for my $line (@technical) {
		if ($line =~ m/^\*/) {
			print STDERR 'encrypted rar' . "\n" if $DEBUG;
			unlink($rar);
			return 0;
		}
	}

	# check for rar-in-rar
	for my $file (@bare_files) {
		if ($file =~ m/\.rar$/) {
			print STDERR 'rar-in-rar' . "\n" if $DEBUG;
			unlink($rar);
			return 0;
		}
	}

	print STDERR 'nzb ok' . "\n" if $DEBUG;
	unlink($rar);
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
		} else {
			print STDERR $first->{'subject'} . "\n" if $DEBUG;
		}

		my $pid = fork();
		if (not defined $pid) {
			print STDERR "can't fork\n";
		} elsif ($pid == 0) {
			my $absFile = File::Spec->rel2abs($firstNZB);

			# download $firstNZB
			die 'no "' . $NZB_WRAPPER . '" available' unless -e $NZB_WRAPPER;
			print STDERR 'calling "' . $NZB_WRAPPER . '" with "' . $TMP_DIR . '" and "' . $absFile . '"' . "\n" if $DEBUG;
			`"$NZB_WRAPPER" "$TMP_DIR" "$absFile" > /dev/null 2> /dev/null`;
			print STDERR 'done' . "\n" if $DEBUG;
			# sometimes the downloaded file name does not match our
			# expectaion, so we have to rename the file
			if (! -e $firstRAR) {
				print STDERR 'missing expected file "' . $firstRAR . '"' . "\n" if $DEBUG;

				opendir(DIR, $TMP_DIR);
				while(my $file = readdir(DIR)) {
					my $fqfn = $TMP_DIR . '/' . $file;
					print STDERR 'checking "' . $fqfn . '"' . "\n" if $DEBUG;

					# only process files
					next if (! -f $fqfn);
					# skip all nzb files
					next if ($file =~ m/\.nzb$/);

					print STDERR 'renaming "' . $fqfn . '" to "' . $firstRAR . '"' . "\n" if $DEBUG;
					rename($fqfn, $firstRAR);
				}
				closedir(DIR);
			}

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

sub debug     { my($self, $debug) = @_; $DEBUG       = $debug; }
sub net_speed { my($self, $speed) = @_; $NET_SPEED   = $speed; }
sub nzb       { my($self, $nzb  ) = @_; $NZB_WRAPPER = $nzb  ; }
sub rar       { my($self, $rar  ) = @_; $RAR_BIN     = $rar  ; }

1;
