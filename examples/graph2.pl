#!/bin/env perl

use strict;
use RRD::Simple ();

my $rrdfile = 'graph2.rrd';
my $end = time();
my $start = $end - (60 * 60 * 24 * 31);
my @ds = qw(nicola hannah jennifer hedley heather baya);

# A salt offset for putting random shit in as the data points later
my %offset = (map { $_ => (index("@ds",$_) * 2) } @ds);

# Make a new object
my $rrd = RRD::Simple->new();

unless (-f $rrdfile) {
	$rrd->create($rrdfile,
			map { $_ => 'GAUGE' } @ds
		);

	for (my $t = $start; $t <= $end; $t += 300) {
		$rrd->update($rrdfile,$t,
				# Put any old random crap in as the data points :)
				map { $_ => cos( (($t+($offset{$_}*500))/20000)-($offset{$_}*10) )
							* (100-$offset{$_}) } @ds
			);
	}
}

# Graph the data
$rrd->graph($rrdfile,
		title => 'Random Graph of Some People',
		'vertical-label' => 'Weirdness',
		'line-thickness' => 2
	);


