use strict;
use warnings;

use ExtUtils::MakeMaker;
use POSIX qw(strftime);

eval 'use ExtUtils::MakeMaker::Coverage';

WriteMakefile(
    AUTHOR    => 'Shadowhunt <dev@shadowhunt.de>',
    EXE_FILES => [ 'bin/epguide-notify' ],
    LICENSE   => 'perl',
    NAME      => 'EpisodeGuide::Util',
    PREREQ_PM => {
        'Date::Format'         => 2.24,
        'Date::Parse'          => 2.30,
        'DateTime'             => 1.12,
        'Getopt::Long'         => 2.38,
        'LWP::ConnCache'       => 3.68,
        'Log::Log4perl'        => 1.29,
        'Text::CSV'            => 1.21,
        'WWW::Mechanize::GZip' => 0.12,
    },
    VERSION   => strftime('%Y.%m%d', localtime),
);
