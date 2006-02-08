chdir('t') if -d 't';
my $rrdfile = -d 't' ? 't/05test.rrd' : '05test.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;
use Test::More tests => 12;
use lib qw(./lib ../lib);
use RRD::Simple qw(:all);
use vars qw($rra);

ok(create($rrdfile,
		bytesIn => 'GAUGE',
		bytesOut => 'GAUGE',
		faultsPerSec => 'COUNTER'
	),'create');

my $updated = time();
ok(update($rrdfile,
		bytesIn => 10039,
		bytesOut => 389,
		faultsPerSec => 0.4
	),'update');

ok(last_update($rrdfile) - $updated < 5 && last_update($rrdfile),
	'last_update');

ok(join(',',sort(sources($rrdfile))) eq 'bytesIn,bytesOut,faultsPerSec',
	'sources');

ok(my $period = retention_period($rrdfile),'retention_period');
ok($period > 39398000 && $period < 39399000,'retention_period result');

SKIP: {
	my $deep = 0;
	eval {
		require Test::Deep;
		Test::Deep->import();
		$deep = 1;
	};
	if (!$deep || $@) {
		skip 'Test::Deep not available', 1;
	}

	my $info = info($rrdfile);
	cmp_deeply(
			$info->{rra},
			$rra,
			"info rra",
		);
}

(my $imgbasename = $rrdfile) =~ s/\.rrd$//;

ok(graph($rrdfile,destination => './'),'graph');
#for (qw(daily weekly monthly annual 3years)) {
for (qw(daily weekly monthly annual)) {
	my $img = "$imgbasename-$_.png";
	ok(-f $img,"$img");
	unlink $img if -f $img;
}

unlink $_ for glob('*.png');
unlink $rrdfile if -f $rrdfile;

BEGIN {
	use vars qw($rra);
	$rra = [
                     {
                       'xff' => '0.5',
                       'pdp_per_row' => 1,
                       'cdp_prep' => undef,
                       'cf' => 'AVERAGE',
                       'rows' => 1800
                     },
                     {
                       'xff' => '0.5',
                       'pdp_per_row' => 30,
                       'cdp_prep' => undef,
                       'cf' => 'AVERAGE',
                       'rows' => 420
                     },
                     {
                       'xff' => '0.5',
                       'pdp_per_row' => 120,
                       'cdp_prep' => undef,
                       'cf' => 'AVERAGE',
                       'rows' => 465
                     },
                     {
                       'xff' => '0.5',
                       'pdp_per_row' => 1440,
                       'cdp_prep' => undef,
                       'cf' => 'AVERAGE',
                       'rows' => 456
                     },
                     {
                       'xff' => '0.5',
                       'pdp_per_row' => 1,
                       'cdp_prep' => undef,
                       'cf' => 'MAX',
                       'rows' => 1800
                     },
                     {
                       'xff' => '0.5',
                       'pdp_per_row' => 30,
                       'cdp_prep' => undef,
                       'cf' => 'MAX',
                       'rows' => 420
                     },
                     {
                       'xff' => '0.5',
                       'pdp_per_row' => 120,
                       'cdp_prep' => undef,
                       'cf' => 'MAX',
                       'rows' => 465
                     },
                     {
                       'xff' => '0.5',
                       'pdp_per_row' => 1440,
                       'cdp_prep' => undef,
                       'cf' => 'MAX',
                       'rows' => 456
                     }
                   ];
}

1;

