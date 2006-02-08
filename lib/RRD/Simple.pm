############################################################
#
#   $Id$
#   RRD::Simple - Simple interface to create and store data in RRD files
#
#   Copyright 2005,2006 Nicola Worthington
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

package RRD::Simple;
# vim:ts=4:sw=4:tw=78

use strict;
use Exporter;
use RRDs;
use Carp qw(croak cluck confess carp);
use File::Spec;
use File::Basename qw(fileparse dirname basename);

use vars qw($VERSION $DEBUG $DEFAULT_DSTYPE
			 @EXPORT @EXPORT_OK %EXPORT_TAGS @ISA);

$VERSION = '1.32' || sprintf('%d.%02d', q$Revision$ =~ /(\d+)/g);

@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(create update last_update graph info
				add_source sources retention_period);
%EXPORT_TAGS = (all => \@EXPORT_OK);

$DEBUG = $ENV{DEBUG} ? 1 : 0;
$DEFAULT_DSTYPE = exists $ENV{DEFAULT_DSTYPE}
					? $ENV{DEFAULT_DSTYPE} : 'GAUGE';



#
# Methods
#

# Create a new object
sub new {
	ref(my $class = shift) && croak 'Class name required';
	croak 'Odd number of elements passed when even was expected' if @_ % 2;
	my $self = { @_ };

	my $validkeys = join('|',qw(rrdtool cf));
	cluck('Unrecognised parameters passed: '.
		join(', ',grep(!/^$validkeys$/,keys %{$self})))
		if (grep(!/^$validkeys$/,keys %{$self}) && $^W);

	$self->{rrdtool} = _find_binary(exists $self->{rrdtool} ?
						$self->{rrdtool} : 'rrdtool');

	#$self->{cf} ||= [ qw(AVERAGE MIN MAX LAST) ];
	# By default, now only create RRAs for AVERAGE and MAX, like
	# mrtg v2.13.2. This is to save disk space and processing time
	# during updates etc.
	$self->{cf} ||= [ qw(AVERAGE MAX) ]; 
	$self->{cf} = [ $self->{cf} ] if !ref($self->{cf});

	bless($self,$class);
	DUMP($class,$self);
	return $self;
}


# Create a new RRD file
sub create {
	my $self = shift;
	unless (ref $self && UNIVERSAL::isa($self, __PACKAGE__)) {
		unshift @_, $self unless $self eq __PACKAGE__;
		$self = new __PACKAGE__;
	}

	# Grab or guess the filename
	my $rrdfile = (@_ % 2 && !_valid_scheme($_[0]))
				|| (!(@_ % 2) && _valid_scheme($_[1]))
					? shift : _guess_filename();
	croak "RRD file '$rrdfile' already exists" if -f $rrdfile;
	TRACE("Using filename: $rrdfile");

	# We've been given a scheme specifier
	my $scheme = 'year';
	if (@_ % 2 && _valid_scheme($_[0])) {
		$scheme = _valid_scheme($_[0]);
		shift @_;
	}
	TRACE("Using scheme: $scheme");

	croak 'Odd number of elements passed when even was expected' if @_ % 2;
	my %ds = @_;
	DUMP('%ds',\%ds);

	my $rrdDef = _rrd_def($scheme);
	my @def = ('-b', time - _seconds_in($scheme,120));
	push @def, '-s', ($rrdDef->{step} || 300);

	# Add data sources
	for my $ds (sort keys %ds) {
		$ds =~ s/[^a-zA-Z0-9_]//g;
		push @def, sprintf('DS:%s:%s:%s:%s:%s',
						substr($ds,0,19),
						uc($ds{$ds}),
						($rrdDef->{heartbeat} || 600),
						'U','U'
					);
	}

	# Add RRA definitions
	my %cf;
	for my $cf (@{$self->{cf}}) {
		$cf{$cf} = $rrdDef->{rra};
	}
	for my $cf (sort keys %cf) {
		for my $rra (@{$cf{$cf}}) {
			push @def, sprintf('RRA:%s:%s:%s:%s',
					$cf, 0.5, $rra->{step}, $rra->{rows}
				);
		}
	}

	DUMP('@def',\@def);

	# Pass to RRDs for execution
	my @rtn = RRDs::create($rrdfile, @def);
	my $error = RRDs::error;
	croak($error) if $error;
	DUMP('RRDs::info',RRDs::info($rrdfile));
	return @rtn;
}


