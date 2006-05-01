# $Id$

chdir('t') if -d 't';
use lib qw(./lib ../lib);
use Test::More tests => 2;

use_ok('RRD::Simple');
require_ok('RRD::Simple');

1;

