#!/usr/bin/perl -w

use strict;

die "I am probably too Linux specific" unless $^O =~ /linux/i;

# cpu
for (`iostat -c`) {
	chomp;
	if (my ($user,$nice,$sys,$iowait,$idle) = $_ =~
			/^\s+([0-9\.]+)\s+([0-9\.]+)\s+([0-9\.]+)\s+
			([0-9\.]+)\s+([0-9\.]+)\s*$/x) {
		print "avgcpu\tuser=GAUGE=$user\tnice=GAUGE=$nice\t".
				"sys=GAUGE=$sys\tiowait=GAUGE=$iowait\t".
				"idle=GAUGE=$idle\n";
	}
}

# fd
if (open(FH,"</proc/sys/fs/file-nr")) {
	local $_ = <FH>;
	close(FH);
	chomp;
	my ($allocated,$maxopen) = split(/\s+/,$_);;

}

memory usage			memory.usage
swap usage				swap.usage

network connections		network.connections.<protocol>
						network.connections.<state>

file descriptors		filesystem.descriptiors

network traffic			network.throughput.<interface>.<tx|rx>.bytes
						network.throughput.<interface>.<tx|rx>.packets
						network.throughput.<interface>.<tx|rx>.errors

processes

load average
cpu utilisation

hdd temperature
cpu temperature

disk io
disk capacity

apache scoreboard
apache req/sec
apache bytes/sec
apache log bytes/sec




__END__
echo -n "fd:fd:TotalAllocated="
cat /proc/sys/fs/file-nr | sed -e's/\s\s*/,TotalFreeAllocated=/; s/\s\s*/,MaximumOpen=/;'

# $Id$

echo -n "loadavg:loadavg:1MinAvg=" && \
	cat /proc/loadavg | cut -d' ' -f1-3 | sed -e's/ /,5MinAvg=/; s/ /,15MinAvg=/;'

# $Id$

echo -n "meminfo:meminfo:"
#cat /proc/meminfo | sed -e's/^/,/; s/:\(.*\)\(kB\)/_\2=\1/; s/:/=/; s/\s\s*//;'
cat /proc/meminfo | sed -e's/^/,/; s/:\(.*\)\(kB\)/=\1/; s/:/=/; s/\s\s*//g;' | tr -d '\n' | cut -b2-;

# $Id$

cat /proc/net/dev | grep ':' | sed -e's/^\s*/network:/g; s/:\s*/:/g; s/\s\s*/,/g'

# $Id$

echo -n "processes:allusers:"
/bin/ps --no-heading -A -o "state,user" | sort > /tmp/proc.$$
echo -n "Total=`wc -l /tmp/proc.$$|awk '{print $1}'`"

for state in `cat /tmp/proc.$$|awk '{print $1}'|sort|uniq`
do
	num=`grep "$state" /tmp/proc.$$ | wc -l`
	echo -n ",$state=$num"
done
echo