# Update an RRD file with some data values
sub update {
	my $self = shift;
	unless (ref $self && UNIVERSAL::isa($self, __PACKAGE__)) {
		unshift @_, $self unless $self eq __PACKAGE__;
		$self = new __PACKAGE__;
	}

	# Grab or guess the filename
	my $rrdfile = (@_ % 2 && $_[0] !~ /^[1-9][0-9]{8,10}$/i)
				 || (!(@_ % 2) && $_[1] =~ /^[1-9][0-9]{8,10}$/i)
					? shift : _guess_filename();

	# We've been given an update timestamp
	my $time = time();
	if (@_ % 2 && $_[0] =~ /^([1-9][0-9]{8,10})$/i) {
		$time = $1;
		shift @_;
	}
	TRACE("Using update time: $time");

	# Try to automatically create it
	unless (-f $rrdfile) {
		cluck("RRD file '$rrdfile' does not exist; attempting to create it ",
				"using default DS type of $DEFAULT_DSTYPE") if $^W;
		my @args;
		for (my $i = 0; $i < @_; $i++) {
			push @args, ($_[$i],$DEFAULT_DSTYPE) unless $i % 2;
		}
		$self->create($rrdfile,@args);
	}

	croak "RRD file '$rrdfile' does not exist" unless -f $rrdfile;
	TRACE("Using filename: $rrdfile");

	croak 'Odd number of elements passed when even was expected' if @_ % 2;

	my %ds;
	while (my $ds = shift(@_)) {
		$ds =~ s/[^a-zA-Z0-9_]//g;
		$ds = substr($ds,0,19);
		$ds{$ds} = shift(@_);
		$ds{$ds} = 'U' if !defined($ds{$ds});
	}
	DUMP('%ds',\%ds);

	# Validate the data source names as we add them
	my @sources = $self->sources($rrdfile);
	for my $ds (sort keys %ds) {
		# Check the data source names
		if (!grep(/^$ds$/,@sources)) {
			# If someone got the case wrong, remind and correct them
			if (grep(/^$ds$/i,@sources)) {
				cluck("Data source '$ds' does not exist. Automatically ",
					"correcting it to '",(grep(/^$ds$/i,@sources))[0],
					"' instead") if $^W;
				$ds{(grep(/^$ds$/i,@sources))[0]} = $ds{$ds};
				delete $ds{$ds};

			# Otherwise add any missing or new data sources on the fly
			} else {
				# Decide what DS type and heartbeat to use
				my $info = RRDs::info($rrdfile);
				my $error = RRDs::error;
				croak($error) if $error;

				my %dsTypes;
				for my $key (grep(/^ds\[.+?\]\.type$/,keys %{$info})) {
					$dsTypes{$info->{$key}}++;
				}
				DUMP('%dsTypes',\%dsTypes);
				my $dstype = (sort { $dsTypes{$b} <=> $dsTypes{$a} }
								keys %dsTypes)[0];
				TRACE("\$dstype = $dstype");

				$self->add_source($rrdfile,$ds,$dstype);
			}
		}
	}

	# Build the def
	my @def = ('--template');
	push @def, join(':',sort keys %ds);
	push @def, join(':',$time,map { $ds{$_} } sort keys %ds);
	DUMP('@def',\@def);

	# Pass to RRDs to execute the update
	my @rtn = RRDs::update($rrdfile, @def);
	my $error = RRDs::error;
	croak($error) if $error;
	return @rtn;
}


# Get the last time an RRD was updates
sub last_update { __PACKAGE__->last(@_); }
sub last {
	my $self = shift;
	unless (ref $self && UNIVERSAL::isa($self, __PACKAGE__)) {
		unshift @_, $self unless $self eq __PACKAGE__;
		$self = new __PACKAGE__;
	}

	my $rrdfile = shift || _guess_filename();
	croak "RRD file '$rrdfile' does not exist" unless -f $rrdfile;
	TRACE("Using filename: $rrdfile");

	my $last = RRDs::last($rrdfile);
	my $error = RRDs::error;
	croak($error) if $error;
	return $last;
}


# Get a list of data sources from an RRD file
sub sources {
	my $self = shift;
	unless (ref $self && UNIVERSAL::isa($self, __PACKAGE__)) {
		unshift @_, $self unless $self eq __PACKAGE__;
		$self = new __PACKAGE__;
	}

	my $rrdfile = shift || _guess_filename();
	croak "RRD file '$rrdfile' does not exist" unless -f $rrdfile;
	TRACE("Using filename: $rrdfile");

	my $info = RRDs::info($rrdfile);
	my $error = RRDs::error;
	croak($error) if $error;

	my @ds;
	foreach (keys %{$info}) {
		if (/^ds\[(.+)?\]\.type$/) {
			push @ds, $1;
		}
	}
	return @ds;
}


# Add a new data source to an RRD file
sub add_source {
	my $self = shift;
	unless (ref $self && UNIVERSAL::isa($self, __PACKAGE__)) {
		unshift @_, $self unless $self eq __PACKAGE__;
		$self = new __PACKAGE__;
	}

	# Grab or guess the filename
	my $rrdfile = @_ % 2 ? shift : _guess_filename();
	unless (-f $rrdfile) {
		cluck("RRD file '$rrdfile' does not exist; attempting to create it")
			if $^W;
		return $self->create($rrdfile,@_);
	}
	croak "RRD file '$rrdfile' does not exist" unless -f $rrdfile;
	TRACE("Using filename: $rrdfile");

	# Check that we will understand this RRD file version first
	my $info = $self->info($rrdfile);
#	croak "Unable to add a new data source to $rrdfile; ",
#		"RRD version $info->{rrd_version} is too new"
#		if ($info->{rrd_version}+1-1) > 1;

	my ($ds,$dstype) = @_;
	TRACE("\$ds = $ds");
	TRACE("\$dstype = $dstype");

	my $rrdfileBackup = "$rrdfile.bak";
	confess "$rrdfileBackup already exists; please investigate"
		if -e $rrdfileBackup;

	# Decide what heartbeat to use
	my $heartbeat = $info->{ds}->{(sort {
							$info->{ds}->{$b}->{minimal_heartbeat} <=>
							$info->{ds}->{$b}->{minimal_heartbeat}
					} keys %{$info->{ds}})[0]}->{minimal_heartbeat};
	TRACE("\$heartbeat = $heartbeat");

	# Make a list of expected sources after the addition
	my $TgtSources = join(',',sort(($self->sources($rrdfile),$ds)));

	# Add the data source
	my $new_rrdfile = '';
	eval {
		$new_rrdfile = _add_source(
				$rrdfile,$ds,$dstype,$heartbeat,$self->{rrdtool}
			);
	};

	# Barf if the eval{} got upset
	if ($@) {
		croak "Failed to add new data source '$ds' to RRD file $rrdfile: $@";
	}

	# Barf of the new RRD file doesn't exist
	unless (-f $new_rrdfile) {
		croak "Failed to add new data source '$ds' to RRD file $rrdfile: ",
				"new RRD file $new_rrdfile does not exist";
	}

	# Barf is the new data source isn't in our new RRD file
	unless ($TgtSources eq join(',',sort($self->sources($new_rrdfile)))) {
		croak "Failed to add new data source '$ds' to RRD file $rrdfile: ",
				"new RRD file $new_rrdfile does not contain expected data ",
				"source names";
	}

	# Try and move the new RRD file in to place over the existing one
	# and then remove the backup RRD file if sucessfull
	if (File::Copy::move($rrdfile,$rrdfileBackup) &&
				File::Copy::move($new_rrdfile,$rrdfile)) {
		unless (unlink($rrdfileBackup)) {
			cluck("Failed to remove back RRD file $rrdfileBackup: $!")
				if $^W;
		}
	} else {
		croak "Failed to move new RRD file in to place: $!";
	}
}


