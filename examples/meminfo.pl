#!/usr/bin/perl -w
############################################################
#
#   $Id$
#   meminfo.pl - Example script bundled as part of RRD::Simple
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

use strict;
use lib qw(../lib);
use RRD::Simple 1.35;

my $rrd = new RRD::Simple;
my $rrdfile = 'meminfo.rrd';
my %memory = ();

eval "use Sys::MemInfo qw(totalmem freemem)";
unless ($@) {
	@memory{qw(total free)} = (totalmem(),freemem());
} else {
	die "Please install Sys::MemInfo so that I can get memory information.\n"
		unless -f '/proc/meminfo' && -r '/proc/meminfo';
	open(FH,'<','/proc/meminfo') || die "Unable to open '/proc/meminfo': $!";
	while (local $_ = <FH>) {
		if (my ($key,$value,$kb) = $_ =~ /^(\w+):\s+(\d+)\s*(kB)\s*$/i) {
			$value *= 1024 if defined $kb;
			$memory{$key} = $value;
		}
	}
	close(FH) || warn "Unable to close '/proc/meminfo': $!";
}

$rrd->create($rrdfile,
		map { ( $_ => 'GAUGE' ) } sort keys %memory
	) unless -f $rrdfile;

$rrd->update($rrdfile, %memory);

$rrd->graph($rrdfile,
		base => 1024,
		title => 'Memory Usage',
		line_thickness => 2,
		vertical_label => 'bytes',
		sources => [ grep(/^(mem)?(total|free|buffers|cached|swap)$/i, keys %memory) ],
	);


