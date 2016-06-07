#!/usr/bin/env perl

=head1 Description

  Install required perl modules from cpan

=cut

use strict;
use warnings;

my @modules = ( "Config::IniFiles", "IPC::Cmd" );

foreach my $module (@modules) {
    my @cpan_cmd = ( "cpan", "-i", $module );
    system(@cpan_cmd) == 0 or die "$module installation failed : $?\n";
}
