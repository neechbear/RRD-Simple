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

use 5.004;
use strict;
use warnings;
use vars qw($VERSION);

$VERSION = '0.01' || sprintf('%d', q$Revision$ =~ /(\d+)/g);

# Default list of probes
my @probes = qw(
		cpu_utilisation cpu_loadavg cpu_temp
		hdd_io mem_usage hdd_temp hdd_capacity
		net_traffic net_connections
		proc_state proc_filehandles
		apache_status apache_logs
	);

# Get command line options
my %opt = ();
eval "require Getopt::Std";
Getopt::Std::getopts('p:i:x:h', \%opt) unless $@;
(display_help() && exit) if defined $opt{h};

# Filter on probe include list
if (defined $opt{i}) {
	my $inc = join('|',split(/\s*,\s*/,$opt{i}));
	@probes = grep(/(^|_)($inc)(_|$)/,@probes);
}

# Filter on probe exclude list
if (defined $opt{x}) {
	my $exc = join('|',split(/\s*,\s*/,$opt{x}));
	@probes = grep(!/(^|_)($exc)(_|$)/,@probes);
}

# Run the probes one by one
die "Nothing to probe!\n" unless @probes;
my $post = '';
for my $probe (@probes) {
	eval {
		my $str = report($probe,eval "$probe();");
		if (defined $opt{p}) {
			$post .= $str;
		} else {
			print $str;
		}
	};
	warn $@ if $@;
}

# HTTP POST the data if asked to
print(scalar basic_http('POST',$opt{p},30,$post), "\n") if $opt{p};

exit;



# Report the data
sub report {
	(my $probe = shift) =~ s/[_-]/\./g;
	my %data = @_;
	my $str = '';
	for my $k (sort keys %data) {
		$str .= sprintf("%s.%s.%s %s\n", time(),
			$probe, $k, $data{$k});
	}
	return $str;
}

# Display help
sub display_help {
	print qq{Syntax: $0 [-i probe1,probe2,..|-x probe1,probe2,..] [-p url] [-h]
     -i <probes>     Include a list of comma seperated probes
     -x <probes>     Exclude a list of comma seperated probes
     -p <url>        HTTP POST data to the specified URL
     -h              Display this help\n};
}

