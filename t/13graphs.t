chdir('t') if -d 't';
my $rrdfile = -d 't' ? 't/13test.rrd' : '13test.rrd';
unlink $rrdfile if -f $rrdfile;

use strict;
use Test::More tests => 66;
use lib qw(./lib ../lib);
use RRD::Simple ();

ok(my $rrd = RRD::Simple->new(),'new');

my %periods = (
		'3years' => [ qw(3years annual monthly weekly daily) ],
		year     => [ qw(annual monthly weekly daily) ],
		month    => [ qw(monthly weekly daily) ],
		week     => [ qw(weekly daily) ],
		day      => [ qw(daily) ],
	);

for my $p (keys %periods) {
	ok($rrd->create($rrdfile, $p,
			bytesIn => 'GAUGE',
			bytesOut => 'GAUGE',
		),"$p create");

	ok($rrd->update($rrdfile,
			bytesIn => 100,
			bytesOut => 100,
		),"$p update");

	ok(join(',',sort $rrd->sources($rrdfile)) eq 'bytesIn,bytesOut',
		"$p sources");

	mkdir '13graphs';
	ok($rrd->graph($rrdfile,
			destination => './13graphs/',
			basename => 'foo',
			sources => [ qw(bytesOut) ],
			source_labels => { bytesOut => 'Kbps Out' },
			source_colors => [ qw(4499ff) ],
			line_thickness => 2,
		),"$p graph");

	for my $f (@{$periods{$p}}) {
		my $file = "./13graphs/foo-$f.png";
		ok(-f $file,"./13graphs/foo-$f.png exists");
		ok((stat($file))[7] > 1024,"./13graphs/foo-$f.png over 1024 bytes");
		ok(unlink($file),"unlink ./13graphs/foo-$f.png");
	}
	unlink '13graphs';

	unlink $rrdfile if -f $rrdfile;
}

unlink $rrdfile if -f $rrdfile;

