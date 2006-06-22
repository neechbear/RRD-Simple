#!/home/system/rrd/bin/perl -w
############################################################
#
#   $Id$
#   rrd-simple-mon.pl - Data gathering script for RRD::Simple
#
#   Copyright 2006 Nicola Worthington
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
############################################################
# vim:ts=4:sw=4:tw=78

BEGIN {
	# This is a very linux specific script - it's crap
	die "This may only run on Linux 2.4 or higher kernel systems"
		unless `uname -s` =~ /Linux/i && `uname -r` =~ /^2\.[4-9]\./;

        # Ensure we can find RRDs.so for RRDs.pm
        eval "use RRDs";
        use constant BASEDIR => '/home/system/rrd';
        if ($@ && !defined $ENV{LD_LIBRARY_PATH}) {
                $ENV{LD_LIBRARY_PATH} = BASEDIR.'/lib';
                exec($0,@ARGV);
        }
}

use 5.6.1;
use strict;
use warnings;
use lib qw(../lib);
use RRDs;
use RRD::Simple 1.39;
use File::Path qw();

my $dir = BASEDIR.'/data/localhost';
File::Path::mkpath($dir) unless -d $dir;
chdir $dir || die "Unable to chdir to '$dir': $!";

my $rrd = new RRD::Simple;

my @colour_theme = (color => [ (
		'BACK#F5F5FF','SHADEA#C8C8FF','SHADEB#9696BE',
		'ARROW#61B51B','GRID#404852','MGRID#67C6DE',
	) ] );

my @thumbnail_theme = (lazy => "", only_graph => "", width => 100, height => 25);

my %update  = ();
my %labels  = ();
my @keys    = ();
my @data    = ();
my @sources = ();
my @types   = ();



#
# cpu-utilisation.rrd
# cpu-utilisation
#

my $rrdfile = 'cpu-utilisation.rrd';
my $cmd = '/usr/bin/vmstat 2 3';

open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!";
while (local $_ = <PH>) {
	next if /---/;
	s/^\s+|\s+$//g;
	if (/\d+/ && @keys) {
		@update{@keys} = split(/\s+/,$_);
	} else { @keys = split(/\s+/,$_); }
}
close(PH) || warn "Unable to close file handle PH for command '$cmd': $!";

my @cpukeys = splice(@keys,-4,4);
%labels = (wa => 'IO wait', id => 'Idle', sy => 'System', us => 'User');

$rrd->create($rrdfile, map { ($_ => 'GAUGE') } @cpukeys )
	unless -f $rrdfile;

$rrd->update($rrdfile, map {( $_ => $update{$_} )} @cpukeys );
write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => "cpu-utilisation",
		extended_legend => 1,
		title => 'CPU Utilisation',
		sources => [ qw(sy us wa id) ],
		source_drawtypes => [ qw(AREA STACK STACK STACK) ],
		source_colors => [ qw(ff0000 00ff00 0000ff ffffff) ],
		vertical_label => '% percent',
		source_labels => \%labels,
		upper_limit => 100,
		lower_limit => 0,
		rigid => "",
	));



#
# hdd-io-$dev.rrd
# hdd-io-$dev
#

$cmd = '/usr/bin/iostat -k';
%update = ();

open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!";
while (local $_ = <PH>) {
	if (my ($dev,$r,$w) = $_ =~ /^([\w\d]+)\s+\S+\s+\S+\s+\S+\s+(\d+)\s+(\d+)$/) {
		$update{$dev} = { 'read' => ($r*1024), 'write' => ($w*1024) };
	}
}
close(PH) || warn "Unable to close file handle PH for command '$cmd': $!";

for my $dev (keys %update) {
	my $rrdfile = "hdd-io-$dev.rrd";
	unless (-f $rrdfile) {
		$rrd->create($rrdfile, map { ($_ => 'DERIVE') }
				sort keys %{$update{$dev}} );
		RRDs::tune($rrdfile,'-i',"$_:0") for keys %{$update{$dev}};
	}

	$rrd->update($rrdfile, %{$update{$dev}});
	write_txt($rrd->graph($rrdfile, @colour_theme,
			basename => "hdd-io-$dev",
			title => "Hard Disk I/O: $dev",
			sources => [ qw(read write) ],
			source_labels => [ qw(Read Write) ],
			source_drawtypes => [ qw(AREA LINE1) ],
			source_colors => [ qw(00ee00 dd0000) ],
			vertical_label => 'bytes/sec',
		));
}



