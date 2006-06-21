#!/home/system/rrd/bin/perl -w
############################################################
#
#   $Id$
#   rrd-server.pl - Data gathering script for RRD::Simple
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

BEGIN {
	# Ensure we can find RRDs.so for RRDs.pm
	eval "use RRDs";
	use constant BASEDIR => '/home/system/rrd';
	if ($@ && !defined $ENV{LD_LIBRARY_PATH}) {
		$ENV{LD_LIBRARY_PATH} = BASEDIR.'/lib';
		exec($0,@ARGV);
	}
}

use 5.6.1;
use strict;
use warnings;
use lib qw(../lib);
use RRD::Simple 1.39;
use RRDs;
use Memoize;
use Getopt::Std qw();
use File::Basename qw(basename);
use File::Path qw();
use vars qw($VERSION);

$VERSION = '0.01' || sprintf('%d', q$Revision$ =~ /(\d+)/g);

# Get command line options
my %opt = ();
Getopt::Std::getopts('u:gth', \%opt);

# Display help
(display_help() && exit) if defined $opt{h} ||
	!(defined $opt{u} || defined $opt{g} || defined $opt{t});

# cd to the righr location and define directories
chdir BASEDIR || die sprintf("Unable to chdir to '%s': %s", BASEDIR, $!);
my %dir = map { ( $_ => BASEDIR."/$_" ) } qw(bin spool data etc graphs cgi-bin);

# Create an RRD::Simple object
my $rrd = RRD::Simple->new(rrdtool => "$dir{bin}/rrdtool");

# Cache results from read_create_data()
memoize('read_create_data');
memoize('basename');

# Go and do some work
update_rrd($rrd,\%dir,$opt{u}) if defined $opt{u};
create_thumbnails($rrd,\%dir) if defined $opt{t};
create_graphs($rrd,\%dir) if defined $opt{g};

exit;



sub create_thumbnails {
	my ($rrd,$dir) = @_;
	my @thumbnail_theme = (only_graph => "", width => 100, height => 25);
}

sub create_graphs {
	my ($rrd,$dir) = @_;
	my @colour_theme = (color => [ (
			'BACK#F5F5FF','SHADEA#C8C8FF','SHADEB#9696BE',
			'ARROW#61B51B','GRID#404852','MGRID#67C6DE',
		) ] );
}

sub update_rrd {
	my ($rrd,$dir,$hostname) = @_;
	my $filename = shift @ARGV || undef;

	# Check out the input data
	die "Input data file '$filename' does not exist.\n"
		if defined $filename && !-f $filename;
	die "No data recieved while expecting STDIN data from rrd-client.pl.\n"
		if !$filename && !key_ready();

	# Check the hostname is sane
	die "Hostname '$hostname' contains disallowed characters.\n"
		if $hostname =~ /[^\w\-\.\d]/ || $hostname =~ /^\.|\.$/;

	# Create the data directory for the RRD file if it doesn't exist
	File::Path::mkpath("$dir->{data}/$hostname") unless -d "$dir->{data}/$hostname";

	# Open the input file if specified
	if (defined $filename) {
		open(FH,'<',$filename) || die "Unable to open file handle for file '$filename': $!";
		select FH;
	};

	# Parse the data
	my %data = ();
	while (local $_ = <>) {
		my ($path,$value) = split(/\s+/,$_);
		my ($time,@path) = split(/\./,$path);
		my $key = pop @path;

		# Check that none of the data is bogus or bollocks
		my $bogus = 0;
		$bogus++ unless $time =~ /^\d+$/;
		$bogus++ unless $value =~ /^[\d\.]+$/;
		for (@path) {
			$bogus++ unless /^[\w\-\_\.\d]+$/;
		}
		next if $bogus;

		my $rrdfile = "$dir->{data}/$hostname/".join('_',@path).".rrd";
		$data{$rrdfile}->{$time}->{$key} = $value;
	}

	# Process the data
	for my $rrdfile (sort keys %data) {
		for my $time (sort keys %{$data{$rrdfile}}) {
			create_rrd($rrd,$dir,$rrdfile,$data{$rrdfile}->{$time})
				unless -f $rrdfile;
			$rrd->update($rrdfile, %{$data{$rrdfile}->{$time}});
		}
	}

	# Close the input file if specified
	if (defined $filename) {
		select STDOUT;
		close(FH) || warn "Unable to close file handle for file '$filename': $!";
	}
}

