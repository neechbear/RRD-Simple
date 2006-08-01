#!/usr/bin/perl -w
############################################################
#
#   $Id$
#   rrd-server.cgi - Data gathering CGI script for RRD::Simple
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

# User defined constants
use constant BASEDIR => '/home/system/rrd';



use 5.6.1;
use warnings;
use strict;
use Socket;

print "Content-type: plain/text\n\n" unless exists $ENV{MOD_PERL};

my $remote_addr = $ENV{REMOTE_ADDR};
for (qw(HTTP_X_FORWARDED_FOR HTTP_VIA HTTP_CLIENT_IP HTTP_PROXY_CONNECTION
		FORWARDED_FOR X_FORWARDED_FOR X_HTTP_FORWARDED_FOR HTTP_FORWARDED)) {
	if (defined $ENV{$_} && $ENV{$_} =~ /([\d\.]+)/) {
		my $ip = $1;
		if (isIP($ip)) {
			$remote_addr = $ip;
			last;
		}
	}
}

unless ($remote_addr) {
	print "FAILED - NO REMOTE_ADDR\n";
	exit;
}

my $host = ip2host($remote_addr);
my $ip = host2ip($host);

(print "FAILED - FORWARD AND REVERSE DNS DO NOT MATCH\n" && exit)
	unless "$ip" eq "$remote_addr";

# Custom hostname flanges
$host = 'merry.tfb.net' if $ip eq (split(/\s+/,`host router.ntl.tfb.net 2>/dev/null`))[3];
$host = 'arwen.tfb.net' if $host eq 'nicolaw.arwen.tfb.net';
$host = 'aragorn' if $ip eq '62.189.112.129' || $ip eq '161.69.135.243';
$host = 'isle-of-cats.etla.org' if $ip eq '82.71.23.88';
$host = 'pandora' if $ip eq '10.163.10.200';
$host = 'tmgc.gametrust.com' if $ip eq '207.97.225.213';

if (open(PH,'|-', BASEDIR."/bin/rrd-server.pl -u $host")) {
	while (<>) {
		warn "$host $_";
		next unless /^[\w\.\-\_\d]+\s+[\d\.]+\s*$/;
		print PH $_;
	}
	close(PH);
	print "OKAY - $host\n";
} else {
	print "FAILED - UNABLE TO EXECUTE\n";
}

exit;


sub ip2host {
	my $ip = shift;
	my @numbers = split(/\./, $ip);
	my $ip_number = pack("C4", @numbers);
	my ($host) = (gethostbyaddr($ip_number, 2))[0];
	if (defined $host && $host) {
		return $host;
	} else {
		return $ip;
	}
}

sub isIP {
	return 0 unless defined $_[0];
	return 1 if $_[0] =~ /^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.
				(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.
				(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.
				(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/x;
	return 0;
}

sub resolve {
	return ip2host(@_) if isIP($_[0]);
	return host2ip(@_);
}

sub host2ip {
	my $host = shift;
	my @addresses = gethostbyname($host);
	if (@addresses > 0) {
		@addresses = map { inet_ntoa($_) } @addresses[4 .. $#addresses];
		return wantarray ? @addresses : $addresses[0];
	} else {
		return $host;
	}
}

1;


