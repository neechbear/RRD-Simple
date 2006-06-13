# $Id$

my $rrdfile = -d 't' ? 't/26add_source.rrd' : '26add_source.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;

BEGIN {
	use Test::More;
	my $okay = 1;
	for (qw(RRDs File::Temp File::Copy)) {
		eval "use $_";
		if ($@) {
			plan skip_all => "$_ *MUST* be installed!";
			$okay = 0;
		}
	}
	plan tests => 6 if $okay;
}

use lib qw(./lib ../lib);
use RRD::Simple 1.35 ();

ok(my $rrd = RRD::Simple->new(),'new');

ok($rrd->create($rrdfile, "year",
		bytesIn => 'GAUGE',
		bytesOut => 'GAUGE',
		faultsPerSec => 'COUNTER',
		bytesDropped => 'GAUGE'
	),'create');

ok(join(',',sort $rrd->sources($rrdfile)) eq 'bytesDropped,bytesIn,bytesOut,faultsPerSec',
	'sources');

SKIP: {
	my $info = {};
	ok($info = $rrd->info($rrdfile),'info');

#	skip("RRD file version $info->{rrd_version} is too new to add data source",2)
#		if ($info->{rrd_version}+1-1) > 1;

	ok($rrd->update($rrdfile,
			bytesIn => 10039,
			bytesOut => 389,
			totalFaults => 992
		),'update (add_source)');

	ok(join(',',sort $rrd->sources($rrdfile)) eq 'bytesDropped,bytesIn,bytesOut,faultsPerSec,totalFaults',
		'sources');
}

unlink $rrdfile if -f $rrdfile;

1;