#
# mem-usage.rrd
# mem-usage, mem-swap
#

$rrdfile = 'mem-usage.rrd';
%update = ();

if (-f '/proc/meminfo') {
	open(FH,'<','/proc/meminfo') || die "Unable to open '/proc/meminfo': $!";
	while (local $_ = <FH>) {
		if (my ($key,$value,$kb) = $_ =~ /^(\w+):\s+(\d+)\s*(kB)\s*$/i) {
			next unless $key =~ /(MemTotal|MemFree|Buffers|Cached|SwapFree|SwapTotal)/i;
			$value *= 1024 if defined $kb;
			$update{$key} = $value;
		}
	}
	close(FH) || warn "Unable to close '/proc/meminfo': $!";
	$update{SwapUsed} = $update{SwapTotal} - $update{SwapFree}
		if exists $update{SwapTotal} && exists $update{SwapFree};
	delete $update{SwapFree};

} else {
	eval "use Sys::MemInfo qw(totalmem freemem)";
	die "Please install Sys::MemInfo so that I can get memory information.\n" if $@;
	@update{qw(MemTotal MemFree)} = (totalmem(),freemem());
}

$rrd->create($rrdfile,
		map { ( $_ => 'GAUGE' ) } sort keys %update
	) unless -f $rrdfile;

$rrd->update($rrdfile, %update);

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => 'mem-usage',
		title => 'Memory Usage',
		base => 1024,
		vertical_label => 'bytes',
		sources => [ ('MemTotal',grep(/^(Buffers|Cached)$/i, keys %update),'MemFree') ],
		source_drawtypes => {
				MemTotal => 'LINE2',
				Cached   => 'AREA',
				Buffers  => 'STACK',
				MemFree  => 'LINE1',
			},
		source_colors => {
				MemTotal => 'ff0000',
				MemFree  => '00ff00',
				Cached   => '0000ff',
				Buffers  => '00ffff',
			},
	));

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename         => 'mem-swap',
		title            => 'Swap Usage',
		base             => 1024,
		vertical_label   => 'bytes',
		sources          => [ qw(SwapTotal SwapUsed) ],
		source_drawtypes => [ qw(LINE2 AREA) ],
	)) if grep(/^SwapUsed$/, $rrd->sources($rrdfile));



#
# hdd-temp.rrd
# hdd-temp
#

$rrdfile = 'hdd-temp.rrd';
$cmd = '/usr/sbin/hddtemp -q /dev/hd? /dev/sd?';
%update = ();

open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!";
while (local $_ = <PH>) {
	if (my ($dev,$temp) = $_ =~ m,^/dev/([a-z]+):\s+.+?:\s+(\d+)..?C,) {
		$update{$dev} = $temp;
	}
}
close(PH) || warn "Unable to close file handle PH for command '$cmd': $!";

if (keys %update) {
	$rrd->create($rrdfile,
			map { ( $_ => 'GAUGE' ) } sort keys %update
		) unless -f $rrdfile;

	$rrd->update($rrdfile, %update);

	write_txt($rrd->graph($rrdfile, @colour_theme,
			basename => 'hdd-temp',
			extended_legend => 1,
			title => 'Hard Disk Temperature',
			vertical_label => 'Celsius',
			sources => [ sort $rrd->sources($rrdfile) ],
		));
}



#
# hdd-capacity.rrd
# hdd-capacity
#

$rrdfile = 'hdd-capacity.rrd';
%update = ();
%labels = ();

@data = split(/\n/, ($^O =~ /linux/ ? `df -P -x iso9660` : `df -P`));
shift @data;

