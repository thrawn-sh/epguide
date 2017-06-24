#!/usr/bin/perl -w

package EpisodeGuide::EpisodeGuides;

use strict;
use warnings FATAL => 'all';

use Date::Calc qw( Add_Delta_Days Today Date_to_Time Time_to_Date This_Year );
use Date::Format;
use Date::Parse;
use JSON;
use LWP::ConnCache;
use Log::Log4perl;
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

    $LOGGER->info('time periode: ' . $first . ' -> ' . $today);

    my $url = 'http://api.tvmaze.com/shows/' . $serieID . '/episodes';
    $LOGGER->info('url: ' . $url);

    my $www = $self->{'www'};
    $www->get($url);
    unless ($www->success) {
        $LOGGER->error('Can\'t retrieve ' . $url . ': ' . $!);
        return undef;
    }

    my $content = $www->content; #decoded_by_headers => 1);
    $LOGGER->debug('content: ' . $content);
    my $json = JSON->new->allow_nonref;
    my $data = $json->decode($content);
    foreach my $entry (@$data) {
        my $season = $entry->{'season'};
        unless($season) {
            $LOGGER->info('Missing season : => skipping');
            next;
        }

        my $episode = $entry->{'number'};
        unless($episode) {
            $LOGGER->info('Missing episode : => skipping');
            next;
        }

        my $released = $entry->{'airdate'};
        unless($released) {
            $LOGGER->info('Missing release date : => skipping');
            next;
        }
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
