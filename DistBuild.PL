#!/usr/bin/env perl
############################################################
#
#   $Id$
#   DistBuild.PL - CPAN Distribution Build Script for Subversion & CVS
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

use 5.6.1;
use strict;
use warnings;
use vars qw($build);

$build = undef;
do 'Build.PL';

die unless -f 'DistBuild.PL' && -f 'Build.PL' && -d 'lib';
$build->do_system('find . -type f | xargs chmod 644; find . -type d | xargs chmod 755');
umask 0000;
chmod 0644, 'Build.PL';
chmod 0755, 'DistBuild.PL';

check_repository();

if ($ENV{CVSROOT} && -d 'CVS' && !-d '.svn' && `which cvs2cl.pl`) {
	stage('Updating ChangeLog');
	$build->do_system('cvs2cl.pl', qw(-r -t -T -P --fsf --no-times))
		&& unlink 'ChangeLog.bak';
}

unlink 'MANIFEST';
stage('Updating MANIFEST');
$build->dispatch('manifest');

stage('Updating META.yml');
$build->dispatch('distmeta');

stage('Building');
$build->dispatch('build');

stage('Checking for essential files');
check_essential_files();

stage('Testing');
$build->dispatch('test', verbose => 0);

stage('Installing');
$build->dispatch('install');

stage('Building distribution tarball');
my @tarballs = ();
if (check_repository(uncommited_only => 1, silent => 1, ignore => "(META.yml|Makefile.PL|README|blib|_build|Build|MANIFEST|tarballs/)")) {
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

check_repository(uncommited_only => 1);

print "\n";
exit;



sub check_repository {
	my %opts = @_;
	my $uncommited_files = 0;
	$opts{ignore} ||= '(META.yml|Makefile.PL|README|blib|_build|Build|MANIFEST)';

	my ($cvs,$svn) = (0,0);
	if (-d 'CVS' && !-d '.svn') {
		$cvs = 1;
	} elsif (-d '.svn' && !-d 'CVS') {
		$svn = 1;
	} elsif (-d '.svn' || -d 'CVS') {
		die "Found both ./.svn/ and ./CVS/; way too confusing!\n";
	} else {
		warn "Couldn't find ./.svn/ or ./CVS/; skipping repository checks ...\n"
	}

	if ($cvs) {
		stage('Checking file statuses in CVS ...') unless $opts{no_stage};
		my $cmd = sprintf("cvs -q status | grep File: | %s egrep -v '%s' %s",
				($opts{uncommited_only} ? ' grep -v "Status: Up-to-date" | ' : ''),
				$opts{ignore},
				($opts{silent} ? ' >/dev/null 2>&1 ' : ''),
			);
		my $rtn = $build->do_system($cmd);
		$uncommited_files = $rtn if $opts{uncommited_only};

	} elsif ($svn) {
		stage('Checking file statuses in Subversion ...') unless $opts{no_stage};
		my $cmd = sprintf("svn status | egrep -v '%s' %s",
				$opts{ignore},
				($opts{silent} ? ' >/dev/null 2>&1 ' : ''),
			);
		my $rtn = $build->do_system($cmd);
		$uncommited_files = $rtn;
	}

	return $uncommited_files;
}


sub stage {
	local $_ = shift;
	chomp;
	print "\n\n".('*'x60).
		"\n* $_\n".
		('*'x60)."\n";
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


sub move_dist_tarballs {
	my @file = glob('*.tar.gz');
	push @file, glob('*.ppd');
	my @tarballs = ();
	for (@file) {
		print "Moving $_ to tarballs/$_\n";
		#unlink "tarballs/$_" if -e "tarballs/$_";
		rename $_, "tarballs/$_";
		push @tarballs, "tarballs/$_" if -f "tarballs/$_";
	}
	return @tarballs;
}


BEGIN {
	$ENV{AUTOMATED_TESTING} = 1;
	for (qw(MANIFEST.bak),glob('*.tar.gz'),glob('*.tar'),glob('*.ppd')) {
		unlink($_) if defined($_) && -e $_;
	}
	system('find . -maxdepth 3 -type f -name "*.rrd" | xargs rm -fv');
}


END {
	for (qw(MANIFEST MANIFEST.bak),glob('*.tar.gz'),glob('*.tar'),glob('*.ppd')) {
		unlink($_) if defined($_) && -e $_;
	}
}


__END__



