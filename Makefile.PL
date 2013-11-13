use strict;
use warnings;

use ExtUtils::MakeMaker;
use POSIX qw(strftime);

eval 'use ExtUtils::MakeMaker::Coverage';

WriteMakefile(
	AUTHOR		=> 'Thrawn <thrawn@shadowhunt.de>',
	EXE_FILES	=> [ 'bin/nzb-collect', 'bin/epguide-notify' ],
	LICENSE		=> 'perl',
	NAME		=> 'NZB::Util',
	PREREQ_PM	=> {
		'Crypt::SSLeay'		=> 0.57,
		'Date::Calc'		=> 6.0,
		'Date::Parse'		=> 2.30,
		'File::Basename'	=> 2.78,
		'File::Path'		=> 2.08,
		'File::Spec'		=> 3.31,
		'File::Temp'		=> 0.22,
		'Getopt::Long'		=> 2.38,
		'HTML::Entities'	=> 3.68,
		'LWP::ConnCache'	=> 3.68,
		'Log::Log4perl'		=> 1.29,
		'Mail::Sendmail'	=> 0.79,
		'Storable'		=> 2.2,
		'Text::CSV'		=> 1.21,
		'Time::ParseDate'	=> 2011.0517,
		'WWW::Mechanize::GZip'	=> 0.12,
		'XML::DOM'		=> 1.44,
	},
	VERSION		=> strftime('%Y.%m%d', localtime),
);
