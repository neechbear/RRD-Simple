#!/usr/bin/perl -w

use strict;
use integer;
use RRD::Simple;
use Time::Local;

my $rrd = '/home/system/colloquy/botbot/logs/botbot.rrd';
unless (-f $rrd) {
	RRD::Simple->create($rrd,
			OBSERVED => 'GAUGE',
			LIST => 'GAUGE',
			SHOUT => 'GAUGE'
		);
}

my $hits = {OBSERVED => {}, SHOUT => {}, LIST => {}};
my ($first,$last) = (0,0);
my $lastUpdate = RRD::Simple->last($rrd);
my %months = (qw(Jan 0 Feb 1 Mar 2 Arp 3 May 4 Jun 5
			Jul 6 Aug 7 Sep 8 Oct 9 Nov 10 Dec 11));

$|++;
while (<>) {
	if (my ($wday,$mon,$mday,$hour,$min,$sec,$year,$type) = $_
			=~ /^\[(...) (...) (..) (..):(..):(..) (....)\] \[(\S+)/) {
		$year -= 1900;
		my @val = split(/\s/,sprintf('%d %d %d %d %d %d',
				$sec,$min,$hour,$mday,$months{$mon},$year));

		my $time = timelocal(@val);
		next if $lastUpdate >= $time;
		$first ||= $time; $last = $time;

		if ($type =~ /^OBSERVED|LIST|SHOUT/) {
			print ".";
			$type = 'LIST' if $type =~ /^LIST/;
			my $period = ($time / 300) * 300;
			$hits->{$type}->{$period}++;
		}
	}
}
print "\n";

die "No new data" unless $first > $lastUpdate;
die "Wasn't anything new in the log files" unless $first && $last;
$first = ($first / 300) * 300;
$last = ($last / 300) * 300;

print join(', ',RRD::Simple->sources($rrd))."\n";
print RRD::Simple->last($rrd)."\n";

for (my $time = $first; $time <= $last; $time += 300) {
	my @vals;
	for my $type (keys %{$hits}) {
		push @vals, ($type,(exists $hits->{$type}->{$time} ?
						$hits->{$type}->{$time} : 0));
	}
	print "RRD::Simple->update('$rrd',$time,'".join("','",@vals)."');\n";
	eval{RRD::Simple->update($rrd,$time,@vals);};
}

RRD::Simple->graph($rrd,
		destination => '/home/system/apache/htdocs/talker',
		title => 'Talker Activity',
		width => 600,
		'vertical-label' => 'Messages',
		'units-exponent' => 0
	);


