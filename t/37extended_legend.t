# $Id: 35average_hrule.t 965 2007-03-01 19:11:23Z nicolaw $

my $rrdfile = -d 't' ? 't/37test.rrd' : '37test.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;

BEGIN {
	use Test::More;
	eval "use RRDs";
	plan skip_all => "RRDs.pm *MUST* be installed!" if $@;
	plan skip_all => "RRDs version less than 1.2" if $RRDs::VERSION < 1.2;
	plan tests => 203 if !$@;
}

use lib qw(./lib ../lib);
use RRD::Simple 1.45 ();

ok(my $rrd = RRD::Simple->new,'new');

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

for my $file (glob('37test-*.png')) { unlink $file; }

my $str = $rrd->graph($rrdfile,
		extended_legend => '%1.1lf',
	);

for my $p (qw(daily)) {
	ok($str->{$p}->[0] eq '37test-daily.png', 'graph without sources: rtn filename');
	ok($str->{$p}->[2] =~ /^\d+$/ && $str->{$p}->[2] > 100, 'graph without sources: rtn width');
	ok($str->{$p}->[3] =~ /^\d+$/ && $str->{$p}->[3] > 100, 'graph without sources: rtn height');
}

ok(-e '37test-daily.png','created 37test-daily.png on disk');

unlink $rrdfile if -f $rrdfile;
unlink '37test-daily.png' if -f '37test-daily.png';
for my $file (glob('37test-*.png')) { unlink $file; }

1;

