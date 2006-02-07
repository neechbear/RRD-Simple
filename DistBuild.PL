#!/usr/bin/env perl
# vim:ts=4:sw=4:tw=78

use strict;
use warnings;
use vars qw($build);

$build = undef;
do 'Build.PL';

stage('Checking file statuses in SVN');
$build->do_system('svn status | egrep -v "(META.yml|Makefile.PL|README|blib|_build|Build|MANIFEST)"');

#stage('Updating ChangeLog');
#$build->do_system('cvs2cl.pl', qw(-r -t -T -P --fsf --no-times))
#	&& unlink 'ChangeLog.bak';

stage('Updating META.yml');
$build->dispatch('distmeta');

stage('Updating MANIFEST');
$build->dispatch('manifest');

stage('Building');
$build->dispatch('build');

#stage('Checking for essential files');
#check_essential_files();

stage('Testing');
$build->dispatch('test', verbose => 0);

stage('Installing');
$build->dispatch('install');

stage('Building distribution tarball');
my @tarballs = ();
if ($build->do_system('svn status | egrep -v "(META.yml|Makefile.PL|README|blib|_build|Build|MANIFEST)" > /dev/null 2>&1')) {;
	print "Uncommited files; skipping ...\n";
} else {
	$build->dispatch('distcheck');
	$build->dispatch('dist');
	$build->dispatch('ppmdist');

	stage('Moving distribution tarball');
	@tarballs = move_dist_tarballs();
}

stage('Cleaning up');
$build->dispatch('distclean');
unlink 'MANIFEST.bak' if -e 'MANIFEST.bak';

stage('Checking file statuses in SVN');
$build->do_system('svn status | egrep -v "(META.yml|Makefile.PL|README|blib|_build|Build|MANIFEST)"');

print "\n";
exit;

BEGIN {
	unlink 'MANIFEST.bak' if -e 'MANIFEST.bak';
	unlink $_ for glob('*.tar.gz'); 
	unlink $_ for glob('*.tar'); 
	system('find . -name "*.rrd" -maxdepth 3 -type f | xargs rm -fv');
}

sub stage {
	local $_ = shift;
	chomp;
	print "\n\n".('*'x60).
		"\n* $_\n".
		('*'x60)."\n";
}

sub move_dist_tarballs {
	my @file = glob('*.tar.gz');
	my @tarballs = ();
	for (@file) {
		print "Moving $_ to tarballs/$_\n";
		#unlink "tarballs/$_" if -e "tarballs/$_";
		rename $_, "tarballs/$_";
		push @tarballs, "tarballs/$_" if -f "tarballs/$_";
	}
	return @tarballs;
}

sub check_essential_files {
	my @essential_files = qw(META.yml Build.PL Makefile.PL
			LICENSE NOTICE README Changes INSTALL MANIFEST TODO
			lib t examples);

	my @missing_files = ();
	for (@essential_files) {
		push @missing_files, $_ if !-e $_;
	}

	if (@missing_files) {
		die "Missing: ".join(', ',@missing_files)."\n";
	} else {
		print "No problems found\n";
	}
}




