my $rrdfile = -d 't' ? 't/01test.rrd' : '01test.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;
use Test::More tests => 5;
use lib qw(./lib ../lib);
use RRD::Simple ();

# Create an interface object
ok(my $rrd = RRD::Simple->new(),'new');

# Create a new RRD file with 3 data sources called
# bytesIn, bytesOut and faultsPerSec. Data retention
# of a year is specified. (The data retention parameter
# is optional and not required).
ok($rrd->create($rrdfile, "year",
		bytesIn => 'GAUGE',
		bytesOut => 'GAUGE',
		faultsPerSec => 'COUNTER'
	),'create');

# Put some arbitary data values in the RRD file for same
# 3 data sources called bytesIn, bytesOut and faultsPerSec.
my $updated = time();
ok($rrd->update($rrdfile,
		bytesIn => 10039,
		bytesOut => 389,
		faultsPerSec => 0.4
	),'update');

# Get unixtime of when RRD file was last updated
ok($rrd->last($rrdfile) - $updated < 5 && $rrd->last($rrdfile),
	'last');

ok(join(',',sort $rrd->sources($rrdfile)) eq 'bytesIn,bytesOut,faultsPerSec',
	'sources');

unlink $rrdfile if -f $rrdfile;

1;

