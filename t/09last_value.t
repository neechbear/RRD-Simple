my $rrdfile = -d 't' ? 't/09test.rrd' : '09test.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;
use Test::More tests => 7 + 2017;
use lib qw(./lib ../lib);
use RRD::Simple ();

ok(my $rrd = RRD::Simple->new(),'new');

my $end = time();
my $start = $end - (60 * 60 * 24 * 7);

ok($rrd->create($rrdfile,
		foo => 'GAUGE',
		bar => 'GAUGE'
	),'create');

my $lastValue = 0;
for (my $t = $start; $t <= $end; $t += 300) {
	$lastValue = int(rand(999));
	ok($rrd->update($rrdfile,$t,
			foo => $lastValue,
			bar => $lastValue+100
		),'update');
}

ok($rrd->last($rrdfile) == $end, 'last');

ok(join(',',sort($rrd->sources($rrdfile))) eq join(',',sort(qw(foo bar))),
	'sources');

#print "Last value inserted for 'bar' = " . ($lastValue + 100) . "\n";
#print "Last value inserted for 'foo' = " . $lastValue . "\n";

my %rtn;
ok(%rtn = $rrd->last_values($rrdfile),'last_values');

SKIP: {
	skip "last_values() method not yet completed", 2;
	ok($rtn{foo} == $lastValue, "$rtn{foo} == $lastValue (foo)");
	ok($rtn{bar} == ($lastValue + 100), "$rtn{bar} == ($lastValue + 100) (bar)");
}

unlink $rrdfile if -f $rrdfile;