# Make a number of graphs for an RRD file
sub graph {
	my $self = shift;
	unless (ref $self && UNIVERSAL::isa($self, __PACKAGE__)) {
		unshift @_, $self unless $self eq __PACKAGE__;
		$self = new __PACKAGE__;
	}

	# Grab or guess the filename
	my $rrdfile = @_ % 2 ? shift : _guess_filename();

	# How much data do we have to graph?
	my $period = $self->retention_period($rrdfile);

	# Check at RRA CFs are available and graph the best one
	my $info = $self->info($rrdfile);
	my $cf = 'AVERAGE';
	for my $rra (@{$info->{rra}}) {
		if ($rra->{cf} eq 'AVERAGE') {
			$cf = 'AVERAGE'; last;
		} elsif ($rra->{cf} eq 'MAX') {
			$cf = 'MAX';
		} elsif ($rra->{cf} eq 'MIN' && $cf ne 'MAX') {
			$cf = 'MIN';
		} elsif ($cf ne 'MAX' && $cf ne 'MIN') {
			$cf = $rra->{cf};
		}
	}
	TRACE("graph() - \$cf = $cf");

	# Create graphs which we have enough data to populate
	my @rtn;
	for my $type (qw(day week month year 3years)) {
		next if $period < _seconds_in($type);
		TRACE("graph() - \$type = $type");
		push @rtn, [ ($self->_create_graph($rrdfile, $type, $cf, @_)) ];
	}

	return @rtn;
}


# Fetch data point information from an RRD file
sub fetch {
	my $self = shift;
	unless (ref $self && UNIVERSAL::isa($self, __PACKAGE__)) {
		unshift @_, $self unless $self eq __PACKAGE__;
		$self = new __PACKAGE__;
	}

	# Grab or guess the filename
	my $rrdfile = @_ % 2 ? shift : _guess_filename();

}


# Fetch the last values inserted in to an RRD file
sub last_values {
	my $self = shift;
	unless (ref $self && UNIVERSAL::isa($self, __PACKAGE__)) {
		unshift @_, $self unless $self eq __PACKAGE__;
		$self = new __PACKAGE__;
	}

	# Grab or guess the filename
	my $rrdfile = @_ % 2 ? shift : _guess_filename();

	# When was the RRD last updated?
	my $lastUpdated = $self->last($rrdfile);

	# Is there a LAST RRA?
	my $info = $self->info($rrdfile);
	my $hasLastRRA = 0;
	for my $rra (@{$info->{rra}}) {
		$hasLastRRA++ if $rra->{cf} eq 'LAST';
	}
	return () if !$hasLastRRA;

	# What's the largest heartbeat in the RRD file data sources?
	my $largestHeartbeat = 1;
	for (map { $info->{ds}->{$_}->{'minimal_heartbeat'} } keys(%{$info->{ds}})) {
		$largestHeartbeat = $_ if $_ > $largestHeartbeat;
	}

	my @def = ('LAST',
				'-s', $lastUpdated - ($largestHeartbeat * 2),
				'-e', $lastUpdated
			);

	# Pass to RRDs to execute
	my ($time,$heartbeat,$ds,$data) = RRDs::fetch($rrdfile, @def);
	my $error = RRDs::error;
	croak($error) if $error;

	# Put it in to a nice easy format
	my %rtn = ();
	for my $rec (reverse @{$data}) {
		for (my $i = 0; $i < @{$rec}; $i++) {
			if (defined $rec->[$i] && !exists($rtn{$ds->[$i]})) {
				$rtn{$ds->[$i]} = $rec->[$i];
			}
		}
	}

	# Well, I'll be buggered if the LAST CF does what you'd think
	# it's meant to do. If anybody can give me some decent documentation
	# on what the LAST CF does, and/or how to get the last value put
	# in to an RRD, then I'll admit that this method exists and export
	# it too.

	return %rtn;
}


# Return how long this RRD retains data for
sub retention_period {
	my $self = shift;
	unless (ref $self && UNIVERSAL::isa($self, __PACKAGE__)) {
		unshift @_, $self unless $self eq __PACKAGE__;
		$self = new __PACKAGE__;
	}

	my $info = $self->info(@_);
	return undef if !defined($info);

	my $duration = $info->{step};
	for my $rra (@{$info->{rra}}) {
		my $secs = ($rra->{pdp_per_row} * $info->{step}) * $rra->{rows};
		$duration = $secs if $secs > $duration;
	}

	return $duration;
}


