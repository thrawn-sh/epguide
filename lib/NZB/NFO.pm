#!/usr/bin/perl -w

package NZB::NFO;

use strict;
use warnings FATAL => 'all';

use Crypt::SSLeay;
use LWP::ConnCache;
use Log::Log4perl;
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

sub parse_imdb_nr($$) { #{{{1
    my ($self, $url) = @_;
    $LOGGER->debug('url: ' . $url);

    my $www = $self->{'www'};
    $www->get($url);
    unless ($www->success) {
        $LOGGER->error('Can\'t retrieve ' . $url . ': ' . $!);
        return undef;
    }

    if ($www->content() =~ /([\w:\/\.]*imdb\.[\w]{2,3}\/[\?\.\/\w\d]+)/) {
        my $imdb_nr = $1;
        $imdb_nr =~ s/[^\d]+//g;
        return $imdb_nr;
    }
    return undef;
} # }}}1

1;
