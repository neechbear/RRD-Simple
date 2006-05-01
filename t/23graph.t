# $Id$

chdir('t') if -d 't';
my $rrdfile = -d 't' ? 't/23test.rrd' : '23test.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;
use Test::More tests => 66+245;
use lib qw(./lib ../lib);
use RRD::Simple ();

use vars qw($rra %retention_periods %scheme_graphs @schemes);
require 'answers.pl';

ok(my $rrd = RRD::Simple->new(),'new');

for my $p (keys %scheme_graphs) {
	ok($rrd->create($rrdfile, $p,
			bytesIn => 'GAUGE',
			bytesOut => 'GAUGE',
		),"$p create");

	for (my $t = 50; $t >= 1; $t--) {
		ok($rrd->update($rrdfile,time-(110*$t),
				bytesIn => 100,
				bytesOut => 50,
			),"$p update");
	}

	ok(join(',',sort $rrd->sources($rrdfile)) eq 'bytesIn,bytesOut',
		"$p sources");

	mkdir '13graphs';
	ok($rrd->graph($rrdfile,
			destination => './13graphs/',
			basename => 'foo',
			sources => [ qw(bytesIn bytesOut) ],
			source_labels => { bytesOut => 'Kbps Out' },
			source_colors => [ qw(4499ff e33f00) ],
			source_drawtypes => [ qw(AREA LINE) ],
			line_thickness => 2,
		),"$p graph");

	for my $f (@{$scheme_graphs{$p}}) {
		my $file = "./13graphs/foo-$f.png";
		ok(-f $file,"create ./13graphs/foo-$f.png");
		SKIP: {
			skip("./13graphs/foo-$f.png wasn't created",2) unless -f $file;
			ok((stat($file))[7] > 1024,"./13graphs/foo-$f.png is at least 1024 bytes");
			ok(unlink($file),"unlink ./13graphs/foo-$f.png");
		}
	}

	unlink $_ for glob('./13graphs/*');
	rmdir '13graphs' || unlink '13graphs';
	unlink $rrdfile if -f $rrdfile;
}

unlink $rrdfile if -f $rrdfile;

1;

