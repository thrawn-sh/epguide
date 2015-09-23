#!/usr/bin/perl -w

package EpisodeGuide::Message;

use strict;
use warnings FATAL => 'all';

sub new {
    my $class  = shift;
    my %params = @_;

    my $self = {
        stream   => $params{'output'},
        messages => { },
    };

    bless $self, $class;
    return $self;
}

sub getMessageForBox($$) {
    my ($self, $boxName) = @_;
    return $self->{'messages'}->{$boxName};
}

sub hasMessages($) {
    my ($self) = @_;

    my $messages = $self->{'messages'};
    my $size     = scalar keys %$messages;
    return ($size > 0);
}

sub write($$$) {
    my ($self, $text, $boxName) = @_;

    local *OUT = $self->{'stream'};
    print OUT $text;

    if (defined $boxName) {
        my $messages = $self->{'messages'};
        my $box   = $messages->{$boxName};
        if (defined $box) {
            $box .= $text;
        } else {
            $box  = $text;
        }
        $messages->{$boxName} = $box;
    }
}

sub DESTROY($) {
    my ($self) = @_;

    local *OUT = $self->{'stream'};
    close(OUT);
}

1;