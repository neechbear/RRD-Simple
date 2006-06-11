#!/usr/bin/perl -w
############################################################
#
#   $Id: vmstat.pl 582 2006-06-10 18:17:26Z nicolaw $
#   vmstat.pl - Example script bundled as part of RRD::Simple
#
#   Copyright 2005,2006 Nicola Worthington
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

use strict;
use RRD::Simple 1.35;
use RRDs;

BEGIN {
	warn "This may only run on Linux 2.6 kernel systems"
		unless `uname -s` =~ /Linux/i && `uname -r` =~ /^2\.6\./;
}

my $cmd = '/usr/bin/vmstat 1 1';
my $rrd = new RRD::Simple;

my @keys = ();
my %update = ();
open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!";
while (local $_ = <PH>) {
	next if /---/;
	s/^\s+|\s+$//g;
	if (/\d+/ && @keys) {
		@update{@keys} = split(/\s+/,$_);
	} else { @keys = split(/\s+/,$_); }
}
close(PH) || die "Unable to close file handle PH for command '$cmd': $!";

my @cpukeys = splice(@keys,-4,4);
my %labels = (wa => 'IO wait', id => 'Idle', sy => 'System', us => 'User');

my $rrdfile = "vmstat-cpu.rrd";
$rrd->create($rrdfile, map { ($_ => 'GAUGE') } @cpukeys )
	unless -f $rrdfile;

$rrd->update($rrdfile, map {( $_ => $update{$_} )} @cpukeys );
$rrd->graph($rrdfile,
		line_thickness => 2,
		vertical_label => '% percent',
		source_labels => \%labels
	);


