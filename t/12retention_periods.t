chdir('t') if -d 't';
my $rrdfile = -d 't' ? 't/12test.rrd' : '12test.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;
use Test::More tests => 26;
use lib qw(./lib ../lib);
use RRD::Simple ();

ok(my $rrd = RRD::Simple->new(),'new');

my %periods = (
		'3years' => 164160000,
		year     => 54446400,
		month    => 18000000,
		week     => 5400000,
		day      => 900000,
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

