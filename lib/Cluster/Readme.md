# Description

    Cluster::Jobs - A module for submitting scripts to a job manager/scheduler

# Usage

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

    $job->submit("test_bwa");

# Config file format

    [job]
    manager=bash   # condor|make|torque
    
    [bwa]
    cmd=/NGS/ngs_pipeline/bin/bwa-0.7.12/bwa
    cpu=4          # number of cpu/core needed for condor/torque
    mem=9          # Maximum amount of memory for condor/torque (4 = 4GB).
    time=82:01:02  # Maximum running time for torque (HH:MM:SS).
     
    [make]
    cpu=2    # make will run 2 jobs in parallel when used as a job manager

# Methods

## new()

Constructor

### parameters

    $config     : Config filename

## add\_job() : Add a job

### parameters

    $script     : bash script filename
    $name       : name of the job (used to record job id)
    $program    : name of the program in config file (i.e. bwa, picard)
    $dependency : job dependencies $job1:$job2

## check() :  Check that the list of jobs does not have circular dependencies

### parameters

    $sorted_jobs  : ref that will contain the list og jobs in topological order  (job1:job2..)

## manager() : Get name of job manager/scheduler

## num\_jobs() : Get number of jobs 

##  graphviz() :  Generate graph visualization of the jobs

###   parameters
      $dot_filename      : name of the dot file

###   output
     - graphviz dot file

     # convert to pdf
     # dot -Tpdf graphviz_file -O -v


## submit() : Submit jobs to the job manager defined in the config file

### parameters

    $jobname      : name of the job manager script

## submit\_bash() : Run jobs with bash

### parameters

    $jobname      : name of the job manager script

## submit\_condor() : Submit jobs to condor

### parameters

    $jobname      : name of the job manager script

### output

    - condor submit file for each job (.condor)

     executable=hello1.sh
     output=hello1.sh.out.txt
     error=hello1.sh.out.txt
     log=hello1.sh.log.txt
     request_memory=1G
     request_cpus=1
     Initialdir=/home/laperrie/test
     queue

    - DAGMan input file (.dag)

     Job hello1 hello1.sh.condor
     Job hello2 hello2.sh.condor

     PARENT hello1 CHILD hello2

## submit\_make() : Run jobs with make

### parameters

    $jobname      : name of the job manager script

### output

    - make file (.makefile)

     all: hello2 hello1

     hello1:
           @echo '#make: bash hello1.sh'
           bash hello1.sh

     hello2: hello1
           @echo '#make: bash hello2.sh'
           bash hello2.sh

## submit\_torque() : Submit jobs to torque

### parameters

    $jobname      : name of the job manager script

### output

    - bash script with qsub command (.pbs)

     #!/bin/bash
     cd /home/laperrie/test 
     
     hello1=`qsub   -l nodes=1:ppn=1,mem=1gb,walltime=05:02 -j oe /home/laperrie/test/hello1.sh`
     echo $hello1

     hello2=`qsub   -l nodes=1:ppn=1,mem=1gb,walltime=05:02 -W depend=afterok:$hello1 -j oe /home/laperrie/test/hello2.sh`
     echo $hello2

# Author

David Laperriere dlaperriere@outlook.com
