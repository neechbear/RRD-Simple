# vim:ts=4:sw=4:tw=78

require 5.005;
use strict;
use ExtUtils::MakeMaker qw(WriteMakefile);

$|++;

my $name = 'RRD::Simple';
my $from = 'lib/RRD/Simple.pm';

# Make the Makefile as per usual
WriteMakefile(
		NAME          => $name,
		VERSION_FROM  => $from,
		ABSTRACT_FROM => $from,
		AUTHOR        => 'Nicola Worthington <nicolaw@cpan.org>',
		PREREQ_PM     => {
				'File::Spec' => 0,
				'File::Basename' => 0,
				'File::Temp' => 0,
				'File::Copy' => 0,
				'RRDs' => 0,
				'Carp' => 0,
			},
	);

# Try and load a bunch of modules required to send an installation
# notification back to the author so that she can guestimate how
# many people are using her modules on what different platforms
eval {
	require Term::ReadKey;
	require Config;
	require LWP::Simple;
}; exit if $@;

# Get the version number of the module
my $version = '';
eval { $version = ExtUtils::MM_Unix::parse_version({},$from); };
if (!$version && open(FH,'<META.yml')) {
	while (local $_ = <FH>) {
		if (/version:\s*([0-9\.]+)/i) {
			$version = $1;
			last;
		}
	} close(FH);
}

# Build a nice little query string of anonymous information to send
# back to the author.
my $str = sprintf('?%s=%s&%s=%s&%s=%s&%s=%s&%s=%s&%s=%s',
		'name',     $name,
		'version',  $version,
		'osname',   $Config::Config{osname},
		'archname', $Config::Config{archname},
		'osver',    $^O,
		'perlver',  $]
	);

# Kindly as the user if they would mind sending this anonymous information
# back to the author
print "\nThank you for downloading $name\n\n";
print "I would like to find out how many people are using this software,\n";
print "and on what operating systems and Perl versions. If you have an\n";
print "internet connection, may I transmit the following information:\n\n";
print "http://perlgirl.org.uk/lib/usage.cgi$str\n";
print "\nSend this anonymous information? (Y/n): ";

# Read the users response. Default to a yes response if the user does not
# type anything in 20 seconds
my $send = 1;
Term::ReadKey::ReadMode(4);
1 while (defined($send = Term::ReadKey::ReadKey(20)) && $send !~ /^[yn]*$/i);
$send = $send =~ /^n$/i ? 0 : 1;
print $send ? "y\n\n" : "n\n\n";
Term::ReadKey::ReadMode(0);

# Finish if the user does not want to send the information
exit unless $send;

# Otherwise send the information
my $resp = '';
eval {
	local $SIG{ALRM} = sub { die "alarm\n" };
	alarm 10;
	$resp = LWP::Simple::get("http://perlgirl.org.uk/lib/usage.cgi$str");
	alarm 0;
};

# Give some feedback to indicate wether the data was sent or not
if ($@) {
	print "Unfortunately I failed to send the information. Thank you anyway.\n";
} else {
	print substr($resp,0,500) || "Thank you for sending this information.\n";
}

# Finish
print "\n";