# Fetch information about an RRD file
sub info {
	my $self = shift;
	unless (ref $self && UNIVERSAL::isa($self, __PACKAGE__)) {
		unshift @_, $self unless $self eq __PACKAGE__;
		$self = new __PACKAGE__;
	}

	# Grab or guess the filename
	my $rrdfile = @_ % 2 ? shift : _guess_filename();

	my $info = RRDs::info($rrdfile);
	my $error = RRDs::error;
	croak($error) if $error;
	DUMP('$info',$info);

	my $rtn;
	for my $key (sort(keys(%{$info}))) {
		if ($key =~ /^rra\[(\d+)\]\.([a-z_]+)/) {
			$rtn->{rra}->[$1]->{$2} = $info->{$key};
		} elsif (my (@dsKey) = $key =~ /^ds\[([[A-Za-z0-9\_]+)?\]\.([a-z_]+)/) {
			$rtn->{ds}->{$1}->{$2} = $info->{$key};
		} elsif ($key !~ /\[[\d_a-z]+\]/i) {
			$rtn->{$key} = $info->{$key};
		}
	}

	# Return the information
	DUMP('$rtn',$rtn);
	return $rtn;
}


# Make a single graph image
sub _create_graph {
	my $self = shift;
	my $rrdfile = shift;
	my $type = _valid_scheme(shift) || 'day';
	my $cf = shift || 'AVERAGE';

	my %param;
	while (my $k = shift) {
		$k =~ s/_/-/g;
		$param{lc($k)} = shift;
	}

	# Specify some default values
	$param{'end'} ||= $self->last($rrdfile) || time();
	$param{'imgformat'} ||= 'PNG';
#	$param{'alt-autoscale'} ||= '';
#	$param{'alt-y-grid'} ||= '';

	# Define what to call the image
	my $basename = defined $param{'basename'} &&
						$param{'basename'} =~ /^\w+$/i ?
						$param{'basename'} :
						(fileparse($rrdfile,'\.[^\.]+'))[0];
	delete $param{'basename'};

	# Define where to write the image
	my $image = sprintf('%s-%s.%s',$basename,
				_alt_graph_name($type), lc($param{'imgformat'}));
	if ($param{'destination'}) {
		$image = File::Spec->catfile($param{'destination'},$image);
	}
	delete $param{'destination'};

	# Define how thick the graph lines should be
	my $line_thickness = defined $param{'line-thickness'} &&
						$param{'line-thickness'} =~ /^[123]$/ ?
						$param{'line-thickness'} : 1;
	delete $param{'line-thickness'};

	# Colours is an alias to colors
	if (exists $param{'source-colours'} && !exists $param{'source-colors'}) {
		$param{'source-colors'} = $param{'source-colours'};
		delete $param{'source-colours'};
	}

	# Allow source line colors to be set
	my @source_colors = ();
	my %source_colors = ();
	if (defined $param{'source-colors'}) {
		if (ref($param{'source-colors'}) eq 'ARRAY') {
			@source_colors = @{$param{'source-colors'}};
		} elsif (ref($param{'source-colors'}) eq 'HASH') {
			%source_colors = %{$param{'source-colors'}};
		}
	}
	delete $param{'source-colors'};

	# Define which data sources we should plot
	my @ds = defined $param{'sources'} &&
						ref($param{'sources'}) eq 'ARRAY' ?
						@{$param{'sources'}} : $self->sources($rrdfile);

	# Allow source legend source_labels to be set
	my %source_labels = ();
	if (defined $param{'source-labels'}) {
		if (ref($param{'source-labels'}) eq 'HASH') {
			%source_labels = %{$param{'source-labels'}};
		} elsif (ref($param{'source-labels'}) eq 'ARRAY') {
			unless (defined $param{'sources'} &&
					ref($param{'sources'}) eq 'ARRAY') {
				carp "source_labels may only be an array if sources is ".
					"also an specified and valid array" if $^W;
			} else {
				for (my $i = 0; $i < @{$param{'source-labels'}}; $i++) {
					$source_labels{$ds[$i]} = $param{'source-labels'}->[$i];
				}
			}
		}
	}
	delete $param{'source-labels'};
	delete $param{'sources'};

	# Specify a default start time
	$param{'start'} ||= $param{'end'} - _seconds_in($type,115);

	# Suffix the title with the period information
	$param{'title'} ||= basename($rrdfile);
	$param{'title'} .= ' - [Daily Graph]'   if $type eq 'day';
	$param{'title'} .= ' - [Weekly Graph]'  if $type eq 'week';
	$param{'title'} .= ' - [Monthly Graph]' if $type eq 'month';
	$param{'title'} .= ' - [Annual Graph]'  if $type eq 'year';
	$param{'title'} .= ' - [3 Year Graph]'  if $type eq '3years';

	# Convert our parameters in to an RRDs friendly defenition
	my @def;
	while (my ($k,$v) = each %param) {
		if (length($k) == 1) { $k = '-'.uc($k); }
		else { $k = "--$k"; }
		for my $v ((ref($v) eq 'ARRAY' ? @{$v} : ($v))) {
			if (!defined $v || !length($v)) {
				push @def, $k;
			} else {
				push @def, "$k=$v";
			}
		}
	}

	# Populate a cycling tied scalar for line colors
	@source_colors = qw(
			FF0000 00FF00 0000FF FFFF00 00FFFF FF00FF 000000
			550000 005500 000055 555500 005555 550055 555555
			AA0000 00AA00 0000AA AAAA00 00AAAA AA00AA AAAAAA
		) unless @source_colors > 0;
	tie my $colour, 'RRD::Simple::_Colour', \@source_colors;

	# Add the data sources to the graph
	my @cmd = ($image,@def);
	for my $ds (@ds) {
		push @cmd, sprintf('DEF:%s=%s:%s:%s',$ds,$rrdfile,$ds,$cf);
		#push @cmd, sprintf('%s:%s#%s:%-22s',
		push @cmd, sprintf('%s:%s#%s:%s',
				"LINE$line_thickness",
				$ds,
				(defined $source_colors{$ds} ? $source_colors{$ds} : $colour),
				(defined $source_labels{$ds} ? $source_labels{$ds} : $ds),
			);
	}

	# Add a comment stating when the graph was last updated
	push @cmd, ('COMMENT:\s','COMMENT:\s','COMMENT:\s');
	my $time = 'Last updated: '.localtime().'\r';
	$time =~ s/:/\\:/g if $RRDs::VERSION >= 1.2; # Only escape for 1.2
	push @cmd, "COMMENT:$time";

	DUMP('@cmd',\@cmd);

	# Generate the graph
	my @rtn = RRDs::graph(@cmd);
	my $error = RRDs::error;
	croak($error) if $error;
	return @rtn;
}




#
# Private subroutines
#

sub _rrd_def {
	croak('Pardon?!') if ref $_[0];
	my $type = _valid_scheme(shift);

	# This is calculated the same way as mrtg v2.13.2
	if ($type eq 'mrtg') {
		my $step = 5; # 5 minutes
		return {
				step => $step * 60, heartbeat => $step * 60 * 2,
				rra => [(
					{ step => 1, rows => int(4000 / $step) }, # 800
					{ step => int(  30 / $step), rows => 800 }, # if $step < 30
					{ step => int( 120 / $step), rows => 800 },
					{ step => int(1440 / $step), rows => 800 },
				)],
			};
	}

	my $step = 1; # 1 minute highest resolution
	my $rra = {
			step => $step * 60, heartbeat => $step * 60 * 2,
			rra => [(
				# Actual $step resolution (for 1.25 days retention)
				{ step => 1, rows => int( _minutes_in('day',125) / $step) },
			)],
		};

	if ($type =~ /^(week|month|year|3years)$/i) {
		push @{$rra->{rra}}, {
				step => int(  30 / $step),
				rows => int( _minutes_in('week',125) / int(30/$step) )
			}; # 30 minute average

		push @{$rra->{rra}}, {
				step => int( 120 / $step),
				rows => int( _minutes_in($type eq 'week' ? 'week' : 'month',125)
						/ int(120/$step) )
			}; # 2 hour average
	}

	if ($type =~ /^(year|3years)$/i) {
		push @{$rra->{rra}}, {
				step => int(1440 / $step),
				rows => int( _minutes_in($type,125) / int(1440/$step) )
			}; # 1 day average
	}

	return $rra;
}


sub _valid_scheme {
	croak('Pardon?!') if ref $_[0];
	TRACE(@_);
	if ($_[0] =~ /^(day|week|month|year|3years|mrtg)$/i) {
		return lc($1);
	}
	return undef;
}


sub _hours_in { return int((_seconds_in(@_)/60)/60); }
sub _minutes_in { return int(_seconds_in(@_)/60); }
sub _seconds_in {
	croak('Pardon?!') if ref $_[0];
	my $str = lc(shift);
	my $scale = shift || 100;

	return undef if !defined(_valid_scheme($str));

	my %time = (
			'day'    => 60 * 60 * 24,
			'week'   => 60 * 60 * 24 * 7,
			'month'  => 60 * 60 * 24 * 31,
			'year'   => 60 * 60 * 24 * 365,
			'3years' => 60 * 60 * 24 * 365 * 3,
			'mrtg'   => ( int(( 1440 / 5 )) * 800 ) * 60, # mrtg v2.13.2
		);

	my $rtn = $time{$str} * ($scale / 100);
	return $rtn;
}


sub _alt_graph_name {
	croak('Pardon?!') if ref $_[0];
	my $type = _valid_scheme(shift);
	return 'daily'   if $type eq 'day';
	return 'weekly'  if $type eq 'week';
	return 'monthly' if $type eq 'month';
	return 'annual'  if $type eq 'year';
	return '3years'  if $type eq '3years';
	return $type;
}


sub _add_source {
	croak('Pardon?!') if ref $_[0];
	my ($rrdfile,$ds,$dstype,$heartbeat,$rrdtool) = @_;

	require File::Copy;
	require File::Temp;

	# Generate an XML dump of the RRD file
	my $tempXmlFile = File::Temp::tmpnam();

	# Try the internal perl way first (portable)
	eval {
		# Patch to rrd_dump.c emailed to Tobi and developers
		# list by nicolaw/heds on 2006/01/08
		if ($RRDs::VERSION >= 1.2013) {
			my @rtn = RRDs::dump($rrdfile,$tempXmlFile);
			my $error = RRDs::error;
			croak($error) if $error;
		}
	};

	# Do it the old fashioned way
	if ($@ || !-f $tempXmlFile || (stat($tempXmlFile))[7] < 200) {
		croak "rrdtool binary '$rrdtool' does not exist or is not executable"
			unless (-f $rrdtool && -x $rrdtool);
		_safe_exec(sprintf('%s dump %s > %s',$rrdtool,$rrdfile,$tempXmlFile));
	}

	# Read in the new temporary XML dump file
	open(IN, "<$tempXmlFile") || croak "Unable to open '$tempXmlFile': $!";

	# Open XML output file
	my $tempImportXmlFile = File::Temp::tmpnam();
	open(OUT, ">$tempImportXmlFile")
		|| croak "Unable to open '$tempImportXmlFile': $!";

	# Create a marker hash ref to store temporary state
	my $marker = {
				insertDS => 0,
				insertCDP_PREP => 0,
				parse => 0,
				version => 1,
			};

	# Parse the input XML file
	while (local $_ = <IN>) {
		chomp;

		# Add the DS definition
		if ($marker->{insertDS} == 1) {
			print OUT <<EndDS;

	<ds>
		<name> $ds </name>
		<type> $dstype </type>
		<minimal_heartbeat> $heartbeat </minimal_heartbeat>
		<min> 0.0000000000e+00 </min>
		<max> NaN </max>

		<!-- PDP Status -->
		<last_ds> UNKN </last_ds>
		<value> 0.0000000000e+00 </value>
		<unknown_sec> 0 </unknown_sec>
	</ds>
EndDS
			$marker->{insertDS} = 0;
		}

		# Insert DS under CDP_PREP entity
		if ($marker->{insertCDP_PREP} == 1) {
			# Version 0003 RRD from rrdtool 1.2x
			if ($marker->{version} >= 3) {
				print OUT "			<ds>\n";
				print OUT "			<primary_value> 0.0000000000e+00 </primary_value>\n";
				print OUT "			<secondary_value> 0.0000000000e+00 </secondary_value>\n";
				print OUT "			<value> NaN </value>\n";
				print OUT "			<unknown_datapoints> 0 </unknown_datapoints>\n";
				print OUT "			</ds>\n";

			# Version 0001 RRD from rrdtool 1.0x
			} else { 
				print OUT "			<ds><value> NaN </value>  <unknown_datapoints> 0 </unknown_datapoints></ds>\n";
			}
			$marker->{insertCDP_PREP} = 0;
		}

		# Look for end of the <lastupdate> entity
		if (/<\/lastupdate>/) {
			$marker->{insertDS} = 1;
	
		# Look for start of the <cdp_prep> entity
		} elsif (/<cdp_prep>/) {
			$marker->{insertCDP_PREP} = 1;

		# Look for the end of an RRA
		} elsif (/<\/database>/) {
			$marker->{parse} = 0;

		# Find the dumped RRD version (must take from the XML, not the RRD)
		} elsif (/<version>\s*([0-9\.]+)\s*<\/version>/) {
			$marker->{version} = ($1 + 1 - 1);
		}

		# Add the extra "<v> NaN </v>" under the RRAs. Just print normal lines
		if ($marker->{parse} == 1) {
			if ($_ =~ /^(.+ <row>)(.+)/) {
				print OUT $1;
				print OUT "<v> NaN </v>";
				print OUT $2;
				print OUT "\n";
			}
		} else {
			print OUT "$_\n";
		}

		# Look for the start of an RRA
		if (/<database>/) {
			$marker->{parse} = 1;
		}
	}

	# Close the files
	close(IN) || croak "Unable to close '$tempXmlFile': $!";
	close(OUT) || croak "Unable to close '$tempImportXmlFile': $!";

	# Import the new output file in to the old RRD filename
	my $new_rrdfile = File::Temp::tmpnam();

	# Try the internal perl way first (portable)
	eval {
		if ($RRDs::VERSION >= 1.0049) {
			my @rtn = RRDs::restore($tempImportXmlFile,$new_rrdfile);
			my $error = RRDs::error;
			croak($error) if $error;
		}
	};

	# Do it the old fashioned way
	if ($@ || !-f $new_rrdfile || (stat($new_rrdfile))[7] < 200) {
		croak "rrdtool binary '$rrdtool' does not exist or is not executable"
			unless (-f $rrdtool && -x $rrdtool);
		my $cmd = sprintf('%s restore %s %s',$rrdtool,$tempImportXmlFile,$new_rrdfile);
		my $rtn = _safe_exec($cmd);

		# At least check the file is created
		unless (-f $new_rrdfile) {
			_nuke_tmp($tempXmlFile,$tempImportXmlFile);
			croak "Command '$cmd' failed to create the new RRD file $new_rrdfile: $rtn";
		}
	}

	# Remove the temporary files
	_nuke_tmp($tempXmlFile,$tempImportXmlFile);
	sub _nuke_tmp {
		for (@_) {
			unlink($_) ||
				carp("Unable to unlink temporary file '$_': $!");
		}
	}

	# Return the new RRD filename
	return $new_rrdfile;
}


sub _safe_exec {
	croak('Pardon?!') if ref $_[0];
	my $cmd = shift;
	if ($cmd =~ /^([\/\.\_\-a-zA-Z0-9 >]+)$/) {
		$cmd = $1;
		TRACE($cmd);
		system($cmd);
		if ($? == -1) {
			croak "Failed to execute command '$cmd': $!\n";
		} elsif ($? & 127) {
			croak(sprintf("While executing command '%s', child died ".
				"with signal %d, %s coredump\n", $cmd,
				($? & 127),  ($? & 128) ? 'with' : 'without'));
		}
		my $exit_value = $? >> 8;
		croak "Error caught from '$cmd'" if $exit_value != 0;
		return $exit_value;
	} else {
		croak "Unexpected potentially unsafe command will not be executed: $cmd";
	}
}


sub _find_binary {
	croak('Pardon?!') if ref $_[0];
	my $binary = shift || 'rrdtool';
	return $binary if -f $binary && -x $binary;

	my @paths = File::Spec->path();
	my $rrds_path = dirname($INC{'RRDs.pm'});
	push @paths, $rrds_path;
	push @paths, File::Spec->catdir($rrds_path,
				File::Spec->updir(),File::Spec->updir(),'bin');

	for my $path (@paths) {
		my $filename = File::Spec->catfile($path,$binary);
		return $filename if -f $filename && -x $filename;
	}

	my $path = File::Spec->catdir(File::Spec->rootdir(),'usr','local');
	if (opendir(DH,$path)) {
		my @dirs = sort { $b cmp $a } grep(/^rrdtool/,readdir(DH));
		closedir(DH) || carp "Unable to close file handle: $!";
		for my $dir (@dirs) {
			my $filename = File::Spec->catfile($path,$dir,'bin',$binary);
			return $filename if -f $filename && -x $filename;
		}
	}
}


sub _guess_filename {
	croak('Pardon?!') if ref $_[0];
	my ($basename, $dirname, $extension) = fileparse($0, '\.[^\.]+');
	return "$dirname$basename.rrd";
}


sub TRACE {
	return unless $DEBUG;
	warn(shift());
}


sub DUMP {
	return unless $DEBUG;
	eval {
		require Data::Dumper;
		warn(shift().': '.Data::Dumper::Dumper(shift()));
	}
}


1;


###############################################################
# This tie code is from Tie::Cycle
# written by brian d foy, <bdfoy@cpan.org>

package RRD::Simple::_Colour;

sub TIESCALAR {
	my ($class,$list_ref) = @_;
	my @shallow_copy = map { $_ } @$list_ref;
	return unless UNIVERSAL::isa( $list_ref, 'ARRAY' );
	my $self = [ 0, scalar @shallow_copy, \@shallow_copy ];
	bless $self, $class;
}

sub FETCH {
	my $self = shift;
	my $index = $$self[0]++;
	$$self[0] %= $self->[1];
	return $self->[2]->[ $index ];
}

sub STORE {
	my ($self,$list_ref) = @_;
	return unless ref $list_ref eq ref [];
	return unless @$list_ref > 1;
	$self = [ 0, scalar @$list_ref, $list_ref ];
}

1;




=pod

=head1 NAME

RRD::Simple - Simple interface to create and store data in RRD files

=head1 SYNOPSIS

 use strict;
 use RRD::Simple ();
 
 # Create an interface object
 my $rrd = RRD::Simple->new();
 
 # Create a new RRD file with 3 data sources called
 # bytesIn, bytesOut and faultsPerSec.
 $rrd->create("myfile.rrd",
             bytesIn => "GAUGE",
             bytesOut => "GAUGE",
             faultsPerSec => "COUNTER"
         );
 
 # Put some arbitary data values in the RRD file for same
 # 3 data sources called bytesIn, bytesOut and faultsPerSec.
 $rrd->update("myfile.rrd",
             bytesIn => 10039,
             bytesOut => 389,
             faultsPerSec => 0.4
         );
 
 # Generate graphs:
 # /var/tmp/myfile-daily.png, /var/tmp/myfile-weekly.png
 # /var/tmp/myfile-monthly.png, /var/tmp/myfile-annual.png
 my @rtn = $rrd->graph("myfile.rrd",
             destination => "/var/tmp",
             title => "Network Interface eth0",
             vertical_label => "Bytes/Faults",
             interlaced => ""
         );

 # Return information about an RRD file
 my $info = $rrd->info("myfile.rrd");
 require Data::Dumper;
 print Data::Dumper::Dumper($info);

 # Get unixtime of when RRD file was last updated
 my $lastUpdated = $rrd->last("myfile.rrd");
 print "myfile.rrd was last updated at " .
       scalar(localtime($lastUpdated)) . "\n";
 
 # Get list of data source names from an RRD file
 my @dsnames = $rrd->sources("myfile.rrd");
 print "Available data sources: " . join(", ", @dsnames) . "\n";
 
 # And for the ultimately lazy, you could create and update
 # an RRD in one go using a one-liner like this:
 perl -MRRD::Simple=:all -e"update(@ARGV)" myfile.rrd bytesIn 99999 

=head1 DESCRIPTION

RRD::Simple provides a simple interface to RRDTool's RRDs module.
This module does not currently offer C<fetch> method that is
available in the RRDs module.

It does however create RRD files with a sensible set of default RRA
(Round Robin Archive) definitions, and can dynamically add new
data source names to an existing RRD file.

This module is ideal for quick and simple storage of data within an
RRD file if you do not need to, nor want to, bother defining custom
RRA definitions.

=head1 METHODS

=head2 new

 my $rrd = RRD::Simple->new(
         rrdtool => "/usr/local/rrdtool-1.2.11/bin/rrdtool"
     );

The C<rrdtool> parameter is optional. It specifically defines where the
C<rrdtool> binary can be found. If not specified, the module will search for
the C<rrdtool> binary in your path, an additional location relative where
the C<RRDs> module was loaded from, and in /usr/local/rrdtool*.

The C<rrdtool> binary is only used by the C<add_source> method, and only
under certain circumstances. The C<add_source> method may also be called
automatically by the C<update> method, if data point values for a previously
undefined data source are provided for insertion.

=head2 create

 $rrd->create($rrdfile, $period,
         source_name => "TYPE",
         source_name => "TYPE",
         source_name => "TYPE"
     );

C<$rrdfile> is optional and will default to C<$0.rrd>. (Script basename with
the file extension of .rrd).

C<$period> is optional and will default to C<year>. Valid options are C<day>,
C<week>, C<month>, C<year>, C<3years> and C<mrtg>. Specifying a retention
period value will change how long data will be retained for within the RRD
file. The C<mrtg> scheme will try and mimic the retention period used by
MRTG (L<http://people.ee.ethz.ch/~oetiker/webtools/mrtg/>.

RRD::Simple will croak and die if you try to create an RRD file that already
exists.

=head2 update

 $rrd->update($rrdfile, $unixtime,
         source_name => "VALUE",
         source_name => "VALUE",
         source_name => "VALUE"
     );

C<$rrdfile> is optional and will default to C<$0.rrd>. (Script basename with
the file extension of .rrd).

C<$unixtime> is optional and will default to C<time()> (the current unixtime).
Specifying this value will determine the date and time that your data point
values will be stored against in the RRD file.

If you try update a value for a data source that does not exist, it will
automatically be added for you. The data source type will be set to whatever
is contained in the C<$RRD::Simple::DEFAULT_DSTYPE> variable. (See the
VARIABLES section below).

If you explicitly do not want this to happen, then you should check that you
are only updating pre-existing data source names using the C<sources> method.
You can manually add new data sources to an RRD file by using the C<add_source>
method, which requires you to explicitly set the data source type.

=head2 last

 my $unixtime = $rrd->last($rrdfile);

C<$rrdfile> is optional and will default to C<$0.rrd>. (Script basename with
the file extension of .rrd).

=head2 sources

 my @sources = $rrd->sources($rrdfile);

C<$rrdfile> is optional and will default to C<$0.rrd>. (Script basename with
the file extension of .rrd).

=head2 add_source

 $rrd->add_source($rrdfile,
         source_name => "TYPE"
     );

C<$rrdfile> is optional and will default to C<$0.rrd>. (Script basename with
the file extension of .rrd).

You may add a new data source to an existing RRD file using this method. Only
one data source name can be added at a time. You must also specify the data
source type.

This method can be called internally by the C<update> method to automatically
add missing data sources.

=head2 graph

 $rrd->graph($rrdfile,
         destination => "/path/to/write/graph/images",
         basename => "graph_basename",
         sources => [ qw(source_name1 source_name2 source_name3) ],
         source_colors => [ qw(ff0000 aa3333 000000) ],
         source_labels => [ ("My Source 1","My Source Two","Source 3") ],
         line_thickness => 2,
         rrd_graph_option => "value",
         rrd_graph_option => "value",
         rrd_graph_option => "value"
     );

C<$rrdfile> is optional and will default to C<$0.rrd>. (Script basename with
the file extension of .rrd).

Graph options specific to RRD::Simple are:

=over 4

=item destination

The C<destination> parameter is optional, and it will default to the same
path location as that of the RRD file specified by C<$rrdfile>. Specifying
this value will force the resulting graph images to be written to this path
location. (The specified path must be a valid directory with the sufficient
permissions to write the graph images).

=item basename

The C<basename> parameter is optional. This parameter specifies the basename
of the graph image files that will be created. If not specified, tt will
default to the name of the RRD file. For exmaple, if you specify a basename
name of C<mygraph>, the following graph image files will be created in the
C<destination> directory:

 mygraph-daily.png
 mygraph-weekly.png
 mygraph-monthly.png
 mygraph-annual.png

The default file format is C<png>, but this can be explicitly specified using
the standard RRDs options. (See below).

=item sources

The C<sources> parameter is optional. This parameter should be an array
of data source names that you want to be plotted. All data sources will be
plotted by default.

=item source_colors

 $rrd->graph($rrdfile,
         source_colors => [ qw(ff3333 ff00ff ffcc99) ],
     );
 
 $rrd->graph($rrdfile,
         source_colors => { source_name1 => "ff3333",
                            source_name2 => "ff00ff",
                            source_name3 => "ffcc99", },
     );

The C<source_colors> parameter is optional. This parameter should be an
array or hash of hex triplet colors to be used for the plotted data source
lines. A selection of vivid primary colors will be set by default.

=item source_labels

 $rrd->graph($rrdfile,
         sources => [ qw(source_name1 source_name2 source_name3) ],
         source_labels => [ ("My Source 1","My Source Two","Source 3") ],
     );
 
 $rrd->graph($rrdfile,
         source_labels => { source_name1 => "My Source 1",
                            source_name2 => "My Source Two",
                            source_name3 => "Source 3", },
     );

The C<source_labels> parameter is optional. The parameter should be an
array or hash of labels to be placed in the legend/key underneath the
graph. An array can only be used if the C<sources> parameter is also
specified, since the label index position in the array will directly
relate to the data source index position in the C<sources> array.

The data source names will be used in the legend/key by default if no
C<source_labels> parameter is specified.

=item line_thickness

Specifies the thickness of the data lines drawn on the graphs. Valid values
are 1, 2 and 3 (pixels).

=back

Common RRD graph options are:

=over 4

=item title

A horizontal string at the top of the graph.

=item vertical_label

A vertically placed string at the left hand side of the graph.

=item width

The width of the canvas (the part of the graph with the actual data
and such). This defaults to 400 pixels.

=item height

The height of the canvas (the part of the graph with the actual data
and such). This defaults to 100 pixels.

=back

For examples on how to best use the C<graph> method, refer to the example
scripts that are bundled with this module in the examples/ directory. A
complete list of parameters can be found at
L<http://people.ee.ethz.ch/~oetiker/webtools/rrdtool/doc/index.en.html>.

=head2 retention_period

 my $seconds = $rrd->retention_period($rrdfile);

C<$rrdfile> is optional and will default to C<$0.rrd>. (Script basename with
the file extension of .rrd).

This method will return a maximum period of time (in seconds) that the RRD
file will store data for.

=head2 info

 my $info = $rrd->info($rrdfile);

C<$rrdfile> is optional and will default to C<$0.rrd>. (Script basename with
the file extension of .rrd).

This method will return a complex data structure containing details about
the RRD file, including RRA and data source information.

=head1 VARIABLES

=head2 $RRD::Simple::DEBUG

Debug and trace information will be printed to STDERR if this variable
if set to 1 (boolean true).

This variable will take its value from C<$ENV{DEBUG}>, if it exists,
otherwise it will default to 0 (boolean false). This is a normal package
variable and may be safely modified at any time.

=head2 $RRD::Simple::DEFAULT_DSTYPE

This variable is used as the default data source type when creating or
adding new data sources, when no other data source type is explicitly
specified.

This variable will take its value from C<$ENV{DEFAULT_DSTYPE}>, if it
exists, otherwise it will default to C<GAUGE>. This is a normal package
variable and may be safely modified at any time.

=head1 EXPORTS

You can export the following functions if you do not wish to go through
the extra effort of using the OO interface:

 create
 update
 last_update (synonym for the last() method)
 sources
 add_source
 graph
 retention_period
 info

The tag C<all> is available to easily export everything:

 use RRD::Simple qw(:all);

See the examples and unit tests in this distribution for more
details.

=head1 SEE ALSO

L<RRDTool::OO>, L<RRDs>,
L<http://www.rrdtool.org>, examples/*.pl

=head1 VERSION

$Id$

=head1 AUTHOR

Nicola Worthington <nicolaw@cpan.org>

L<http://perlgirl.org.uk>

=head1 COPYRIGHT

Copyright 2005,2006 Nicola Worthington.

This software is licensed under The Apache Software License, Version 2.0.

L<http://www.apache.org/licenses/LICENSE-2.0>

=cut


__END__



