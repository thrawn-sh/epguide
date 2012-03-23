#!/usr/bin/perl -w

package NZB::Check;

use strict;
use warnings FATAL => 'all';

# cleanup temporary files and directories on signals
$SIG{TERM} = $SIG{INT} = $SIG{QUIT} = $SIG{HUP} = sub { die; };

use File::Basename;
use File::Spec;
use File::Temp;
use Log::Log4perl;
use NZB::Binsearch;
use NZB::NZB;
use WWW::Mechanize::GZip;

File::Temp->safe_level(File::Temp::HIGH);

my $LOGGER = Log::Log4perl->get_logger();

sub new {
	my $class  = shift;
	my %params = @_;

	my $www = WWW::Mechanize::GZip->new(autocheck => 1, ssl_opts => { verify_hostname => 0 });
	$www->agent_alias('Windows IE 6');
	$www->conn_cache(LWP::ConnCache->new);
	$www->default_header('Accept-Language' => 'en');

	my $self = {
		binsearch     => $params{'binsearch'},
		speed         => 10 * 1000, # 10 kb/s
		tmp_dir       => File::Temp->newdir(File::Spec->tmpdir() . '/nzb_XXXXX', UNLINK => 1),
		unrar         => 'unrar',
		wrapper       => dirname($0) . '/nzb_wrapper.sh',
		wrapper_cfg   => dirname($0) . '/nzb_wrapper.cfg',
	};

	my $speed = $params{'speed'};
	$self->{'speed'} = $speed if defined $speed;
	my $unrar = $params{'unrar'};
	$self->{'unrar'} = $unrar if defined $unrar;
	my $wrapper = $params{'wrapper'};
	$self->{'wrapper'} = $wrapper if defined $wrapper;
	my $wrapper_cfg = $params{'wrapper_cfg'};
	$self->{'wrapper_cfg'} = $wrapper_cfg if defined $wrapper_cfg;

	bless $self, $class;
	return $self;
}

sub checkNZB($$$) { #{{{1
	my ($self, $nzb,  $blacklist) = @_;
	
	# nzb from blacklisted poster
	if (defined $blacklist->{$nzb->{'poster'}}) {
		$LOGGER->debug('blacklist');
		return 0;
	}

	# binsearch says this is a password protected nzb 
	if ($nzb->{'password'}) {
		$LOGGER->debug('password (binsearch)');
		return 0;
	}

	# password and rar in rar
	my $rar = $self->getFirstRAR($nzb);
	unless (-e $rar) {
		# no rar to check => fail
		$LOGGER->debug('no rar download');
		return 0;
	}

	# lt  : technical filelist
	# lb  : list bare file names
	# -p- : don't ask for password
	my $unrar = $self->{'unrar'};
	my @bare_files = `"$unrar" lb -p- "$rar" 2> /dev/null`;
	my @technical  = `"$unrar" lt -p- "$rar" 2> /dev/null`;

	# empty rar or encrypted headers
	if (scalar @bare_files == 0) {
		$LOGGER->debug('empty rar');
		unlink($rar);
		return 0;
	}

	# check for encrypted data
	for my $line (@technical) {
		if ($line =~ m/^\*/) {
			$LOGGER->debug('encrypted rar');
			unlink($rar);
			return 0;
		}
	}

	# check for rar-in-rar
	for my $file (@bare_files) {
		if ($file =~ m/\.rar$/) {
			$LOGGER->debug('rar-in-rar');
			unlink($rar);
			return 0;
		}
	}

	$LOGGER->debug('nzb ok');
	unlink($rar);
	return 1;
}#}}}1
sub determineFirstRAR($$) { #{{{1
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
			$LOGGER->warn($a->{'subject'} . ' did not match') unless $part_a;


			my $part_b = "";
			$b->{'subject'} =~ m/(\d+)\.rar"/;
			$part_b = $1;
			$LOGGER->warn($b->{'subject'} . ' did not match') unless $part_b;

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
sub getFirstRAR($$) {#{{{1
	my ($self, $nzb) = @_;
	my $tmp_dir = $self->{'tmp_dir'};
	my $tmp = File::Temp->new(TEMPLATE => 'temp_XXXXX', DIR => $tmp_dir, SUFFIX => '.nzb', UNLINK => 1);

	my $binsearch = $self->{'binsearch'};
	$binsearch->downloadNZB($nzb, $tmp);

	my $files_ref = NZB::NZB->parseNZB($tmp);

	my $first = $self->determineFirstRAR($files_ref);
	if (defined $first) {
		my $firstNZB = File::Temp->new(TEMPLATE => 'min_XXXXX', DIR => $tmp_dir, SUFFIX => '.nzb', UNLINK => 1);
		NZB::NZB->writeNZB($first, $firstNZB);

		my $size = 0;
		for my $segment (@{$first->{'segments_ref'}}) {
			$size += $segment->{'size'};
		}

		my $firstRAR = undef;
		$first->{'subject'} =~ m/\"(.+)\"/;
		if (defined $1) {
			$firstRAR = File::Spec->rel2abs($tmp_dir . '/' . $1);
		} else {
			$LOGGER->debug($first->{'subject'});
		}

		my $pid = fork();
		if (not defined $pid) {
			$LOGGER->error('can\'t fork');
		} elsif ($pid == 0) {
			my $absFile = File::Spec->rel2abs($firstNZB);

			my $wrapper     = $self->{'wrapper'};
			my $wrapper_cfg = $self->{'wrapper_cfg'};
			# download $firstNZB
			die 'no "' . $wrapper . '" available' unless -e $wrapper;
			$LOGGER->debug('calling "' . $wrapper . '" with "' . $tmp_dir . '" and "' . $absFile . '" and "' . $wrapper_cfg . '"');
			`"$wrapper" "$tmp_dir" "$absFile" "$wrapper_cfg" > /dev/null 2> /dev/null`;
			$LOGGER->debug('done');
			# sometimes the downloaded file name does not match our
			# expectaion, so we have to rename the file
			unless (-e $firstRAR) {
				$LOGGER->debug('missing expected file "' . $firstRAR . '"');

				opendir(DIR, $tmp_dir);
				while(my $file = readdir(DIR)) {
					my $fqfn = $tmp_dir . '/' . $file;
					$LOGGER->debug('checking "' . $fqfn . '"');

					# only process files
					next unless (-f $fqfn);
					# skip all nzb files
					next if ($file =~ m/\.nzb$/);

					$LOGGER->debug('renaming "' . $fqfn . '" to "' . $firstRAR . '"');
					rename($fqfn, $firstRAR);
				}
				closedir(DIR);
			}

			exit 0;
		} else {
			# give the child time to download the nzb (factor 2 is
			# grace)
			my $sleepStep = 5;
			my $speed = $self->{'speed'};
			my $waitTime = (int (($size / $speed) * 2 + $sleepStep));

			while (($waitTime > 0) and (waitpid($pid, 1) == 0) and (! -e $firstRAR)) {
				sleep($sleepStep);
				$waitTime -= $sleepStep;
			}

			kill(-9, $pid);
			waitpid($pid, 1);
		}

		return $firstRAR;
	}
} #}}}1

1;
