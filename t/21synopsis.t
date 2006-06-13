# $Id$

chdir('t') if -d 't';
my $rrdfile = -d 't' ? 't/21test.rrd' : '21test.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;

BEGIN {
	use Test::More;
	eval "use RRDs";
	plan skip_all => "RRDs.pm *MUST* be installed!" if $@;
	plan tests => 5 if !$@;
}

use lib qw(./lib ../lib);
use RRD::Simple 1.35 ();

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

