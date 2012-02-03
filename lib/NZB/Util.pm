#!/usr/bin/perl -w

package NZB::Util;

use strict;
use warnings FATAL => 'all';

sub max {
	return (sort{ $a <=> $b }(@_))[$#_];
}

sub min {
	return (sort{ $a <=> $b }(@_))[0];
}

1;
