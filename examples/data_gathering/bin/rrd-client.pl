#!/usr/bin/perl -w
############################################################
#
#   $Id$
#   rrd-client.pl - Data gathering script for RRD::Simple
#
#   Copyright 2006,2007 Nicola Worthington
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

############################################################
# User defined constants
use constant DB_MYSQL_DSN  => $ENV{DB_MYSQL_DSN} || 'DBI:mysql:mysql:localhost';
use constant DB_MYSQL_USER => $ENV{DB_MYSQL_USER} || undef;
use constant DB_MYSQL_PASS => $ENV{DB_MYSQL_PASS} || undef;

use constant NET_PING_HOSTS => $ENV{NET_PING_HOSTS} ?
		(split(/[\s,:]+/,$ENV{NET_PING_HOSTS})) : qw();

#
#  YOU SHOULD NOT NEED TO EDIT ANYTHING BEYOND THIS POINT
#
############################################################





use 5.004;
use strict;
#use warnings; # comment out for release
use vars qw($VERSION);

$VERSION = '1.41' || sprintf('%d', q$Revision$ =~ /(\d+)/g);
$ENV{PATH} = '/bin:/usr/bin';
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};


# Default list of probes
my @probes = qw(
		cpu_utilisation cpu_loadavg cpu_temp cpu_interrupts
		hdd_io hdd_temp hdd_capacity
		mem_usage mem_swap_activity mem_proc_largest
		proc_threads proc_state proc_filehandles
		apache_status apache_logs
		misc_uptime misc_users misc_ipmi_temp misc_entropy
		db_mysql_activity db_mysql_replication
		mail_exim_queue mail_postfix_queue mail_sendmail_queue
		net_traffic net_connections net_ping_host
	);
# net_connections_ports


# Get command line options
my %opt = ();
eval "require Getopt::Std";
Getopt::Std::getopts('p:i:x:s:c:V:hvq', \%opt) unless $@;
(display_help() && exit) if defined $opt{h};
(display_version() && exit) if defined $opt{v};


# Complain if someone uses -s with -i and/or -x
if (($opt{i} || $opt{x}) && $opt{s}) {
	warn "Error: -s cannot be used in conjunction with -x or -i.\n\n";
	display_help() && exit;
}

# Check to see if we are capable of SNMP queries
my $oids = {};
my $snmpget;
if ($opt{s}) {
	eval {
		require Net::SNMP;
		@probes = 'net_snmp';	
	};
	if ($@) {
		$snmpget = select_cmd(qw(/usr/bin/snmpwalk /usr/local/bin/snmpwalk));
		die "Error: unable to query via SNMP. Please install Net::SNMP or snmpget.\n"
			if !defined($snmpget) || !-f $snmpget || !-x $snmpget;
		@probes = 'snmpget';
	}

	$opt{c} = 'public' unless defined($opt{c}) && $opt{c} =~ /\S+/;
	$opt{V} = '2c' unless defined($opt{w}) && $opt{w} =~ /^(1|2c)$/;

	$oids = {
		# Net-SNMP - http://www.debianhelp.co.uk/linuxoids.htm
		'cpu.loadavg.1min'       => [ '.1.3.6.1.4.1.2021.10.1.3.1' ],
		'cpu.loadavg.5min'       => [ '.1.3.6.1.4.1.2021.10.1.3.2' ],
		'cpu.loadavg.15min'      => [ '.1.3.6.1.4.1.2021.10.1.3.3' ],
		'cpu.utilisation.Idle'   => [ '.1.3.6.1.4.1.2021.11.11.0' ],
		'cpu.utilisation.System' => [ '.1.3.6.1.4.1.2021.11.10.0' ],
		'cpu.utilisation.User'   => [ '.1.3.6.1.4.1.2021.11.9.0' ],
		'mem.usage.swap.Total'   => [ '.1.3.6.1.4.1.2021.4.3.0' ],
		'mem.usage.swap.Free'    => [ '.1.3.6.1.4.1.2021.4.4.0' ],
		'mem.usage.Total'        => [ '.1.3.6.1.4.1.2021.4.5.0' ],
		'mem.usage.Shared'       => [ '.1.3.6.1.4.1.2021.4.13.0' ],
		'mem.usage.Buffers'      => [ '.1.3.6.1.4.1.2021.4.14.0' ],
		'mem.usage.Cached'       => [ '.1.3.6.1.4.1.2021.4.15.0' ],
		'mem.usage.Free'         => [ '.1.3.6.1.4.1.2021.4.11.0' ],
		'mem.usage.Used'         => [ '.1.3.6.1.4.1.2021.4.6.0' ],
		'misc.uptime.DaysUp',    => [ '.1.3.6.1.2.1.1.3.0' => sub { return $_[0]/100/60/60/24 } ],
		# Windows NT - http://www.wtcs.org/snmp4tpc/testing.htm
		};

# The -i/-x and -s options are mutually exclusive.
# -s for SNMP will take priority.
} else {
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
}


