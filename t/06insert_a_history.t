my $rrdfile = -d 't' ? 't/06test.rrd' : '06test.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;
use Test::More tests => 4 + 8929;
use lib qw(./lib ../lib);
use RRD::Simple ();

ok(my $rrd = RRD::Simple->new(),'new');

my $end = time() - 3600;
my $start = $end - (60 * 60 * 24 * 31);
my @ds = qw(nicola hannah jennifer hedley heather baya);

ok($rrd->create($rrdfile,
		map { $_ => 'GAUGE' } @ds
	),'create');

for (my $t = $start; $t <= $end; $t += 300) {
	ok($rrd->update($rrdfile,$t,
			map { $_ => int(rand(100)) } @ds
		),'update');
}

ok($rrd->last($rrdfile) == $end, 'last');

ok(join(',',sort $rrd->sources($rrdfile)) eq join(',',sort(@ds)),
	'sources');

unlink $rrdfile if -f $rrdfile;

