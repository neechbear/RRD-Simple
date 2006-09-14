############################################################
#
#   $Id: Examples.pm 756 2006-08-24 22:30:54Z nicolaw $
#   RRD::Simple::Examples - Examples POD for RRD::Simple
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

package RRD::Simple::Examples;
# vim:ts=4:sw=4:tw=78

=pod

=head1 NAME

RRD::Simple::Examples

=head1 EXAMPLES

=head2 Example 1: Basic Data Gathering Using vmstat

 my $rrd = new RRD::Simple;
 
 my @keys = ();
 my %update = ();
 open(PH,'-|',$cmd) || die "Unable to open file handle PH for command '$cmd': $!";
 while (local $_ = <PH>) {
     next if /---/;
     s/^\s+|\s+$//g;
     if (/\d+/ && @keys) {
         @update{@keys} = split(/\s+/,$_);
     } else { @keys = split(/\s+/,$_); }
 }
 close(PH) || die "Unable to close file handle PH for command '$cmd': $!";
 
 my @cpukeys = splice(@keys,-4,4);
 my %labels = (wa => 'IO wait', id => 'Idle', sy => 'System', us => 'User');
 
 my $rrdfile = "vmstat-cpu.rrd";
 $rrd->create($rrdfile, map { ($_ => 'GAUGE') } @cpukeys )
     unless -f $rrdfile;

 $rrd->update($rrdfile, map {( $_ => $update{$_} )} @cpukeys );

=head1 COPYRIGHT

Copyright 2005,2006 Nicola Worthington.

This software is licensed under The Apache Software License, Version 2.0.

L<http://www.apache.org/licenses/LICENSE-2.0>

=cut

1;