sub create_rrd {
	my ($rrd,$dir,$rrdfile,$data) = @_;
	my $defs = read_create_data("$dir->{etc}/create.defs");

	# Figure out what DS types to use
	my %create = map { ($_ => 'GAUGE') } sort keys %{$data};
	while (my ($match,$def) = each %{$defs}) {
		next unless basename($rrdfile,qw(.rrd)) =~ /$match/;
		for my $ds (keys %create) {
			$create{$ds} = $def->{'*'}->{type} if defined $def->{'*'}->{type};
			$create{$ds} = $def->{lc($ds)}->{type} if defined $def->{lc($ds)}->{type};
		}
	}

	# Create the RRD file
	$rrd->create($rrdfile, %create);

	# Tune to use min and max values if specified
	while (my ($match,$def) = each %{$defs}) {
		next unless basename($rrdfile,qw(.rrd)) =~ /$match/;
		for my $ds ($rrd->sources($rrdfile)) {
			my $min = defined $def->{lc($ds)}->{min} ? $def->{lc($ds)}->{min} :
				defined $def->{'*'}->{min} ? $def->{'*'}->{min} : undef;
			RRDs::tune($rrdfile,'-i',"$ds:$min") if defined $min;

			my $max = defined $def->{lc($ds)}->{max} ? $def->{lc($ds)}->{max} :
				defined $def->{'*'}->{max} ? $def->{'*'}->{max} : undef;
			RRDs::tune($rrdfile,'-a',"$ds:$max") if defined $max;
		}
	}
}

sub display_help {
	print qq{Syntax: $0 <-u hostname,-g,-t|-h> [inputfile]
     -u <hostname>   Update RRD data for <hostname>
     -g              Create graphs from RRD data
     -t              Create thumbnails from RRD data
     -h              Display this help\n};
}

sub key_ready {
	my ($rin, $nfd) = ('','');
	vec($rin, fileno(STDIN), 1) = 1;
	return $nfd = select($rin,undef,undef,3);
}

sub read_create_data {
	my $filename = shift || undef;
	my %defs = ();
	
	# Open the input file if specified
	if (defined $filename && -f $filename) {
		open(FH,'<',$filename) || die "Unable to open file handle for file '$filename': $!";
		select FH;
	} else {
		select DATA;
	}

	# Parse the file
	while (local $_ = <DATA>) {
		last if /^__END__\s*$/;
		next if /^\s*$/ || /^\s*#/;

		my %def = ();
		@def{qw(rrdfile ds type min max)} = split(/\s+/,$_);
		next unless defined $def{ds};
		$def{ds} = lc($def{ds});
		$def{rrdfile} = qr($def{rrdfile});
		for (keys %def) {
			if (!defined $def{$_} || $def{$_} eq '-') {	
				delete $def{$_};
			} elsif ($_ =~ /^(min|max)$/ && $def{$_} !~ /^[\d\.]+$/) {
				delete $def{$_};
			} elsif ($_ eq 'type' && $def{$_} !~ /^(GAUGE|COUNTER|DERIVE|ABSOLUTE|COMPUTE)$/i) {
				delete $def{$_};
			}
		}

		$defs{$def{rrdfile}}->{$def{ds}} = {
				map { ($_ => $def{$_}) } grep(!/^(rrdfile|ds)$/,keys %def)
			};
	}

	# Close the input file if specified
	select STDOUT;
	if (defined $filename && -f $filename) {
		close(FH) || warn "Unable to close file handle for file '$filename': $!";
	}

	return \%defs;
}

sub write_txt {
	my %rtn = @_;
	while (my ($period,$data) = each %rtn) {
		my $filename = shift @{$data};
		my %values = ();
		my $max_len = 0;
		for (@{$data->[0]}) {
			my ($ds,$k,$v) = split(/\s+/,$_);
			$values{$ds}->{$k} = $v;
			$max_len = length($ds) if length($ds) > $max_len;
		}
		if (open(FH,'>',"$filename.txt")) {
			printf FH "%s (%dx%d) %dK\n\n", $filename,
			$data->[1], $data->[2], (stat($filename))[7]/1024;
			for (sort keys %values) {
				printf FH "%-${max_len}s     min: %s, max: %s, last: %s\n", $_,
				$values{$_}->{min}, $values{$_}->{max}, $values{$_}->{last};
			}
			close(FH);
		}
	}
}


1;



__DATA__

#	* means all
#	- means undef/na

