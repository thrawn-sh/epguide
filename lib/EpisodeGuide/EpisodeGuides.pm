#!/usr/bin/perl -w

package EpisodeGuide::EpisodeGuides;

use strict;
use warnings FATAL => 'all';

use Date::Calc qw( Add_Delta_Days Today Date_to_Time Time_to_Date This_Year);
use Date::Format;
use Date::Parse;
use LWP::ConnCache;
use Log::Log4perl;
use Text::CSV;
use WWW::Mechanize::GZip;

my $LOGGER = Log::Log4perl->get_logger();

sub  trim($) {
    my ($string) = @_;
    $string =~ s/^\s+|\s+$//g;
    return $string;
}

sub new {
    my $class  = shift;
    my %params = @_;

    my $www = WWW::Mechanize::GZip->new(autocheck => 1, ssl_opts => { verify_hostname => 0 });
    $www->agent_alias('Windows IE 6');
    $www->conn_cache(LWP::ConnCache->new);
    $www->default_header('Accept-Language' => 'en');

    my $self = {
        www => $www,
    };

    bless $self, $class;
    return $self;
}

sub getAllEpisodes($$$) { #{{{1
    my ($self, $serieID) = @_;

    my @episodes;
    my $today = Date_to_Time(Today(), 0, 0, 0);
    my $first = Date_to_Time(Add_Delta_Days(Today(), -90), 0, 0, 0);
    my $year  = This_Year();

    $LOGGER->info('time periode: ' . $first . ' -> ' . $today);

    my $url = 'http://epguides.com/common/exportToCSV.asp?rage=' . $serieID;
    $LOGGER->info('url: ' . $url);

    my $www = $self->{'www'};
    $www->get($url);
    unless ($www->success) {
        $LOGGER->error('Can\'t retrieve ' . $url . ': ' . $!);
        return undef;
    }

    my $csv = Text::CSV->new({ binary => 1, allow_loose_quotes => 1 });

    for my $line (split(/\r|\n/, $www->text())) {
        $line = trim($line);

        next if ($line eq ""); # empty
        next if ($line eq "list output"); # document title
        next if ($line eq "number,season,episode,production code,airdate,title,special?,tvrage"); # csv header

        unless ($csv->parse($line)) {
            $LOGGER->info('Could not parse line: => skipping (' . $line . ')' . $csv->error_diag() );
            next;
        }

        my @fields   = $csv->fields();
        my $season   = $fields[1];
        my $episode  = $fields[2];
        my $released = $fields[4];

        unless($season) {
            $LOGGER->info('Missing season : => skipping (' . $line . ')');
            next;
        }
        unless($episode) {
            $LOGGER->info('Missing episode : => skipping (' . $line . ')');
            next;
        }
        unless($released) {
            $LOGGER->info('Missing release date : => skipping (' . $line . ')');
            next;
        }
        $released =~ s# #/#g;

        my @dateparts = split(/\/| /,$released);
        unless (scalar(@dateparts) == 3) {
            $LOGGER->info('Incomplete release date : ' . $released . ' => skipping (' . $line . ')');
            next;
        }

        if ($dateparts[2] < 100) {
            $dateparts[2] += 2000;
            if ($dateparts[2] > $year) {
                $dateparts[2] -= 100;
            }
        }
        $released = join('/', @dateparts);
        $released = str2time($released);

        if (($released > $first) && ($released < $today)) {
            my $episodeID   = sprintf("s%02de%02d", $season, $episode);
            my $releaseDate = time2str('%Y-%m-%d', $released);
            $LOGGER->info('found episode ' . $episodeID . ' released on ' . $releaseDate);
            push(@episodes, { id => $episodeID, date => $releaseDate });
        }
    }

    return \@episodes;
} #}}}1
1;
