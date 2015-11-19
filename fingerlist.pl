#!/usr/bin/perl

use strict;
use warnings;

die "Usage: $0 in\n" unless $#ARGV == 0;

my %pk = ();

open IN, $ARGV[0];
do { do { s/[^[:print:]]/./g; /(\w+)/; print "$1\n" } if defined $_ } while read IN, $_, 1063;
close IN;
