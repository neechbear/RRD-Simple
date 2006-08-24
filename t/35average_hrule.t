# $Id: 35last_value.t 739 2006-08-20 19:55:00Z nicolaw $

my $rrdfile = -d 't' ? 't/35test.rrd' : '35test.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;

BEGIN {
	use Test::More;
	eval "use RRDs";
	plan skip_all => "RRDs.pm *MUST* be installed!" if $@;
	plan skip_all => "RRDs version less than 1.2" if $RRDs::VERSION < 1.2;
	plan tests => 183 if !$@;
}

use lib qw(./lib ../lib);
use RRD::Simple 1.40 ();

ok(my $rrd = RRD::Simple->new(),'new');

my $end = time();
my $start = $end - (60 * 60 * 3);

ok($rrd->create($rrdfile,'day',
		knickers => 'GAUGE',
	),'create');

my $lastValue = 0;
my $x = rand ( 10 );
for (my $t = $start; $t <= $end; $t += 60) {
	$lastValue = ( cos($t / 1000 ) + rand(2) ) + $x;
	$lastValue = 6 if $lastValue > 6;
	ok($rrd->update($rrdfile,$t,
			knickers => $lastValue,
		),'update');
}

$rrd->graph($rrdfile,
		sources => [ qw(knickers) ],
		'HRULE:knickersAVERAGE#00ff77:KnickersAvg' => '',
	);

unlink $rrdfile if -f $rrdfile;
unlink '35test-daily.png' if -f '35test-daily.png';

1;

