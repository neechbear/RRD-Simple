#!/home/system/rrd/bin/perl -w
############################################################
#
#   $Id$
#   rrd-client.pl - Data gathering script for RRD::Simple
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

use 5.6.1;
use strict;
use warnings;
use vars qw($VERSION);

$VERSION = '0.01' || sprintf('%d', q$Revision$ =~ /(\d+)/g);

warn "This may only run on Linux 2.4 or higher kernel systems"
	unless `uname -s` =~ /Linux/i && `uname -r` =~ /^2\.[4-9]\./;

my @probes = qw(
		cpu_utilisation cpu_loadavg cpu_temp
		hdd_io mem_usage hdd_temp hdd_capacity
		net_traffic net_connections
		proc_state proc_filehandles
		apache_status apache_logs
	);

for my $probe (@probes) {
	eval {
		report($probe,eval "$probe();");
	};
	warn $@ if $@;
}

sub report {
	(my $probe = shift) =~ s/[_-]/\./g;
	my %data = @_;
	for my $k (sort keys %data) {
		printf("%s.%s.%s %s\n", time(),
			$probe, $k, $data{$k});
	}
}

exit;



sub cpu_temp {
	my $cmd = '/usr/bin/sensors';
	my %update = ();

	open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
	while (local $_ = <PH>) {
		if (my ($k,$v) = $_ =~ /^([^:]*\bCPU\b.*?):\s*\S*?([\d\.]+)\S*\s*/) {
			$k =~ s/\W//g; $k =~ s/Temp$//i;
			$update{$k} = $v;
		}
	}
	close(PH) || warn "Unable to close file handle PH for command '$cmd': $!\n";

	return %update;
}

sub apache_logs {
	my $dir = '/var/log/httpd';
	my %update = ();

	if (-d $dir) {
		opendir(DH,$dir) || die "Unable to open file handle for directory '$dir': $!\n";
		my @files = grep(!/^\./,readdir(DH));
		closedir(DH) || warn "Unable to close file handle for directory '$dir': $!\n";
		for (@files) {
			next if /\.(\d+|gz|bz2|Z|zip|old|bak|backup)$/i;
			next unless -f "$dir/$_";
			$update{$_} = (stat("$dir/$_"))[7];
		}
	}

	return %update;
}

