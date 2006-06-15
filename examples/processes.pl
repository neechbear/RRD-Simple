#!/usr/bin/perl -w
############################################################
#
#   $Id$
#   processes.pl - Example script bundled as part of RRD::Simple
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
use RRD::Simple 1.35;

my %update = ();
eval "use Proc::ProcessTable";
unless ($@) {
	my $p = new Proc::ProcessTable("cache_ttys" => 1 );
	for (@{$p->table}) {
		$update{$_->{state}}++;
	}
} elsif (-f '/bin/ps' && -x '/bin/ps') {
	open(PH,'-|','/bin/ps -eo pid,s') || die $!;
	while (local $_ = <PH>) {
		if (/^\d+\s+(\w+)\s*$/) {
			$update{$1}++;
		}
	}
	close(PH) || warn $!;
}

use Data::Dumper;
print Dumper(\%update);

__END__

PROCESS STATE CODES
Here are the different values that the s, stat and state output specifiers
(header "STAT" or "S") will display to describe the state of a process.
D    Uninterruptible sleep (usually IO)
R    Running or runnable (on run queue)
S    Interruptible sleep (waiting for an event to complete)
T    Stopped, either by a job control signal or because it is being traced.
W    paging (not valid since the 2.6.xx kernel)
X    dead (should never be seen)
Z    Defunct ("zombie") process, terminated but not reaped by its parent.



