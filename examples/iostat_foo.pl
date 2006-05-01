#!/usr/bin/perl -w

use strict;
use RRD::Simple;

our $cmd = '/usr/bin/iostat -x 1';
our $ok = -1;

open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!";
while (local $_ = <PH>) {
	$ok++ if $ok < 1 && /^avg-cpu:/;
	next unless $ok > 0;
	next unless /^[hsm]d[a-z0-9]\s+/;
	my @x = split(/\s+/,$_);
	printf("%-10s %10s %10s\n",$x[0],$x[7],$x[8]);
}
close(PH) || die "Unable to close file handle PH for command '$cmd': $!";

