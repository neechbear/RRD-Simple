#!/usr/bin/perl -w

use strict;
use RRD::Simple;
use Data::Dumper;

my $rrdfile = '/home/system/colloquy/botbot/logs/botbot.rrd';
my $destdir = '/home/nicolaw/webroot/www/www.neechi.co.uk';

my @rtn = RRD::Simple->graph($rrdfile,
		destination => $destdir,
		'vertical-label' => 'Messages',
		'title' => 'Talker Activity',
	);

print Dumper(\@rtn);