# rrdfile	ds	type	min	max

^net_traffic_.+	Transmit	DERIVE	0	-
^net_traffic_.+	Receive	DERIVE	0	-

^hdd_io_.+	*	DERIVE	0	-

^apache_status$	ReqPerSec	DERIVE	0	-
^apache_status$	BytesPerSec	DERIVE	0	-
^apache_logs$	*	DERIVE	0	-




__END__

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => "cpu-utilisation",
		extended_legend => 1,
		title => 'CPU Utilisation',
		sources => [ qw(sy us wa id) ],
		source_drawtypes => [ qw(AREA STACK STACK STACK) ],
		source_colors => [ qw(ff0000 00ff00 0000ff ffffff) ],
		vertical_label => '% percent',
		source_labels => \%labels,
		upper_limit => 100,
		lower_limit => 0,
		rigid => "",
	));

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => "hdd-io-$dev",
		title => "Hard Disk I/O: $dev",
		sources => [ qw(read write) ],
		source_labels => [ qw(Read Write) ],
		source_drawtypes => [ qw(AREA LINE1) ],
		source_colors => [ qw(00ee00 dd0000) ],
		vertical_label => 'bytes/sec',
	));

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => 'mem-usage',
		title => 'Memory Usage',
		base => 1024,
		vertical_label => 'bytes',
		sources => [ ('MemTotal',grep(/^(Buffers|Cached)$/i, keys %update),'MemFree') ],
		source_drawtypes => {
				MemTotal => 'LINE2',
				Cached   => 'AREA',
				Buffers  => 'STACK',
				MemFree  => 'LINE1',
			},
		source_colors => {
				MemTotal => 'ff0000',
				MemFree  => '00ff00',
				Cached   => '0000ff',
				Buffers  => '00ffff',
			},
	));

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename         => 'mem-swap',
		title            => 'Swap Usage',
		base             => 1024,
		vertical_label   => 'bytes',
		sources          => [ qw(SwapTotal SwapUsed) ],
		source_drawtypes => [ qw(LINE2 AREA) ],
	)) if grep(/^SwapUsed$/, $rrd->sources($rrdfile));

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => 'hdd-temp',
		extended_legend => 1,
		title => 'Hard Disk Temperature',
		vertical_label => 'Celsius',
		sources => [ sort $rrd->sources($rrdfile) ],
	));

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename       => 'hdd-capacity',
		extended_legend => 1,
		title          => 'Disk Capacity',
		line_thickness => 2,
		vertical_label => '% used',
		units_exponent => 0,
		upper_limit    => 100,
		sources        => [ sort keys %update ],
		source_labels  => [ map { $labels{$_} } sort keys %labels ],
	));

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => "net-traffic-$dev",
		extended_legend => 1,
		title => "Network Traffic: $dev",
		vertical_label => 'bytes/sec',
		sources => [ qw(TXbytes RXbytes) ],
		source_labels => [ qw(Transmit Recieve) ],
		source_drawtypes => [ qw(AREA LINE) ],
		source_colors => [ qw(00dd00 0000dd) ],
	));

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => "proc-state",
		extended_legend => 1,
		title => 'Processes',
		vertical_label => 'Processes',
		sources => \@sources,
		source_drawtypes => \@types,
		source_labels => \%labels,
	));

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => "cpu-loadavg",
		extended_legend => 1,
		title => 'Load Average',
		sources => [ qw(1min 5min 15min) ], 
		source_colors => [ qw(ffbb00 cc0000 0000cc) ],
		source_drawtypes => [ qw(AREA LINE1 LINE1) ],
		vertical_label => 'Load',
	));

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => "net-connections",
		extended_legend => 1,
		title => 'Network Connections',
		sources => [ ('ESTABLISHED',
				grep(!/^(LISTEN|ESTABLISHED)$/,@sources),
				'LISTEN') ], 
		source_drawtypes => \@types,
		source_colors => { LISTEN => 'ffffff' },
		vertical_label => 'Connections',
	));

write_txt($rrd->graph($rrdfile, @colour_theme,
		basename => "proc-filehandles",
		extended_legend => 1,
		title => 'File Handles',
		sources => [ qw(maximum allocated used free) ],
		source_labels => [ qw(Maximum Allocated Used Free) ],
		source_drawtypes => [ qw(LINE2 AREA LINE1 LINE1) ],
		vertical_label => 'Handles',
	));

