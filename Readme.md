## Cluster::Jobs - A Perl module for submitting scripts to a job manager/scheduler

### Description

Cluster::Jobs provides a Perl interface to submit sequential and parallel jobs to a job manager/scheduler like HTCondor or TORQUE. Jobs can also be executed locally with bash or make.

### Synopsis
    use FindBin qw($Bin);

    use lib "$Bin/lib/Cluster";
    use Jobs;

    my $job = Jobs->new( -config => "config.ini");

    ## e.g. 
    ## 2 bwa scripts created beforehand
    $job->add_job(script => "test.sh" , name => "test" , program => "bwa");
    $job->add_job(script => "test2.sh", name => "test2", program => "bwa", dependency => "test");

    ## test2.sh will run after test.sh

    $job->submit("test_bwa");

### Config file format (Config::IniFiles)
    [job]
    manager=bash   # condor|make|torque

    [bwa]
    cmd=/NGS/ngs_pipeline/bin/bwa-0.7.12/bwa
    cpu=4          # number of cpu/core needed for condor/torque.
    mem=9          # Maximum amount of memory for condor/torque (4 = 4GB).
    time=82:01:02  # Maximum running time for torque (HH:MM:SS).

    [make]
    cpu=2    # make will run 2 jobs in parallel when used as a job manager.


### Requirements

Cluster::Jobs use the perl modules [Config::IniFiles](https://metacpan.org/release/Config-IniFiles) and [IPC::Cmd](https://metacpan.org/release/IPC-Cmd) 

    ## install from cpan
    cpan -i Config::IniFiles IPC::Cmd

### Alternatives

 * [Grid::Request](https://metacpan.org/release/Grid-Request) - An API for submitting jobs to a computational grid such as SGE or Condor.
 * [HPCI](https://metacpan.org/pod/HPCI) - High Performance Computing Interface
 * [PBS::Client](https://metacpan.org/release/PBS-Client) - Perl interface to submit jobs to Portable Batch System (PBS).



