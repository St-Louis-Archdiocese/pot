#!/usr/bin/perl

use strict;
use warnings;

die "Usage: $0 in1 {in2 ...} out\n" unless $#ARGV >= 1;

my %pk = ();

my $out = pop @ARGV;
open OUT, ">$out";
foreach my $in ( @ARGV ) {
	open IN, $in;
	my $c = 0;
	do { do { $pk{$c++} = $_; print OUT "$_"; s/[^[:print:]]/./g; print "$_\n" } if defined $_ } while read IN, $_, 1063;
	close IN;
	print STDERR "$in\t$c++\n";
}
close OUT;
