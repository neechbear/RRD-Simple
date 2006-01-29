#!/bin/env perl

use strict;
use lib qw(../lib);
use RRD::Simple;

my $rrd = new RRD::Simple;

my $rrdfile = 'disk-capacity.rrd';
my %capacity;
my %labels;

my @data = split(/\n/, ($^O =~ /linux/ ? `df -P` : `df`));
shift @data;

for (@data) {
	my ($fs,$blocks,$used,$avail,$capacity,$mount) = split(/\s+/,$_);
	next if ($fs eq 'none' || $mount =~ m#^/dev/#);

	if (my ($val) = $capacity =~ /(\d+)/) {
		(my $ds = $mount) =~ s/\//_/g;
		$labels{$ds} = $mount;
		$capacity{$ds} = $val;
	} 
}

$rrd->create($rrdfile,
		map { $_ => 'GAUGE' } sort keys %capacity
	) unless -f $rrdfile;

$rrd->update($rrdfile,
		map { $_ => $capacity{$_} } sort keys %capacity
	);

$rrd->graph($rrdfile,
		title          => 'Disk Capacity',
		line_thickness => 2,
		vertical_label => '% used',
		units_exponent => 0,
		upper_limit    => 100,
		sources        => [ sort keys %capacity ],
		source_labels  => [ map { $labels{$_} } sort keys %labels ],
		color          => [ qw(BACK#F5F5FF SHADEA#C8C8FF SHADEB#9696BE
					           ARROW#61B51B GRID#404852 MGRID#67C6DE) ],
	);


