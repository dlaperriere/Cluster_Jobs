#!/usr/bin/env perl

=head1 Description

  Run 4 jobs with dependencies.

=cut

use strict;
use warnings;

use Cwd;
use FindBin qw($Bin);

use lib "$Bin/../lib/Cluster";
use Jobs;

sub hello_script($) {
    my ($msg) = @_;
    my $dir = getcwd;
    open( S, ">", "$msg.sh" ) or die "could not write script $msg: $!\n";
    print S "#!/bin/bash\n";
    print S "cd $dir\n";
    print S "perl $Bin/../bin/hello.pl $msg\n";
    close(S);
    chmod 0711, "$msg.sh";
}

my $job = Jobs->new( -config => "$Bin/../config.ini" );

&hello_script("hello1");
$job->add_job( "hello1.sh", "hello1", "hello" );

# $job->add_job( script => "hello1.sh", name => "hello1", program => "hello" );

&hello_script("hello2");

# $job->add_job( "hello2.sh", "hello2", "hello", "hello1" );
$job->add_job(
    script     => "hello2.sh",
    name       => "hello2",
    program    => "hello",
    dependency => "hello1"
);

&hello_script("hello3");
$job->add_job( "hello3.sh", "hello3", "hello", "hello1" );

&hello_script("hello4");
$job->add_job( "hello4.sh", "hello4", "hello", "hello2:hello3" );


$job->graphviz("test_ok");
$job->submit("test_ok");

=head1 Author

David Laperriere <david.laperriere@umontreal.ca>

=cut