for (@data) {
	my ($fs,$blocks,$used,$avail,$capacity,$mount) = split(/\s+/,$_);
	next if ($fs eq 'none' || $mount =~ m#^/dev/#);

	if (my ($val) = $capacity =~ /(\d+)/) {
		(my $ds = $mount) =~ s/\//_/g;
		$labels{$ds} = $mount;
		$update{$ds} = $val;
	} 
}

$rrd->create($rrdfile,
		map { ( $_ => 'GAUGE' ) } sort keys %update
	) unless -f $rrdfile;

$rrd->update($rrdfile, %update);

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename       => 'hdd-capacity',
		extended_legend => 1,
		title          => 'Disk Capacity',
		line_thickness => 2,
		vertical_label => '% used',
		units_exponent => 0,
		upper_limit    => 100,
		sources        => [ sort keys %update ],
		source_labels  => [ map { $labels{$_} } sort keys %labels ],
	));



#
# net-traffic-$dev.rrd
# net-traffic-$dev
#

@keys = ();
%update = ();

open(FH,'<','/proc/net/dev') || die "Unable to open '/proc/net/dev': $!";
while (local $_ = <FH>) {
	s/^\s+|\s+$//g;
	if ((my ($dev,$data) = $_ =~ /^(.+?):\s*(\d+.+)\s*$/) && @keys) {
		$update{$dev} = [ split(/\s+/,$data) ];
	} else {
		my ($rx,$tx) = (split(/\s*\|\s*/,$_))[1,2];
		@keys = (map({"RX$_"} split(/\s+/,$rx)), map{"TX$_"} split(/\s+/,$tx));
	}
}
close(FH) || warn "Unable to close '/proc/net/dev': $!";

for my $dev (keys %update) {
	my $rrdfile = "net-traffic-$dev.rrd";
	unless (-f $rrdfile) {
		$rrd->create($rrdfile, map { ($_ => 'DERIVE') } grep(/^.Xbytes$/,@keys));
		RRDs::tune($rrdfile,'-i',"$_:0") for @keys;
	}

	my %tmp;
	for (my $i = 0; $i < @keys; $i++) {
		$tmp{$keys[$i]} = $update{$dev}->[$i]
			if $keys[$i] =~ /^.Xbytes$/;
	}

	$rrd->update($rrdfile, %tmp);
	write_txt($rrd->graph($rrdfile, @colour_theme,
			basename => "net-traffic-$dev",
			extended_legend => 1,
			title => "Network Traffic: $dev",
			vertical_label => 'bytes/sec',
			sources => [ qw(TXbytes RXbytes) ],
			source_labels => [ qw(Transmit Recieve) ],
			source_drawtypes => [ qw(AREA LINE) ],
			source_colors => [ qw(00dd00 0000dd) ],
		));
}



#
# proc-state.rrd
# proc-state
#

$rrdfile = 'proc-state.rrd';
$cmd = '/bin/ps -eo pid,s';
%update = ();

if (-f '/bin/ps' && -x '/bin/ps') {
	open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!";
	while (local $_ = <PH>) {
		if (/^\d+\s+(\w+)\s*$/) {
			$update{$1}++;
		}
	}
	close(PH) || warn "Unable to close file handle for command '$cmd': $!";
} else {
	eval "use Proc::ProcessTable";
	die "Please install /bin/ps or Proc::ProcessTable\n" if $@;
	my $p = new Proc::ProcessTable("cache_ttys" => 1 );
	for (@{$p->table}) {
		$update{$_->{state}}++;
	}
}

$rrd->create($rrdfile, map { ($_ => 'GAUGE') } sort keys %update )
	unless -f $rrdfile;

@sources = sort $rrd->sources($rrdfile);
$update{$_} ||= 0 for @sources;
$rrd->update($rrdfile, %update);

%labels = (D => 'IO wait', R => 'Run', S => 'Sleep', T => 'Stopped',
			W => 'Paging', X => 'Dead', Z => 'Zombie');

@types = ('AREA');
for (my $i = 2; $i <= @sources; $i++) {
	push @types, 'STACK';
}

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => "proc-state",
		extended_legend => 1,
		title => 'Processes',
		vertical_label => 'Processes',
		sources => \@sources,
		source_drawtypes => \@types,
		source_labels => \%labels,
	));



