#!/usr/bin/perl -w

use strict;

use constant RRD_CMD => '/home/rrd/bin/rrd-server.pl -u %s';
use constant SNMP_CMDS => (
		'/usr/bin/snmpwalk -c public -v 2c %s IF-MIB::ifInOctets',
		'/usr/bin/snmpwalk -c public -v 2c %s IF-MIB::ifOutOctets'
	);
use constant HOSTS => qw(
		switch1.company.com
		switch2.company.com
		switch3.company.com
		switch4.company.com
	);

for my $host (HOSTS) {
	my %update;
	my $time = time;

	for my $cmd (SNMP_CMDS) {
		$cmd = sprintf($cmd,$host);
		print "$cmd\n";
		for (qx($cmd)) {
			if (my ($key,$port,$value) = $_ =~ /(if(?:In|Out)Octets)\.(\d+)\s*=\s*(?:Counter32:\s*)?(\d+)/i) {
				$update{"$time.switch.traffic.$key"} += $value;
				$update{"$time.switch.traffic.port$port.$key"} = $value;
			}
		}
	}

	my $str;
	$str .= "$_ $update{$_}\n" for sort keys %update;
	my $cmd = sprintf(RRD_CMD,$host);
	print "$cmd\n";
	open(PH,'|-',$cmd) || die "Unable to open file handle PH for command '$cmd': $!";
	print PH $str;
	close(PH) || die "Unable to close file hadle PH for command '$cmd': $!";
}

