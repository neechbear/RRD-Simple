# $Id$

chdir('t') if -d 't';

BEGIN {
	use Test::More;
	eval "use RRDs";
	plan skip_all => "RRDs *MUST* be installed!" if $@;
	plan tests => 2 if !$@;
}

use lib qw(./lib ../lib);
use_ok('RRD::Simple');
require_ok('RRD::Simple');

1;