# Run the probes one by one
die "Error: nothing to probe!\n" unless @probes;
my $post = '';
my %update_cache;
for my $probe (@probes) {
	eval {
		local $SIG{ALRM} = sub { die "Timeout!\n"; };
		alarm 15;
		my $str = report($probe,eval "$probe();");
		if (defined $opt{p}) {
			$post .= $str;
		} else {
			print $str;
		}
		warn "Warning [$probe]: $@" if !$opt{q} && $@;
		alarm 0;
	};
	warn "Warning [$probe]: $@" if !$opt{q} && $@;
}


# HTTP POST the data if asked to
print scalar(basic_http('POST',$opt{p},30,$post))."\n" if $opt{p};


exit;





# Report the data
sub report {
	(my $probe = shift) =~ s/[_-]/\./g;
	my %data = @_ % 2 ? (@_,undef) : @_;
	my $str = '';
	for my $k (sort keys %data) {
		#$data{$k} = 0 unless defined($data{$k});
		next unless defined($data{$k});
		if ($probe eq 'net.snmp' || $probe eq 'snmpget') {
			$str .= sprintf("%s.%s %s\n", time(), $k, $data{$k});
		} else {
			$str .= sprintf("%s.%s.%s %s\n", time(),
				$probe, $k, $data{$k});
		}
	}
	return $str;
}


# Display help
sub display_help {
	print qq{Syntax: rrd-client.pl [-i probe1,probe2,..|-x probe1,probe2,..|-s host]
                      [-c community] [-V 1|2c] [-p URL] [-h|-v]
   -i <probes>     Include a list of comma seperated probes
   -x <probes>     Exclude a list of comma seperated probes
   -s <host>       Specify hostname to probe via SNMP
   -c <community>  Specify SNMP community name (defaults to public)
   -V <version>    Specify SNMP version to use (1 or 2c, defaults to 2c)
   -p <URL>        HTTP POST data to the specified URL
   -q              Suppress all warning messages
   -v              Display version information
   -h              Display this help

Examples:
   rrd-client.pl -x apache_status -q -p http://rrd.me.uk/cgi-bin/rrd-server.pl
   rrd-client.pl -s localhost -p http://rrd.me.uk/cgi-bin/rrd-server.pl
   rrd-client.pl -s server1.company.com | rrd-server.pl -u server1.company.com
\n};
}


# Display version
sub display_version {
	print "$0 version $VERSION ".'($Id$)'."\n";
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
		print SOCK "User-Agent: $0 version $VERSION ".'($Id$)'."\n";
		if ($post && $method eq 'POST') {
			print SOCK "Content-Length: ". length($post) ."\n";
			print SOCK "Content-Type: application/x-www-form-urlencoded\n";
		}
		print SOCK "\n";
		print SOCK $post if $post && $method eq 'POST';

		my $body = 0;
		while (local $_ = <SOCK>) {
			s/[\n\n]+//g;
			$str .= $_ if $_ && $body;
			$body = 1 if /^\s*$/;
		}
		close(SOCK);
		alarm 0;
	};

	warn "Warning [basic_http]: $@" if !$opt{q} && $@ && $post;
	return wantarray ? split(/\n/,$str) : "$str";
}


