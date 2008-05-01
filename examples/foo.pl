#!/bin/env perl

use strict;
use RRD::Simple 1.44;
 
my $rrd = RRD::Simple->new( file => "$ENV{HOME}/webroot/www/rrd.me.uk/data/boromir.rbsov.tfb.net/mem_usage.rrd" );
 
$rrd->graph(
		periods => [ qw( month weekly ) ],
		destination => "$ENV{HOME}/webroot/www/bb-207-42-158-85.fallbr.tfb.net/D:/",
		title => "Memory Utilisation",
		base => 1024,
		vertical_label => "bytes",
		sources => [ qw(Total Used) ],
		source_drawtypes => [ qw(AREA LINE1) ],
		source_colours => "dddddd 0000dd",
		lower_limit => 0,
		rigid => "",
		"VDEF:D=Used,LSLSLOPE" => "",
		"VDEF:H=Used,LSLINT" => "",
		"VDEF:F=Used,LSLCORREL" => "",
		"CDEF:Proj=Used,POP,D,COUNT,*,H,+" => "",
		"LINE1:Proj#dd0000: Projection" => "",
		"SHIFT:Total:-604800" => "",
		"SHIFT:Used:-604800" => "",
	);

$rrd->graph(
		periods          => [ qw( weekly daily ) ],
		destination      => "$ENV{HOME}/webroot/www/bb-207-42-158-85.fallbr.tfb.net/D:/",

		title            => "Memory Utilisation",
		vertical_label   => "bytes",
		base             => 1024,
		lower_limit      => 0,
		rigid            => "",

		sources          => [ qw(Total) ],
		source_drawtypes => [ qw(AREA) ],
		source_colours   => "dddddd",

		"CDEF:Used0=Used","",
		"SHIFT:Total:-172800" => "",
		"SHIFT:Used:-172800" => "",

		"CDEF:Used2=Used,0.98,*","",	"AREA:Used2#F90000:Used","",

		"CDEF:UsedMb=Used,1024,/,1024,/","",
		'GPRINT:UsedMb:LAST:Last\: %5.1lf MB',"",
		'GPRINT:UsedMb:MIN:Min\: %5.1lf MB',"",
		'GPRINT:UsedMb:MAX:Max\: %5.1lf MB',"",
		'GPRINT:UsedMb:AVERAGE:Avg\: %5.1lf MB',"",

		"CDEF:Used10=Used,0.90,*","",	"AREA:Used10#E10000","",
		"CDEF:Used15=Used,0.85,*","",	"AREA:Used15#D20000","",
		"CDEF:Used20=Used,0.80,*","",	"AREA:Used20#C30000","",
		"CDEF:Used25=Used,0.75,*","",	"AREA:Used25#B40000","",
		"CDEF:Used30=Used,0.70,*","",	"AREA:Used30#A50000","",
		"CDEF:Used35=Used,0.65,*","",	"AREA:Used35#960000","",
		"CDEF:Used40=Used,0.60,*","",	"AREA:Used40#870000","",
		"CDEF:Used45=Used,0.55,*","",	"AREA:Used45#780000","",
		"CDEF:Used50=Used,0.50,*","",	"AREA:Used50#690000","",
		"CDEF:Used55=Used,0.45,*","",	"AREA:Used55#5A0000","",
		"CDEF:Used60=Used,0.40,*","",	"AREA:Used60#4B0000","",
		"CDEF:Used65=Used,0.35,*","",	"AREA:Used65#3C0000","",
		"CDEF:Used70=Used,0.30,*","",	"AREA:Used70#2D0000","",
		"CDEF:Used75=Used,0.25,*","",	"AREA:Used75#180000","",
		"CDEF:Used80=Used,0.20,*","",	"AREA:Used80#0F0000","",
		"CDEF:Used85=Used,0.15,*","",	"AREA:Used85#000000","",
		"LINE1:Used#FF0000","",

#		"VDEF:foo=Used,TIME,-,172800","",
#		"VRULE:foo#00ff00" => "",

		"VDEF:D=Used0,LSLSLOPE","",
		"VDEF:H=Used0,LSLINT","",
		"VDEF:F=Used0,LSLCORREL","",
		"CDEF:Proj=Used0,POP,D,COUNT,*,H,+","",
		"LINE2:Proj#7700dd: Projection","",
		"LINE1:Proj#ff00ff","",
	);

