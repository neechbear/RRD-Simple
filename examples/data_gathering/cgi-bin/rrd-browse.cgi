#!/usr/bin/perl
############################################################
#
#   $Id$
#   rrd-browse.cgi - Graph browser CGI script for RRD::Simple
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
use constant RRDURL => '/rrd';



use 5.6.1;
use warnings;
use strict;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use HTML::Template::Expr;
use File::Basename qw(basename);
use Config::General qw();
use Memoize;
#use Data::Dumper;

# Speed things up a little :)
my %list_cache = ();
memoize('list_dir', SCALAR_CACHE => [HASH => \%list_cache]);
my %graph_cache = ();
memoize('graph_def', SCALAR_CACHE => [HASH => \%graph_cache]);

# Grab CGI paramaters
my $cgi = new CGI;
my %q = $cgi->Vars;

# cd to the righr location and define directories
my %dir = map { ( $_ => BASEDIR."/$_" ) } qw(bin spool data etc graphs cgi-bin thumbnails);
chdir $dir{'cgi-bin'} || (printf("<h1>Unable to chdir to '%s': %s</h1>", $dir{'cgi-bin'}, $!) && exit);

# Create the initial %tmpl data hash
my %tmpl = %ENV;
$tmpl{template} = defined $q{template} && -f $q{template} ? $q{template} : 'index.tmpl';
$tmpl{PERIOD} = defined $q{PERIOD} ? $q{PERIOD} : 'daily';
$tmpl{title} = ucfirst(basename($tmpl{template},'.tmpl')); $tmpl{title} =~ s/[_\-]/ /g;
$tmpl{self_url} = $cgi->self_url(-absolute => 1, -query_string => 0, -path_info => 0);
$tmpl{rrd_url} = RRDURL;

# Build up the data in %tmpl
my $gdefs = read_graph_data("$dir{etc}/graph.defs");
my @graphs = list_dir($dir{graphs});
my @thumbnails = list_dir($dir{thumbnails});
my %graph_tmpl = ();
$tmpl{hosts} = []; $tmpl{graphs} = [];

# By host
for my $host (sort by_domain list_dir($dir{data})) {
	if (!grep(/^$host$/,@graphs)) {
		push @{$tmpl{hosts}}, { host => $host, no_graphs => 1 };
	} else {
		my %host = ( host => $host );
		for (qw(thumbnails graphs)) {
			eval {
				my @ary = ();
				for my $img (sort alpha_period list_dir("$dir{$_}/$host")) {
					my %hash = (
						src => "$tmpl{rrd_url}/$_/$host/$img",
						period => ($img =~ /.*-(\w+)\.\w+$/),
						graph => ($img =~ /^(.+)\-\w+\.\w+$/),
					);
					my $gdef = graph_def($gdefs,$hash{graph});
					$hash{title} = defined $gdef->{title} ? $gdef->{title} : $hash{graph};
					$hash{txt} = "$dir{graphs}/$host/$img.txt" if $_ eq 'graphs';
					push @ary, \%hash;

					# By graph later
					if ($_ eq 'thumbnails' && defined $hash{graph} &&
							defined $hash{period} && $hash{period} eq 'daily') {
						my %hash2 = %hash; delete $hash2{title}; $hash2{host} = $host;
						push @{$graph_tmpl{"$hash{graph}\t$hash{title}"}}, \%hash2;
					}
				}
				$host{$_} = \@ary;
			};
			warn $@ if $@;
		}
		$host{total_graphs} = grep(/^daily$/, map { $_->{period} } @{$host{graphs}});
		push @{$tmpl{hosts}}, \%host;
	}
}

# By graph
for (sort keys %graph_tmpl) {
	my ($graph,$title) = split(/\t/,$_);
	push @{$tmpl{graphs}}, {
			graph => $graph,
			graph_title => $title,
			total_hosts => @{$graph_tmpl{$_}}+0,
			thumbnails => $graph_tmpl{$_},
		};
}

# Print the output
#$tmpl{DEBUG} = Dumper(\%tmpl);
my $template = HTML::Template::Expr->new(
		filename => $tmpl{template},
		associate => $cgi,
		case_sensitive => 1,
		loop_context_vars => 1,
		max_includes => 5,
		global_vars => 1,
		die_on_bad_params => 0,
		functions => {
				slurp => \&slurp,
				like => sub { return $_[0] =~ /$_[1]/i ? 1 : 0; },
				equal_or_like => sub {
						return 1 if (!defined($_[1]) || !length($_[1])) && (!defined($_[2]) || !length($_[2]));
						(warn "$_[0] eq $_[1]\n" && return 1) if defined $_[1] && "$_[0]" eq "$_[1]";
						return 1 if defined $_[2] && "$_[0]" =~ /$_[2]/;
						return 0;
					},
			},
	);
$template->param(\%tmpl);
print $cgi->header(-content => 'text/html'), $template->output();

%list_cache = ();
%graph_cache = ();

exit;

sub slurp {
	my $rtn = $_[0];
	if (open(FH,'<',$_[0])) {
		local $/ = undef;
		$rtn = <FH>;
		close(FH);
	}
	return $rtn;
}

sub by_domain {
	sub split_domain {
		local $_ = shift || '';
		if (/(.*)\.(\w\w\w+)$/) {
			return ($2,$1);
		} elsif (/(.*)\.(\w+\.\w\w)$/) {
			return ($2,$1);
		}
		return ($_,'');
	}
	my @A = split_domain($a);
	my @B = split_domain($b);

	($A[0] cmp $B[0])
		||
	($A[1] cmp $B[1])
}

sub alpha_period {
	my %order = qw(daily 0 weekly 1 monthly 2 annual 3 3year 4);
	($a =~ /^(.+)\-/)[0] cmp ($b =~ /^(.+)\-/)[0]
		||
	$order{($a =~ /^.+\-(\w+)\./)[0]} <=> $order{($b =~ /^.+\-(\w+)\./)[0]}
}

sub list_dir {
	my $dir = shift;
	my @items = ();
	opendir(DH,$dir) || die "Unable to open file handle for directory '$dir': $!";
	@items = grep(!/^\./,readdir(DH));
	closedir(DH) || die "Unable to close file handle for directory '$dir': $!";
	return @items;
}

sub graph_def {
	my ($gdefs,$graph) = @_;
	return {} unless defined $graph;

	my $rtn = {};
	for (keys %{$gdefs->{graph}}) {
		my $graph_key = qr(^$_$);
		if ($graph =~ /$graph_key/) {
			$rtn = { %{$gdefs->{graph}->{$_}} };
			my ($var) = $graph =~ /_([^_]+)$/;
			for my $key (keys %{$rtn}) {
				$rtn->{$key} =~ s/\$1/$var/g;
			}
			last;
		}
	}

	return $rtn;
}

sub read_graph_data {
	my $filename = shift || undef;

	my %config = ();
	eval {
		my $conf = new Config::General(
			-ConfigFile				=> $filename,
			-LowerCaseNames			=> 1,
			-UseApacheInclude		=> 1,
			-IncludeRelative		=> 1,
#			-DefaultConfig			=> \%default,
			-MergeDuplicateBlocks	=> 1,
			-AllowMultiOptions		=> 1,
			-MergeDuplicateOptions	=> 1,
			-AutoTrue				=> 1,
		);
		%config = $conf->getall;
	};
	warn $@ if $@;

	return \%config;
}

1;