# Return the most appropriate binary command
sub select_cmd {
	foreach (@_) {
		if (-f $_ && -x $_ && /(\S+)/) {
			return $1;
		}
	}
	return '';
}






#
# Probes
#

sub _parse_snmp_results {
	my $result = shift;
	my %update;

	for my $key (sort(keys(%{$oids}))) {
		my $oid = $oids->{$key}->[0];
		my $sub = $oids->{$key}->[1];
		my $value = $result->{$oid};
		next unless exists $result->{$oid};
		$value = &$sub($value) if defined($sub) && ref($sub) eq 'CODE';
		$update{$key} = $value;
	}

	return %update;
}



sub snmpget {
	return unless defined($oids) && ref($oids) eq 'HASH';

	my $oidStr = join(' ', map { $oids->{$_}->[0] } keys %{$oids});
	my $cmd = "$snmpget -O n -v $opt{V} -c $opt{c} $opt{s} $oidStr";
	my $result = {};

	open(PH,'-|',"$cmd 2>&1") || die "Unable to open file handle PH for command '$cmd': $!\n";
	while (local $_ = <PH>) {
		if (/^(\.[\.0-9]+)\s*=\s*(?:([A-Z]+):?\s+)?(\S+)/) {
			my ($oid,$type,$value) = ($1,$2,$3);
			#print "$oid -> $type -> $value\n";
			$result->{$oid} = $value;
		} else {
			warn "Warning [snmpget]: $_\n";
		}
	}
        close(PH) || die "Unable to close file handle PH for command '$cmd': $!\n";

	return _parse_snmp_results($result);
}



sub net_snmp {
	return unless defined($oids) && ref($oids) eq 'HASH';

	my ($session, $error) = Net::SNMP->session(
			-hostname  => $opt{s},
			-community => $opt{c},
			-version   => $opt{V},
			-port      => 161,
			-translate => [ -timeticks => 0x0 ],
		);
	die $error if !defined($session);

	my $result = $session->get_request(
			-varbindlist => [ map { $oids->{$_}->[0] } keys %{$oids} ]
		);
	$session->close;
	die $session->error if !defined($result);

	return _parse_snmp_results($result);
}



sub net_ping_host {
	return unless defined NET_PING_HOSTS() && scalar NET_PING_HOSTS() > 0;
	my $cmd = select_cmd(qw(/bin/ping /usr/bin/ping /sbin/ping /usr/sbin/ping));
	return unless -f $cmd;
	my %update = ();
	my $count = 3;

	for my $str (NET_PING_HOSTS()) {
		my ($host) = $str =~ /^([\w\d_\-\.]+)$/i;
		next unless $host;
		my $cmd2 = "$cmd -c $count $host 2>&1";

		open(PH,'-|',$cmd2) || die "Unable to open file handle PH for command '$cmd2': $!\n";
		while (local $_ = <PH>) {
			if (/\s+(\d+)%\s+packet\s+loss[\s,]/i) {
				$update{"$host.PacketLoss"} = $1 || 0;
			} elsif (my ($min,$avg,$max,$mdev) = $_ =~
					/\s+([\d\.]+)\/([\d\.]+)\/([\d\.]+)\/([\d\.]+)\s+/) {
				$update{"$host.AvgRTT"} = $avg || 0;
				$update{"$host.MinRTT"} = $min || 0;
				$update{"$host.MaxRTT"} = $max || 0;
				$update{"$host.MDevRTT"} = $mdev || 0;
			}
		}
		close(PH) || die "Unable to close file handle PH for command '$cmd2': $!\n";
	}

	return %update;
}



sub mem_proc_largest {
	my $cmd = select_cmd(qw(/bin/ps /usr/bin/ps));
	return unless -f $cmd;
	$cmd .= ' -eo vsize';

	my %update = ();
	open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
	while (local $_ = <PH>) {
		if (/(\d+)/) {
			my $kb = $1;
			$update{LargestProc} = $kb if !defined $update{LargestProc} ||
				(defined $update{LargestProc} && $kb > $update{LargestProc});
		}
	}
	close(PH) || die "Unable to close file handle PH for command '$cmd': $!\n";
	$update{LargestProc} *= 1024 if defined $update{LargestProc};

	return %update;
}



