#!/usr/bin/env perl

=head1 Description

  Run a list of jobs
  
=head1 Usage

    perl run_joblist.pl -config ini_file -list joblist.txt 
    
    joblist file format (tsv)
    
    command  | name  | program | dependency
    -------- | ----- | ------- | ----------
    echo ok  | echo1 | 	hello  | 
    echo ok2 | echo2 | 	hello  | echo1
    echo ok3 | echo3 | 	hello  | echo1:echo2


=cut

use strict;
use warnings;

use Cwd;
use FindBin qw($Bin);
use File::Basename;
use Getopt::Long;
use Pod::Usage;

use lib "$Bin/lib/Cluster";
use Jobs;

## methods

sub usage($){
  my ($msg) = @_;
  $msg = " " unless $msg;
  print "$msg\n";
  print "usage: perl run_joblist.pl -config ini_file -list joblist.txt
 \n";
  exit(0);
}

sub generate_bash($$){
  my ($cmd,$name) = @_;
    my $dir = getcwd;
    my $script = "$name.sh";
    open( S, ">", $script ) or die "could not write script $script: $!\n";
    print S "#!/bin/bash\n";
    print S "cd $dir\n";
    print S "$cmd\n";
    print S "status=\$?\n";
    print S "exit \$status\n";
    close(S);
    
    chmod 0711, $script;
    return $script;
}


## process parameters
my ($config,$joblist);
my $help = 0;


my $options_ok = GetOptions(
     "help|?"     => \$help,
     "config=s"  => \$config,
     "list=s"     => \$joblist
    );

&usage() unless $options_ok;
&usage() if $help;
&usage("missing parameter ...") unless $config and $joblist;

&usage("could not read config file \'$config\': $! \n") unless -f $config;
&usage("could not read joblist file \'$joblist\': $! \n") unless -f $joblist;

## create job list
my $job = Jobs->new( -config => $config );

open(JOBLIST, "<", $joblist) or die "could not read $joblist: $!\n";
while(my $line = <JOBLIST>){
	chomp($line);
	my ($cmd,$name,$program,$dependency) = split("\t",$line);
	$dependency = "" unless $dependency;
	if(not defined $cmd or not defined $name or not defined $program){next;}
	
	my $script = &generate_bash($cmd,$name);
	$job->add_job(script => $script, name => $name, program => $program, dependency => $dependency);
}
close(JOBLIST);

# $job->graphviz($joblist);
$job->submit($joblist);


=head1 Author

David Laperriere <david.laperriere@umontreal.ca>

=cut
