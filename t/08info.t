my $rrdfile = -d 't' ? 't/08test.rrd' : '08test.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;
use Test::More tests => 4;
use lib qw(./lib ../lib);
use RRD::Simple ();

ok(RRD::Simple->create($rrdfile,
		foo => 'GAUGE',
		bar => 'COUNTER'
	),'create');

ok(RRD::Simple->update($rrdfile,
		foo => 1024,
		bar => 4096,
	),'update');

my $info = {};
ok($info = RRD::Simple->info($rrdfile),'get info'); 
ok($info->{ds}->{foo}->{type} eq 'GAUGE','check info');

unlink $rrdfile if -f $rrdfile;

1;