sub proc_threads {
	return unless ($^O eq 'linux' && `/bin/uname -r 2>&1` =~ /^2\.6\./) ||
					($^O eq 'solaris' && `/bin/uname -r 2>&1` =~ /^5\.9/);
	my %update = ();
	my $cmd = '/bin/ps -eo pid,nlwp';

	open(PH,'-|',$cmd) || die "Unable to open file handle for command '$cmd': $!";
	while (local $_ = <PH>) {
		if (my ($pid,$nlwp) = $_ =~ /^\s*(\d+)\s+(\d+)\s*$/) {
			$update{Processes}++;
			$update{Threads} += $nlwp;
			$update{MultiThreadProcs}++ if $nlwp > 1;
		}
	}
	close(PH) || die "Unable to close file handle for command '$cmd': $!";

	return %update;
}



sub mail_exim_queue {
	my $spooldir = '/var/spool/exim/input';
	return unless -d $spooldir && -x $spooldir && -r $spooldir;

	local %mail::exim::queue::update = (Messages => 0);
	require File::Find;
	File::Find::find({wanted => sub {
			my ($dev,$ino,$mode,$nlink,$uid,$gid);
			(($dev,$ino,$mode,$nlink,$uid,$gid) = lstat($_)) &&
			-f _ &&
			/^.*-D\z/s &&
			$mail::exim::queue::update{Messages}++;
		}, no_chdir => 1}, $spooldir);
	return %mail::exim::queue::update;
}


sub mail_sendmail_queue {
	my $spooldir = '/var/spool/mqueue';
	return unless -d $spooldir && -x $spooldir && -r $spooldir;

	local %mail::sendmail::queue::update = (Messages => 0);
	require File::Find;
	File::Find::find({wanted => sub {
			my ($dev,$ino,$mode,$nlink,$uid,$gid);
			(($dev,$ino,$mode,$nlink,$uid,$gid) = lstat($_)) &&
			-f _ &&
			/^Qf[a-zA-Z0-9]{14}\z/s &&
			$mail::sendmail::queue::update{Messages}++;
		}, no_chdir => 1}, $spooldir);
	return %mail::sendmail::queue::update;
}



sub mail_postfix_queue {
	my @spooldirs = qw(
			/var/spool/postfix/incoming
			/var/spool/postfix/active
			/var/spool/postfix/defer
			/var/spool/postfix/deferred
		);
	for my $spooldir (@spooldirs) {
		return unless -d $spooldir && -x $spooldir && -r $spooldir;
	}

	local %mail::postfix::queue::update = (Messages => 0);
	require File::Find;
	File::Find::find({wanted => sub {
			my ($dev,$ino,$mode,$nlink,$uid,$gid);
			(($dev,$ino,$mode,$nlink,$uid,$gid) = lstat($_)) &&
			-f _ &&
			$mail::postfix::queue::update{Messages}++;
		}, no_chdir => 1}, @spooldirs);
	return %mail::postfix::queue::update;
}



# DO NOT ENABLE THIS ONE YET
sub mail_queue {
	my $cmd = select_cmd(qw(/usr/bin/mailq /usr/sbin/mailq /usr/local/bin/mailq
			/usr/local/sbin/mailq /bin/mailq /sbin/mailq
			/usr/local/exim/bin/mailq /home/system/exim/bin/mailq));
	return unless -f $cmd;

	my %update = ();

	open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
	while (local $_ = <PH>) {
		# This needs to match a single message id = currently only exim friendly
		if (/^\s*\S+\s+\S+\s+[a-z0-9]{6}-[a-z0-9]{6}-[a-z0-9]{2} </i) {
			$update{Messages}++;
		}
	}
	close(PH) || die "Unable to close file handle PH for command '$cmd': $!\n";
	$update{Messages} = 0 if !defined($update{Messages});

	return %update;
}



