#!/usr/bin/perl -w

package NZB::EpisodeGuides;

use strict;
use warnings FATAL => 'all';

use Date::Calc qw( Add_Delta_Days Today Date_to_Time Time_to_Date);
use Date::Format;
use Date::Parse;
use LWP::ConnCache;
use Log::Log4perl;
use Text::CSV;
use WWW::Mechanize::GZip;

my $LOGGER = Log::Log4perl->get_logger();

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

    my $url = 'http://epguides.com/common/exportToCSV.asp?rage=' . $serieID;
    $LOGGER->debug('url: ' . $url);

    my $www = $self->{'www'};
    $www->get($url);
    unless ($www->success) {
        $LOGGER->error('Can\'t retrieve ' . $url . ': ' . $!);
        return undef;
    }

    my $csv = Text::CSV->new({ binary => 1 });

    my $line_counter = 0;
    for my $line (split("\n", $www->text())) {
        $line_counter++;
        next if ($line_counter <= 1);     # skip cvs header
        next unless ($csv->parse($line)); # could not parse line

        my @fields = $csv->fields();
        my $season   = $fields[1];
        my $episode  = $fields[2];
        my $released = $fields[4];

        unless($season) {
            $LOGGER->info('Missing season : => skipping');
            next;
        }
        unless($episode) {
            $LOGGER->info('Missing episode : => skipping');
            next;
        }
        unless($released) {
            $LOGGER->info('Missing release date : => skipping');
            next;
        }
        $released =~ s# #/#g;

        my @dateparts = split(/\//,$released);
        unless (scalar(@dateparts) == 3) {
            $LOGGER->info('Incomplete release date : ' . $released . ' => skipping');
            next;
        }

        if ($dateparts[2] < 100) {
            $dateparts[2] += 2000;
        }
        $released = join('/', @dateparts);
        $released = str2time($released) + (24 * 60 * 60); # give the release one day time to propagate

        if (($released > $first) && ($released < $today)) {
            my $episodeID = sprintf("s%02de%02d", $season, $episode);
            push(@episodes, { id => $episodeID, date => time2str('%Y-%m-%d', $released) });
        }
    }

    return \@episodes;
} #}}}1
sub getEpisodes($$$) { #{{{1
    my ($self, $serieID, $search_weeks) = @_;

    my @episodes;
    my @today = Today();
    my $nzb_end_date   = Date_to_Time(@today, 0, 0, 0);
    my $nzb_start_date = Date_to_Time(Add_Delta_Days(@today, $search_weeks * -7), 0, 0, 0);

    my $url = 'http://epguides.com/common/exportToCSV.asp?rage=' . $serieID;
    $LOGGER->debug('url: ' . $url);

    my $www = $self->{'www'};
    $www->get($url);
    unless ($www->success) {
        $LOGGER->error('Can\'t retrieve ' . $url . ': ' . $!);
        return undef;
    }

    my $csv = Text::CSV->new({ binary => 1 });

    my $line_counter = 0;
    for my $line (split("\n", $www->text())) {
        $line_counter++;
        next if ($line_counter <= 1);     # skip cvs header
        next unless ($csv->parse($line)); # could not parse line

        my @fields = $csv->fields();
        my $season   = $fields[1];
        my $episode  = $fields[2];
        my $released = $fields[4];

        unless($released) {
            $LOGGER->info('Missing release date : => skipping');
            next;
        }
        $released =~ s# #/#g;

        my @dateparts = split(/\//,$released);
        unless (scalar(@dateparts) == 3) {
            $LOGGER->info('Incomplete release date : ' . $released . ' => skipping');
            next;
        }

        if ($dateparts[2] < 100) {
            $dateparts[2] += 2000;
        }
        $released = join('/', @dateparts);
        $released = str2time($released);

        if (($nzb_start_date <= $released) and ($released <= $nzb_end_date)) {
            my $episodeID = sprintf("s%02de%02d", $season, $episode);
            push(@episodes, $episodeID);
        }
    }

    return \@episodes;
} #}}}1
1;
