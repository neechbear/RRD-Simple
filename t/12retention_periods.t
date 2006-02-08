chdir('t') if -d 't';
my $rrdfile = -d 't' ? 't/12test.rrd' : '12test.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;
use Test::More tests => 31;
use lib qw(./lib ../lib);
use RRD::Simple ();

ok(my $rrd = RRD::Simple->new(),'new');

# RRD::Simple version 1.31 or less
#my %periods = (
#		'3years' => 164160000,
#		'year'   => 54446400,
#		'month'  => 18000000,
#		'week'   => 5400000,
#		'day'    => 900000,
#	);

#nicolaw@arwen:~/svn/RRD-Simple $ perl -I./lib/ -MRRD::Simple=:all -e'for (qw(day week month year mrtg 3years)) { $x="f";unlink $x;create($x,$_,ds=>"COUNTER");print "Retention period in seconds for $_ => ".retention_period($x)."\n";}'
my %periods = (
		'3years' => 118195200,
		'mrtg'   => 69120000,
		'year'   => 39398400,
		'month'  => 3348000,
		'week'   => 756000,
		'day'    => 108000,
	);

for my $p (keys %periods) {
	ok($rrd->create($rrdfile, $p,
			bytesIn => 'GAUGE',
			bytesOut => 'GAUGE',
		),"$p create");

	ok($rrd->update($rrdfile,
			bytesIn => 100,
			bytesOut => 100,
		),"$p update");

	ok(join(',',sort $rrd->sources($rrdfile)) eq 'bytesIn,bytesOut',
		"$p sources");

	ok(my $period = $rrd->retention_period($rrdfile),"$p retention_period");
	ok($period > ($periods{$p} * 0.95) &&
		$period < ($periods{$p} * 1.05),
		"$p retention_period result");

	unlink $rrdfile if -f $rrdfile;
}

unlink $rrdfile if -f $rrdfile;

1;