sub db_mysql_activity {
	my %update = ();
	return %update unless (defined DB_MYSQL_DSN && defined DB_MYSQL_USER);

	eval {
		require DBI;
		my $dbh = DBI->connect(DB_MYSQL_DSN,DB_MYSQL_USER,DB_MYSQL_PASS);
		my $sth = $dbh->prepare('SHOW STATUS');
		$sth->execute();
		while (my @ary = $sth->fetchrow_array()) {
			if ($ary[0] =~ /^Questions$/i) {
				%update = @ary;
				last;
			}
		}
		$sth->finish();
		$dbh->disconnect();
	};

	return %update;
}



sub db_mysql_replication {
	my %update = ();
	return %update unless (defined DB_MYSQL_DSN && defined DB_MYSQL_USER);

	eval {
		require DBI;
		my $dbh = DBI->connect(DB_MYSQL_DSN,DB_MYSQL_USER,DB_MYSQL_PASS);
		my $sth = $dbh->prepare('SHOW SLAVE STATUS');
		$sth->execute();
		my $row = $sth->fetchrow_hashref;
		$sth->finish();
		$dbh->disconnect();
		$update{SecondsBehind} = $row->{Seconds_Behind_Master} || 0;
	};

	return %update;
}



sub misc_users {
	my $cmd = select_cmd(qw(/usr/bin/who /bin/who /usr/bin/w /bin/w));
	return unless -f $cmd;
	my %update = ();

	open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
	my %users = ();
	while (local $_ = <PH>) {
		next if /^\s*USERS\s*TTY/;
		$users{(split(/\s+/,$_))[0]}++;
		$update{Users}++;
	}
	close(PH) || die "Unable to close file handle PH for command '$cmd': $!\n";
	$update{Unique} = keys %users if keys %users;

	unless (keys %update) {
		$cmd = -f '/usr/bin/uptime' ? '/usr/bin/uptime' : '/bin/uptime';
		if (my ($users) = `$cmd` =~ /,\s*(\d+)\s*users?\s*,/i) {
			$update{Users} = $1;
		}
	}

	$update{Users} ||= 0;
	$update{Unique} ||= 0;

	return %update;
}



sub misc_uptime {
	my $cmd = select_cmd(qw(/usr/bin/uptime /bin/uptime));
	return unless -f $cmd;
	my %update = ();

	if (my ($str) = `$cmd` =~ /\s*up\s*(.+?)\s*,\s*\d+\s*users?/) {
		my $days = 0;
		if (my ($nuke,$num) = $str =~ /(\s*(\d+)\s*days?,?\s*)/) {
			$str =~ s/$nuke//;
			$days += $num;
		}
		if (my ($nuke,$mins) = $str =~ /(\s*(\d+)\s*mins?,?\s*)/) {
			$str =~ s/$nuke//;
			$days += ($mins / (60*24));
		}
		if (my ($nuke,$hours) = $str =~ /(\s*(\d+)\s*(hour|hr)s?,?\s*)/) {
			$str =~ s/$nuke//;
			$days += ($hours / 24);
		}
		if (my ($hours,$mins) = $str =~ /\s*(\d+):(\d+)\s*,?/) {
			$days += ($mins / (60*24));
			$days += ($hours / 24);
		}
		$update{DaysUp} = $days;
	}

	return %update;
}



sub cpu_temp {
	my $cmd = '/usr/bin/sensors';
	return unless -f $cmd;
	my %update = ();

	open(PH,'-|',"$cmd 2>&1") || die "Unable to open file handle PH for command '$cmd': $!\n";
	while (local $_ = <PH>) {
		if (my ($k,$v) = $_ =~ /^([^:]*\b(?:CPU|temp)\d*\b.*?):\s*\S*?([\d\.]+)\S*\s*/i) {
			$k =~ s/\W//g; $k =~ s/Temp$//i;
			$update{$k} = $v;
                } elsif (/(no sensors found|kernel driver|sensors-detect|error|warning)/i
				&& !$opt{q}) {
                        warn "Warning [cpu_temp]: $_";
                }
	}
	close(PH) || die "Unable to close file handle PH for command '$cmd': $!\n";

	return %update;
}