#
# cpu-loadavg.rrd
# cpu-loadavg
#

$rrdfile = 'cpu-loadavg.rrd';
@data = `uptime` =~ /([\d\.]+)[,\s]+([\d\.]+)[,\s]+([\d\.]+)\s*$/;

$rrd->create($rrdfile, map { ($_ => 'GAUGE') } qw(1min 5min 15min))
	unless -f $rrdfile;

$rrd->update($rrdfile,
		'1min' => $data[0],
		'5min' => $data[1],
		'15min' => $data[2],
	);

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => "cpu-loadavg",
		extended_legend => 1,
		title => 'Load Average',
		sources => [ qw(1min 5min 15min) ], 
		source_colors => [ qw(ffbb00 cc0000 0000cc) ],
		source_drawtypes => [ qw(AREA LINE1 LINE1) ],
		vertical_label => 'Load',
	));



#
# net-connections.rrd
# net-connections
#

$rrdfile = 'net-connections.rrd';
$cmd = '/bin/netstat -na';
%update = ();

open(PH,'-|',$cmd) || die "Unable to open file handle for command '$cmd': $!";
while (local $_ = <PH>) {
	if (my ($proto,$state) = $_ =~ /^(tcp|udp|raw)\s+.+\s+([A-Z_]+)\s*$/) {
		$update{$state}++;
	}
}
close(PH) || warn "Unable to close file handle for command '$cmd': $!";

$rrd->create($rrdfile, map {($_ => 'GAUGE')} keys %update) unless -f $rrdfile;
$rrd->update($rrdfile, %update);

@sources = $rrd->sources($rrdfile);
@types = ('AREA');
for (my $i = 2; $i < @sources; $i++) {
	push @types, 'STACK';
}
push @types, 'LINE2';

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => "net-connections",
		extended_legend => 1,
		title => 'Network Connections',
		sources => [ ('ESTABLISHED',
				grep(!/^(LISTEN|ESTABLISHED)$/,@sources),
				'LISTEN') ], 
		source_drawtypes => \@types,
		source_colors => { LISTEN => 'ffffff' },
		vertical_label => 'Connections',
	));



#
# proc-filehandles.rrd
# proc-filehandles
#

$rrdfile = 'proc-filehandles.rrd';
%update = ();

open(FH,'<','/proc/sys/fs/file-nr') || die "Unable to open '/proc/sys/fs/file-nr': $!";
my $str = <FH>;
close(FH) || warn "Unable to close '/proc/sys/fs/file-nr': $!";
@update{qw(allocated free maximum)} = split(/\s+/,$str);
$update{used} = $update{allocated} - $update{free};

$rrd->create($rrdfile, map {($_ => 'GAUGE')} keys %update) unless -f $rrdfile;
$rrd->update($rrdfile, %update);

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => "proc-filehandles",
		extended_legend => 1,
		title => 'File Handles',
		sources => [ qw(maximum allocated used free) ],
		source_labels => [ qw(Maximum Allocated Used Free) ],
		source_drawtypes => [ qw(LINE2 AREA LINE1 LINE1) ],
		vertical_label => 'Handles',
	));

exit;



#
# write_txt
#

sub write_txt {
	my %rtn = @_;
	while (my ($period,$data) = each %rtn) { 
		my $filename = shift @{$data};
		my %values = ();
		my $max_len = 0;
		for (@{$data->[0]}) {
			my ($ds,$k,$v) = split(/\s+/,$_);
			$values{$ds}->{$k} = $v;
			$max_len = length($ds) if length($ds) > $max_len;
		}
		if (open(FH,'>',"$filename.txt")) {
			printf FH "%s (%dx%d) %dK\n\n", $filename,
				$data->[1], $data->[2], (stat($filename))[7]/1024;
			for (sort keys %values) {
				printf FH "%-${max_len}s     min: %s, max: %s, last: %s\n", $_,
					$values{$_}->{min}, $values{$_}->{max}, $values{$_}->{last};
			}
			close(FH);
		}
	}
}


1;