# Basic HTTP client if LWP is unavailable
sub basic_http {
	my ($method,$url,$timeout,$data) = @_;
	$method ||= 'GET';
	$url ||= 'http://localhost/';
	$timeout ||= 5;

	my ($scheme,$host,$port,$path) = $url =~ m,^(https?://)([\w\d\.\-]+)(?::(\d+))?(.*),i;
	$scheme ||= 'http://';
	$host ||= 'localhost';
	$path ||= '/';
	$port ||= 80;

	my $str = '';
	eval "use Socket";
	return $str if $@;

	eval {
		local $SIG{ALRM} = sub { die "TIMEOUT\n" };
		alarm $timeout;

		my $iaddr = inet_aton($host) || die;
		my $paddr = sockaddr_in($port, $iaddr);
		my $proto = getprotobyname('tcp');
		socket(SOCK, AF_INET(), SOCK_STREAM(), $proto) || die "socket: $!";
		connect(SOCK, $paddr) || die "connect: $!";

		select(SOCK); $| = 1; 
		select(STDOUT);

		# Send the HTTP request
		print SOCK "$method $path HTTP/1.1\n";
		print SOCK "Host: $host". ("$port" ne "80" ? ":$port" : '') ."\n";
		print SOCK "User-Agent: $0 $VERSION\n";
		if ($post && $method eq 'POST') {
			print SOCK "Content-Length: ". length($post) ."\n";
			print SOCK "Content-Type: application/x-www-form-urlencoded\n";
		}
		print SOCK "\n";
		print SOCK $post if $post && $method eq 'POST';

		my $body = 0;
		while (local $_ = <SOCK>) {
			$str .= $_ if $body;
			$body = 1 if /^\s*$/;
		}
		close(SOCK);
		alarm 0;
	};

	warn $@ if $@ && $post;
	return wantarray ? split(/\n/,$str) : $str;
}



#
# Probes
#

sub cpu_temp {
	my $cmd = '/usr/bin/sensors';
	return () unless -f $cmd;
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
	return () unless -d $dir;
	my %update = ();

	if (-d $dir) {
		opendir(DH,$dir) || die "Unable to open file handle for directory '$dir': $!\n";
		my @files = grep(!/^\./,readdir(DH));
		closedir(DH) || warn "Unable to close file handle for directory '$dir': $!\n";
		for (@files) {
			next if /\.(\d+|gz|bz2|Z|zip|old|bak|pid|backup)$/i || /[_\.\-]pid$/;
			my $file = "$dir/$_";
			next unless -f $file;
			s/[\.\-]/_/g;
			$update{$_} = (stat($file))[7];
		}
	}

	return %update;
}

sub apache_status {
	my @data = ();
	my %update = ();

	my $timeout = 5;
	my $url = 'http://localhost/server-status?auto';
	my %keys = (W => 'Write', G => 'GraceClose', D => 'DNS', S => 'Starting',
		L => 'Logging', R => 'Read', K => 'Keepalive', C => 'Closing',
		I => 'Idle', '_' => 'Waiting');


	eval "use LWP::UserAgent";
	unless ($@) {
		my $ua = LWP::UserAgent->new(agent => "$0 $VERSION", timeout => $timeout);
		$ua->env_proxy;
		$ua->max_size(1024*250);
		my $response = $ua->get($url);
		if ($response->is_success) {
			@data = split(/\n+|\r+/,$response->content);
		} else {
			warn "failed to get $url; ". $response->status_line ."\n";
		}
	} else {
		@data = basic_http('GET',$url,$timeout);
	}

	for (@data) {
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

	$update{ReqPerSec} = int($update{TotalAccesses})
		if defined $update{TotalAccesses};
	$update{BytesPerSec} = int($update{TotalkBytes} * 1024)
		if defined $update{TotalkBytes};

	return %update;
}

sub cpu_utilisation {
	my $cmd = '/usr/bin/vmstat';
	return () unless -f $cmd;
	$cmd .= ' 1 2';

	my @keys = ();
	my %update = ();
	my %labels = (wa => 'IO_Wait', id => 'Idle', sy => 'System', us => 'User');

	open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
	while (local $_ = <PH>) {
		s/^\s+|\s+$//g;
		if (/\s+\d+\s+\d+\s+\d+\s+/ && @keys) {
			@update{@keys} = split(/\s+/,$_);
		} else { @keys = split(/\s+/,$_); }
	}
	close(PH) || warn "Unable to close file handle PH for command '$cmd': $!\n";

	$update{$_} ||= 0 for keys %labels;
	return ( map {( $labels{$_} || $_ => $update{$_} )} keys %labels );
}

sub hdd_io {
	my $cmd = -f '/usr/bin/iostat' ? '/usr/bin/iostat' : '/usr/sbin/iostat';
	return () unless -f $cmd;
	return () unless $^O eq 'linux';
	$cmd .= ' -k';

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
	my $cmd = -f '/usr/bin/free' ? '/usr/bin/free' : '/bin/free';
	my @keys = ();

	if ($^O eq 'linux' && -f $cmd && -x $cmd) {
		$cmd .= ' -b';
		open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
		while (local $_ = <PH>) {
			if (@keys && /^Mem:\s*(\d+.+)\s*$/i) {
				my @values = split(/\s+/,$1);
				for (my $i = 0; $i < @values; $i++) {
					$update{ucfirst($keys[$i])} = $values[$i];
				}
				$update{Used} = $update{Used} - $update{Buffers} - $update{Cached};

			} elsif (@keys && /^Swap:\s*(\d+.+)\s*$/i) {
				my @values = split(/\s+/,$1);
				for (my $i = 0; $i < @values; $i++) {
					$update{"swap.".ucfirst($keys[$i])} = $values[$i];
				}

			} elsif (!@keys && /^\s*([\w\s]+)\s*$/) {
				@keys = split(/\s+/,$1);
			}
		}
		close(PH) || warn "Unable to close file handle PH for command '$cmd': $!\n";

#	} elsif (-f '/proc/meminfo') {
#		open(FH,'<','/proc/meminfo') || die "Unable to open '/proc/meminfo': $!\n";
#		while (local $_ = <FH>) {
#			if (my ($key,$value,$kb) = $_ =~ /^(\w+):\s+(\d+)\s*(kB)\s*$/i) {
#				next unless $key =~ /^(MemTotal|MemFree|Buffers|Cached|SwapFree|SwapTotal)$/i;
#				$value *= 1024 if defined $kb;
#				if ($key =~ /^Swap/i) {
#					$update{"swap.$key"} = $value;
#				} else {
#					$update{$key} = $value;
#				}
#			}
#		}
#		if (exists $update{"swap.SwapTotal"} && exists $update{"swap.SwapFree"}) {
#			$update{"swap.SwapUsed"} = $update{"swap.SwapTotal"} - $update{"swap.SwapFree"};
#			delete $update{"swap.SwapFree"};
#		}
#		close(FH) || warn "Unable to close '/proc/meminfo': $!\n";

	} else {
		eval "use Sys::MemInfo qw(totalmem freemem)";
		die "Please install Sys::MemInfo so that I can get memory information.\n" if $@;
		@update{qw(Total Free)} = (totalmem(),freemem());
	}

	return %update;
}

sub hdd_temp {
	my $cmd = '/usr/sbin/hddtemp';
	return () unless -f $cmd;
	$cmd .= '  -q /dev/hd? /dev/sd?';

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
	return () unless -f '/proc/net/dev';
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
	my $cmd = -f '/bin/ps' ? '/bin/ps' : '/usr/bin/ps';
	my %update = ();
	my %keys = ();

	if (-f $cmd && -x $cmd) {
		if ($^O eq 'freebsd') {
			$cmd .= ' axo pid,state';
		#	%keys = (D => 'IO_Wait', R => 'Run', S => 'Sleep', T => 'Stopped',
		#			I => 'Idle', L => 'Lock_Wait', Z => 'Zombie', W => 'Idle_Thread');
			%keys = (D => 'IO_Wait', R => 'Run', S => 'Sleep', T => 'Stopped',
					W => 'Paging', Z => 'Zombie', I => 'Sleep');
		} else {#} elsif ($^O =~ /^(linux|solaris)$/)
			$cmd .= ' -eo pid,s';
			%keys = (D => 'IO_Wait', R => 'Run', S => 'Sleep', T => 'Stopped',
					W => 'Paging', X => 'Dead', Z => 'Zombie');
		}

		my $known_keys = join('',keys %keys);
		open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
		while (local $_ = <PH>) {
			if (my ($pid,$state) = $_ =~ /^\s*(\d+)\s+(\S+)\s*$/) {
				$state =~ s/[^$known_keys]//g;
				$update{$keys{$state}||$state}++ if $state;
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

	if (-f '/proc/loadavg') {
		open(FH,'<','/proc/loadavg') || die "Unable to open '/proc/loadavg': $!\n";
		my $str = <FH>;
		close(FH) || warn "Unable to close '/proc/loadavg': $!\n";
		@data = split(/\s+/,$str);

	} else {
		my $cmd = -f '/usr/bin/uptime' ? '/usr/bin/uptime' : '/bin/uptime';
		@data = `$cmd` =~ /[\s:]+([\d\.]+)[,\s]+([\d\.]+)[,\s]+([\d\.]+)\s*$/;
	}

	%update = (
		"1min"  => $data[0],
		"5min"  => $data[1],
		"15min" => $data[2],
		);

	return %update;
}

sub net_connections {
	my $cmd = -f '/bin/netstat' ? '/bin/netstat' : '/usr/bin/netstat';
	return () unless -f $cmd;
	$cmd .= ' -na';

	my %update = ();

	open(PH,'-|',$cmd) || die "Unable to open file handle for command '$cmd': $!\n";
	while (local $_ = <PH>) {
		if (my ($proto,$state) = $_ =~ /^(tcp[46]?|udp[46]?|raw)\s+.+\s+([A-Z_]+)\s*$/) {
			$update{$state}++;
		}
	}
	close(PH) || warn "Unable to close file handle for command '$cmd': $!\n";

	return %update;
}

sub proc_filehandles {
	return () unless -f '/proc/sys/fs/file-nr';
	my %update = ();

	open(FH,'<','/proc/sys/fs/file-nr') || die "Unable to open '/proc/sys/fs/file-nr': $!\n";
	my $str = <FH>;
	close(FH) || warn "Unable to close '/proc/sys/fs/file-nr': $!\n";
	@update{qw(Allocated Free Maximum)} = split(/\s+/,$str);
	$update{Used} = $update{Allocated} - $update{Free};

	return %update;
}


1;