sub apache_logs {
	my $dir = '/var/log/httpd';
	return unless -d $dir;
	my %update = ();

	if (-d $dir) {
		opendir(DH,$dir) || die "Unable to open file handle for directory '$dir': $!\n";
		my @files = grep(!/^\./,readdir(DH));
		closedir(DH) || die "Unable to close file handle for directory '$dir': $!\n";
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
		eval {
			my $ua = LWP::UserAgent->new(
				agent => "$0 version $VERSION ".'($Id)',
				 timeout => $timeout);
			$ua->env_proxy;
			$ua->max_size(1024*250);
			my $response = $ua->get($url);
			if ($response->is_success) {
				@data = split(/\n+|\r+/,$response->content);
			} elsif (!$opt{q}) {
				warn "Warning [apache_status]: failed to get $url; ". $response->status_line ."\n";
			}
		};
	}
	if ($@) {
		@data = basic_http('GET',$url,$timeout);
	}

	for (@data) {
		my ($k,$v) = $_ =~ /^\s*(.+?):\s+(.+?)\s*$/;
		$k = '' unless defined $k;
		$v = '' unless defined $v;
		$k =~ s/\s+//g; #$k = lc($k);
		next unless $k;
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



sub _darwin_cpu_utilisation {
	my $output = qx{/usr/bin/sar 4 1};
	my %rv = ();
	if ($output =~ m/Average:\s+(\d+)\s+(\d+)\s+(\d+)/) {
		%rv = (
				User => $1,
				System => $2,
				Idle => $3,
				IO_Wait => 0, # at the time of writing, sar doesn't provide this metric
			);
	}
	return %rv;
}



sub cpu_utilisation {
	if ($^O eq 'darwin') {
		return _darwin_cpu_utilisation();
	}

	my $cmd = '/usr/bin/vmstat';
	return unless -f $cmd;
	my %update = _parse_vmstat("$cmd 1 2");
	my %labels = (wa => 'IO_Wait', id => 'Idle', sy => 'System', us => 'User');

	$update{$_} ||= 0 for keys %labels;
	return ( map {( $labels{$_} || $_ => $update{$_} )} keys %labels );
}



sub cpu_interrupts {
	my $cmd = '/usr/bin/vmstat';
	return unless -f $cmd;

	my %update = _parse_vmstat("$cmd 1 2");
	my %labels = (in => 'Interrupts');
	return unless defined $update{in};

	$update{$_} ||= 0 for keys %labels;
	return ( map {( $labels{$_} || $_ => $update{$_} )} keys %labels );
}



sub mem_swap_activity {
	my $cmd = '/usr/bin/vmstat';
	return unless -f $cmd;

	my %update = _parse_vmstat("$cmd 1 2");
	my %labels = (si => 'Swap_In', so => 'Swap_Out');
	return unless defined $update{si} && defined $update{so};

	$update{$_} ||= 0 for keys %labels;
	return ( map {( $labels{$_} || $_ => $update{$_} )} keys %labels );
}



sub _parse_vmstat {
	my $cmd = shift;
	my %update;
	my @keys;

	if (exists $update_cache{vmstat}) {
		%update = %{$update_cache{vmstat}};
	} else {
		open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
		while (local $_ = <PH>) {
			s/^\s+|\s+$//g;
			if (/\s+\d+\s+\d+\s+\d+\s+/ && @keys) {
				@update{@keys} = split(/\s+/,$_);
			} else { @keys = split(/\s+/,$_); }
		}
		close(PH) || die "Unable to close file handle PH for command '$cmd': $!\n";
		$update_cache{vmstat} = \%update;
	}

	return %update;
}



sub _parse_ipmitool_sensor {
	my $cmd = shift;
	my %update;
	my @keys;

	if (exists $update_cache{ipmitool_sensor}) {
		%update = %{$update_cache{ipmitool_sensor}};
	} else {
		if ((-e '/dev/ipmi0' || -e '/dev/ipmi/0') && open(PH,'-|',$cmd)) {
			while (local $_ = <PH>) {
					chomp; s/(^\s+|\s+$)//g;
					my ($key,@ary) = split(/\s*\|\s*/,$_);
					$key =~ s/[^a-zA-Z0-9_]//g;
					$update{$key} = \@ary;
			}
			close(PH);
			$update_cache{ipmitool_sensor} = \%update;
		}
	}

	return %update;
}



sub misc_ipmi_temp {
	my $cmd = select_cmd(qw(/usr/bin/ipmitool));
	return unless -f $cmd;

	my %update = ();
	my %data = _parse_ipmitool_sensor("$cmd sensor");
	for (grep(/temp/i,keys %data)) {
		$update{$_} = $data{$_}->[0]
			if $data{$_}->[0] =~ /^[0-9\.]+$/;
	}
	return unless keys %update;

	return %update;;
}



sub hdd_io {
	my $cmd = select_cmd(qw(/usr/bin/iostat /usr/sbin/iostat));
	return unless -f $cmd;
	return unless $^O eq 'linux';
	$cmd .= ' -k';

	my %update = ();

	open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
	while (local $_ = <PH>) {
		if (my ($dev,$r,$w) = $_ =~ /^([\w\d]+)\s+\S+\s+\S+\s+\S+\s+(\d+)\s+(\d+)$/) {
			$update{"$dev.Read"} = $r*1024;
			$update{"$dev.Write"} = $w*1024;
		}
	}
	close(PH) || die "Unable to close file handle PH for command '$cmd': $!\n";

	return %update;
}



sub mem_usage {
	my %update = ();
	my $cmd = select_cmd(qw(/usr/bin/free /bin/free));
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
		close(PH) || die "Unable to close file handle PH for command '$cmd': $!\n";

	} elsif ($^O eq 'darwin' && -x '/usr/sbin/sysctl') {
		my $swap = qx{/usr/sbin/sysctl vm.swapusage};
		if ($swap =~ m/total = (.+)M  used = (.+)M  free = (.+)M/) {
			$update{"swap.Total"} = $1*1024*1024;
			$update{"swap.Used"} = $2*1024*1024;
			$update{"swap.Free"} = $3*1024*1024;
		}

	} else {
		eval "use Sys::MemInfo qw(totalmem freemem)";
		die "Please install Sys::MemInfo so that I can get memory information.\n" if $@;
		@update{qw(Total Free)} = (totalmem(),freemem());
	}

	return %update;
}



sub hdd_temp {
	my $cmd = select_cmd(qw(/usr/sbin/hddtemp /usr/bin/hddtemp));
	return unless -f $cmd;

	my @devs = ();
	for my $dev (glob('/dev/hd?'),glob('/dev/sd?')) {
		if ($dev =~ /^(\/dev\/\w{3})$/i) {
			push @devs, $1;
		}
	}

	$cmd .= " -q @devs 2>&1";
	my %update = ();
	return %update unless @devs;

	open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!\n";
	while (local $_ = <PH>) {
		if (my ($dev,$temp) = $_ =~ m,^/dev/([a-z]+):\s+.+?:\s+(\d+)..?C,) {
			$update{$dev} = $temp;
		} elsif (!/^\s*$/ && !$opt{q}) {
			warn "Warning [hdd_temp]: $_";
		}
	}
	close(PH) || die "Unable to close file handle PH for command '$cmd': $!\n";

	return %update;
}



sub hdd_capacity {
	my $cmd = select_cmd(qw(/bin/df /usr/bin/df));
	return unless -f $cmd;

	if ($^O eq 'linux') { $cmd .= ' -P -x iso9660 -x nfs -x smbfs'; }
	elsif ($^O eq 'solaris') { $cmd .= ' -lk -F ufs'; }
	elsif ($^O eq 'darwin') { $cmd .= ' -P -T hfs,ufs'; }
	else { $cmd .= ' -P'; }

	my %update = ();
	my %variants = (
			'' => '',
			'inodes.' => ' -i ',
		);

	for my $variant (keys %variants) {
		my $variant_cmd = "$cmd $variants{$variant}";
		my @data = split(/\n/, `$variant_cmd`);
		shift @data;

		my @cols = qw(fs blocks used avail capacity mount unknown);
		for (@data) {
			my %data = ();
			@data{@cols} = split(/\s+/,$_);
			if ($^O eq 'darwin' || defined $data{unknown}) {
				@data{@cols} = $_ =~ /^(.+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%?\s+(.+)\s*$/;
			}

			next if ($data{fs} eq 'none' || $data{mount} =~ m#^/dev/#);
			$data{capacity} =~ s/\%//;
			(my $ds = $data{mount}) =~ s/[^a-z0-9]/_/ig; $ds =~ s/__+/_/g;

                        # McAfee SCM 4.2 bodge-o-rama fix work around
                        next if $ds =~ /^_var_jails_d_spam_/;

			$update{"${variant}$ds"} = $data{capacity};
		}
	}

	return %update;
}



sub misc_entropy {
	my $file = '/proc/sys/kernel/random/entropy_avail';
	return unless -f $file;
	my %update = ();

	open(FH,'<',$file) || die "Unable to open '$file': $!\n";
	chomp($update{entropy_avail} = <FH>);
	close(FH) || die "Unable to close '$file': $!\n";

	return %update;
}



sub net_traffic {
	return unless -f '/proc/net/dev';
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
	close(FH) || die "Unable to close '/proc/net/dev': $!\n";

	return %update;
}



sub proc_state {
	my $cmd = select_cmd(qw(/bin/ps /usr/bin/ps));
	my %update = ();
	my %keys = ();

	if (-f $cmd && -x $cmd) {
		if ($^O eq 'freebsd' || $^O eq 'darwin') {
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
		close(PH) || die "Unable to close file handle for command '$cmd': $!\n";
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
		close(FH) || die "Unable to close '/proc/loadavg': $!\n";
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



sub _parse_netstat {
	my $cmd = shift;
	my $update;
	my @keys = qw(local_ip local_port remote_ip remote_port);

	if (exists $update_cache{netstat}) {
		$update = $update_cache{netstat};
	} else {
		open(PH,'-|',$cmd) || die "Unable to open file handle for command '$cmd': $!\n";
		while (local $_ = <PH>) {
			my %line;
			if (@line{qw(proto data state)} = $_ =~ /^(tcp[46]?|udp[46]?|raw)\s+(.+)\s+([A-Z_]+)\s*$/) {
				@line{@keys} = $line{data} =~ /(?:^|[\s\b])([:abcdef0-9\.]+):(\d{1,5})(?:[\s\b]|$)/g;
				push @{$update}, \%line;
			}
		}
		close(PH) || die "Unable to close file handle PH for command '$cmd': $!\n";
		$update_cache{netstat} = $update;
	}

	return $update;
}



sub net_connections_ports {
	my $cmd = select_cmd(qw(/bin/netstat /usr/bin/netstat /usr/sbin/netstat));
	return unless -f $cmd;
	$cmd .= ' -na 2>&1';

	my %update = ();
	my %listening_ports;
	for (@{_parse_netstat($cmd)}) {
		if ($_->{state} =~ /listen/i && defined $_->{local_port}) {
			$listening_ports{"$_->{proto}:$_->{local_port}"} = 1;
			$update{"$_->{proto}_$_->{local_port}"} = 0;
		}
	}
	for (@{_parse_netstat($cmd)}) {
		next if !defined $_->{state} || !defined $_->{remote_port};
		$update{"$_->{proto}_$_->{remote_port}"}++ if exists $listening_ports{"$_->{proto}:$_->{remote_port}"};
	}

	return %update;
}



sub net_connections {
	my $cmd = select_cmd(qw(/bin/netstat /usr/bin/netstat /usr/sbin/netstat));
	return unless -f $cmd;
	$cmd .= ' -na 2>&1';

	my %update = ();
	for (@{_parse_netstat($cmd)}) {
		$update{$_->{state}}++ if defined $_->{state};
	}

	return %update;
}



sub proc_filehandles {
	return unless -f '/proc/sys/fs/file-nr';
	my %update = ();

	open(FH,'<','/proc/sys/fs/file-nr') || die "Unable to open '/proc/sys/fs/file-nr': $!\n";
	my $str = <FH>;
	close(FH) || die "Unable to close '/proc/sys/fs/file-nr': $!\n";
	@update{qw(Allocated Free Maximum)} = split(/\s+/,$str);
	$update{Used} = $update{Allocated} - $update{Free};

	return %update;
}