sub apache_status {
	eval "use LWP::UserAgent";
	die "Please install LWP::UserAgent so that I can monitor Apache.\n" if $@;

	my $ua = LWP::UserAgent->new(
			agent => "$0 $VERSION",
			timeout => 5,
		);
	$ua->env_proxy;
	$ua->max_size(1024*250);

	my $url = 'http://localhost/server-status?auto';
	my %update = ();

	my %keys = (W => 'Write', G => 'GraceClose', D => 'DNS', S => 'Starting',
		L => 'Logging', R => 'Read', K => 'Keepalive', C => 'Closing',
		I => 'Idle', '_' => 'Waiting');

	my $response = $ua->get($url);
	if ($response->is_success) {
		for (split(/\n+|\r+/,$response->content)) {
			my ($k,$v) = $_ =~ /^\s*(.+?):\s+(.+?)\s*$/;
			$k =~ s/\s+//g; #$k = lc($k);
			if ($k eq 'Scoreboard') {
				my %x; $x{$_}++ for split(//,$v);
				for (keys %keys) {
					$update{"scoreboard.$keys{$_}"} = 
						defined $x{$_} ? $x{$_} : 0;
				}
			} else {
				$update{$k} = $v;
			}
		}
		$update{ReqPerSec} = $update{TotalAccesses};
		$update{BytesPerSec} = $update{TotalkBytes} * 1024;

	} else {
		warn "failed to get $url; ". $response->status_line ."\n";
	}

	return %update;
}

sub cpu_utilisation {
	my $cmd = '/usr/bin/vmstat 1 2';
	my @keys = ();
	my %update = ();
	my %labels = (wa => 'IO_Wait', id => 'Idle', sy => 'System', us => 'User');

	open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
	while (local $_ = <PH>) {
		next if /---/;
		s/^\s+|\s+$//g;
		if (/\d+/ && @keys) {
			@update{@keys} = split(/\s+/,$_);
		} else { @keys = split(/\s+/,$_); }
	}
	close(PH) || warn "Unable to close file handle PH for command '$cmd': $!\n";

	my @cpukeys = splice(@keys,-4,4);
	return ( map {( $labels{$_} || $_ => $update{$_} )} @cpukeys );
}

sub hdd_io {
	my $cmd = '/usr/bin/iostat -k';
	my %update = ();

	open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
	while (local $_ = <PH>) {
		if (my ($dev,$r,$w) = $_ =~ /^([\w\d]+)\s+\S+\s+\S+\s+\S+\s+(\d+)\s+(\d+)$/) {
			$update{"$dev.Read"} = $r*1024;
			$update{"$dev.Write"} = $w*1024;
		}
	}
	close(PH) || warn "Unable to close file handle PH for command '$cmd': $!\n";

	return %update;
}

sub mem_usage {
	my %update = ();

	if (-f '/proc/meminfo') {
		open(FH,'<','/proc/meminfo') || die "Unable to open '/proc/meminfo': $!\n";
		while (local $_ = <FH>) {
			if (my ($key,$value,$kb) = $_ =~ /^(\w+):\s+(\d+)\s*(kB)\s*$/i) {
				next unless $key =~ /^(MemTotal|MemFree|Buffers|Cached|SwapFree|SwapTotal)$/i;
				$value *= 1024 if defined $kb;
				if ($key =~ /^Swap/i) {
					$update{"swap.$key"} = $value;
				} else {
					$update{$key} = $value;
				}
			}
		}
		if (exists $update{"swap.SwapTotal"} && exists $update{"swap.SwapFree"}) {
			$update{"swap.SwapUsed"} = $update{"swap.SwapTotal"} - $update{"swap.SwapFree"};
			delete $update{"swap.SwapFree"};
		}
		close(FH) || warn "Unable to close '/proc/meminfo': $!\n";

	} else {
		eval "use Sys::MemInfo qw(totalmem freemem)";
		die "Please install Sys::MemInfo so that I can get memory information.\n" if $@;
		@update{qw(MemTotal MemFree)} = (totalmem(),freemem());
	}

	return %update;
}

sub hdd_temp {
	my $cmd = '/usr/sbin/hddtemp -q /dev/hd? /dev/sd?';
	my %update = ();

	open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
	while (local $_ = <PH>) {
		if (my ($dev,$temp) = $_ =~ m,^/dev/([a-z]+):\s+.+?:\s+(\d+)..?C,) {
			$update{$dev} = $temp;
		}
	}
	close(PH) || warn "Unable to close file handle PH for command '$cmd': $!\n";

	return %update;
}

sub hdd_capacity {
	my %update = ();
	my @data = split(/\n/, ($^O =~ /linux/ ? `df -P -x iso9660` : `df -P`));
	shift @data;

	for (@data) {
		my ($fs,$blocks,$used,$avail,$capacity,$mount) = split(/\s+/,$_);
		next if ($fs eq 'none' || $mount =~ m#^/dev/#);
		if (my ($val) = $capacity =~ /(\d+)/) {
			(my $ds = $mount) =~ s/\//_/g;
			$update{$ds} = $val;
		} 
	}

	return %update;
}

sub net_traffic {
	my @keys = ();
	my %update = ();

	open(FH,'<','/proc/net/dev') || die "Unable to open '/proc/net/dev': $!\n";
	while (local $_ = <FH>) {
		s/^\s+|\s+$//g;
		if ((my ($dev,$data) = $_ =~ /^(.+?):\s*(\d+.+)\s*$/) && @keys) {
			my @values = split(/\s+/,$data);
			for (my $i = 0; $i < @keys; $i++) {
				if ($keys[$i] eq 'TXbytes') {
					$update{"$dev.Transmit"} = $values[$i];
				} elsif ($keys[$i] eq 'RXbytes') {
					$update{"$dev.Receive"} = $values[$i];
				}
				#$update{"$dev.$keys[$i]"} = $values[$i];
			}
		} else {
			my ($rx,$tx) = (split(/\s*\|\s*/,$_))[1,2];
			@keys = (map({"RX$_"} split(/\s+/,$rx)), map{"TX$_"} split(/\s+/,$tx));
		}
	}
	close(FH) || warn "Unable to close '/proc/net/dev': $!\n";

	return %update;
}

sub proc_state {
	my $cmd = '/bin/ps -eo pid,s';
	my %update = ();
	my %keys = (D => 'IO wait', R => 'Run', S => 'Sleep', T => 'Stopped',
			W => 'Paging', X => 'Dead', Z => 'Zombie');

	if (-f '/bin/ps' && -x '/bin/ps') {
		open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
		while (local $_ = <PH>) {
			if (/^\d+\s+(\w+)\s*$/) {
				$update{$keys{$1}||$1}++;
			}
		}
		close(PH) || warn "Unable to close file handle for command '$cmd': $!\n";
		$update{$_} ||= 0 for values %keys;

	} else {
		eval "use Proc::ProcessTable";
		die "Please install /bin/ps or Proc::ProcessTable\n" if $@;
		my $p = new Proc::ProcessTable("cache_ttys" => 1 );
		for (@{$p->table}) {
			$update{$_->{state}}++;
		}
	}

	return %update;
}

sub cpu_loadavg {
	my %update = ();
	my @data = ();

	unless (-f '/proc/loadavg') {
		open(FH,'<','/proc/loadavg') || die "Unable to open '/proc/loadavg': $!\n";
		my $str = <FH>;
		close(FH) || warn "Unable to close '/proc/loadavg': $!\n";
		@data = split(/\s+/,$str);

	} else {
		@data = `uptime` =~ /([\d\.]+)[,\s]+([\d\.]+)[,\s]+([\d\.]+)\s*$/;
	}

	%update = (
		"1min"  => $data[0],
		"5min"  => $data[1],
		"15min" => $data[2],
		);

	return %update;
}

sub net_connections {
	my $cmd = '/bin/netstat -na';
	my %update = ();

	open(PH,'-|',$cmd) || die "Unable to open file handle for command '$cmd': $!\n";
	while (local $_ = <PH>) {
		if (my ($proto,$state) = $_ =~ /^(tcp|udp|raw)\s+.+\s+([A-Z_]+)\s*$/) {
			$update{$state}++;
		}
	}
	close(PH) || warn "Unable to close file handle for command '$cmd': $!\n";

	return %update;
}

sub proc_filehandles {
	my %update = ();

	open(FH,'<','/proc/sys/fs/file-nr') || die "Unable to open '/proc/sys/fs/file-nr': $!\n";
	my $str = <FH>;
	close(FH) || warn "Unable to close '/proc/sys/fs/file-nr': $!\n";
	@update{qw(Allocated Free Maximum)} = split(/\s+/,$str);
	$update{Used} = $update{Allocated} - $update{Free};

	return %update;
}



1;




