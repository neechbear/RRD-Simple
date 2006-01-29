my $rrdfile = -d 't' ? 't/07test.rrd' : '07test.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;
use Test::More tests => 5;
use lib qw(./lib ../lib);
use RRD::Simple ();

ok(my $rrd = RRD::Simple->new(),'new');

ok($rrd->create($rrdfile, "year",
		bytesIn => 'GAUGE',
		bytesOut => 'GAUGE',
		faultsPerSec => 'COUNTER'
	),'create');

ok($rrd->update($rrdfile,
		bytesIn => 10039,
		bytesOut => 389,
		faultsPerSec => 4
	),'update');

#
# Updating a data source with incorrect case while perl
# warnings are enabled will cause a warning message to be
# printed. This might alarm people if it is output during
# the unit tests, so we will disable warnings for this
# part of the tests.
#

my $oldW = $^W; $^W = 0;

ok($rrd->update($rrdfile,time+1,
		bytesIn => 11003,
		BytesOUT => 201,
		faultsPerSec => 2
	),'update');

$^W = $oldW;

ok(join(',',sort $rrd->sources($rrdfile)) eq 'bytesIn,bytesOut,faultsPerSec',
	'sources');

unlink $rrdfile if -f $rrdfile;

