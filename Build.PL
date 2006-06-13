# vim:ts=4:sw=4:tw=78
# $Id$

use strict;
use Module::Build;
use vars qw($build);

BEGIN {
	eval "use RRDs";
	if ($@) {
		warn qq{
+-----------------------------------------------------------------------------+
| WARNING! -- Could not load RRDs.pm                                          |
|                                                                             |
| RRD::Simple requires RRDs.pm (a part of RRDtool) in order to function. You  |
| can download a copy of RRDtool from http://www.rrdtool.org. See the INSTALL |
| document for more details.                                                  |
+-----------------------------------------------------------------------------+

} unless $ENV{AUTOMATED_TESTING};
	}
}

$build = Module::Build->new(
		module_name        => 'RRD::Simple',
		license            => 'open_source',
		create_makefile_pl => 'passthrough',
		create_readme      => 1,
		create_packlist    => 1,
		sign               => 0,

		requires => {
			'File::Spec'     => 0, # 3.15
			'File::Basename' => 0, # 2.73
			'File::Temp'     => 0, # 0.16
			'File::Copy'     => 0, # 2.08
			'RRDs'           => 0, # 1.2013
			'Carp'           => 0, # 1.04
		},

		build_requires => {
			'Test'                => 0, # 1.25
			'Test::More'          => 0, # 0.60
		},

		recommends => {
			'Test::Pod'           => 1.20,
			'Test::Pod::Coverage' => 1.06,
			'Test::Deep'          => 0.093,
		},

		conflicts => {
			'RRDTool::Managed' => 0,
		},

		add_to_cleanup => [ qw(
			t/21test.rrd t/22test.rrd t/23test.rrd t/24test.rrd t/25test.rrd
			t/26add_source.rrd t/30assume_rrd_filename.rrd t/34test.rrd
			t/31create_assume_rrd_filename.rrd t/32test.rrd t/33test.rrd
		) ],
	);

$build->create_build_script;


# Send perl and module version information home if we've been given
# permission to do so by a human being - default to not send for automated
# testing environments, of if the user does not respond within 20 seconds.

my $url = $ENV{AUTOMATED_TESTING} ? undef : may_send_version_information();
if ($url) {
	my @resp = ();
	eval {
		local $SIG{ALRM} = sub { die; };
		alarm 10;
		my $ua = LWP::UserAgent->new(
				agent => 'Build.PL $Revision$',
				timeout => 9,
				max_size => 500,
			);
		$ua->env_proxy;
		my $response = $ua->get($url);
		if ($response->is_success()) {
			for (split(/\s*\n+\s*/, $response->content())) {
				push @resp, $_ if $_;
			}
		}
		alarm 0;
	};
	print substr($resp[0],0,79) || "Thank you for sending this information.";
	print "\n\n";
}

sub may_send_version_information {
	eval {
		require Config;
		require LWP::UserAgent;
	};
	return undef if $@;

	my $str = sprintf('%s?%s=%s&%s=%s&%s=%s&%s=%s&%s=%s&%s=%s',
			'http://perlgirl.org.uk/lib/usage.cgi',
			'name',     $build->dist_name(),
			'version',  $build->dist_version(),
			'osname',   $Config::Config{osname},
			'archname', $Config::Config{archname},
			'osver',    $^O,
			'perlver',  $]
		);

	print "\nThank you for downloading ".$build->dist_name()."\n\n";
	print "I would like to find out how many people are using this software,\n";
	print "and on what operating systems and Perl versions. If you have an\n";
	print "internet connection, may I transmit the following information:\n\n";
	print "$str\n\n";

	my $send = 0;
	eval {
		local $SIG{ALRM} = sub { die; };
		alarm 20;
		$send = $build->y_n('Send this anonymous information?','n');
		alarm 0;
	};

	return $send ? $str : undef;
}

1;

