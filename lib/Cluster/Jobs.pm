package Jobs;

use 5.008;

use strict;
use warnings;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw();
$VERSION = '1.03';

use Carp;
use Cwd;
use File::Basename;

use IPC::Cmd qw[can_run run];
use Config::IniFiles;

=encoding utf8
 
=head1 Description

 Cluster::Jobs - A module for submitting scripts to a job manager/scheduler

=head1 Usage

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


=head1 Config file format
 
 [job]
 manager=bash   # condor|make|torque
 
 [bwa]
 cmd=/NGS/ngs_pipeline/bin/bwa-0.7.12/bwa
 cpu=4          # number of cpu/core needed for condor/torque
 mem=9          # Maximum amount of memory for condor/torque (4 = 4GB).
 time=82:01:02  # Maximum running time for torque (HH:MM:SS).
  
 [make]
 cpu=2    # make will run 2 jobs in parallel when used as a job manager

=head1 Methods

=cut

=head2 new()
 
Constructor

=head3 parameters

  $config     : Config filename

=cut

sub new {
    my ( $class, @args ) = @_;

    ## internal variables
    my $config = undef;
    my %jobs   = ();      # job_num -> script name program dependencies

    my %params = @args;
    @params{ map { lc $_ } keys %params } = values %params;    # lowercase keys

    $config = $params{'-config'};

    croak("Missing config file...") unless $params{'-config'};
    croak("Could not read config file \"$config\":\n $! ...")
      unless -f $params{'-config'};

    my $self = bless {
        config => $config,
        jobs   => \%jobs,

    }, $class;

    return $self;
}    # /new

=head2 add_job()
 
Add a job

=head3 parameters

  $script     : bash script filename
  $name       : name of the job (used to record job id)
  $program    : name of the program in config file (i.e. bwa, picard)
  $dependency : job dependencies $job1:$job2

=cut

sub add_job {
    my ( $self, $script, $name, $program, $dependency );
    $self = shift @_;

    if ( scalar( grep $_, @_ ) <= 4 ) {

        # add_job( "hello1.sh", "hello1", "hello" );
        ( $script, $name, $program, $dependency ) = @_;
    }
    else {
       # add_job( script => "hello1.sh", name => "hello1", program => "hello" );
        my %params = @_;
        $script     = $params{script};
        $name       = $params{name};
        $program    = $params{program};
        $dependency = $params{dependency};

    }

    my $jobs       = $self->{jobs};
    my $job_number = $self->num_jobs;
    $job_number++;

    if ( not defined $dependency ) { $dependency = ""; }
    $$jobs{$job_number} = join( "\a", $script, $name, $program, $dependency );

    return $job_number;
}    #/ add_job

=head2 check()
 
Check that the list of jobs does not have circular dependencies

=head3 parameters

  $sorted_jobs  : ref that will contain the list og jobs in topological order  (job1:job2..)

=cut

sub check {
    my ( $self, $sorted_jobs ) = @_;

    my $cycles = 1;

    ## build list of dependencies
    my %deps;
    my $jobs     = $self->{jobs};
    my $num_jobs = $self->num_jobs();
    for ( my $i = 1 ; $i <= $num_jobs ; $i++ ) {
        my $job_info = $$jobs{$i};
        my ( $script, $name, $program, $dependency ) = split( /\a/, $job_info );
        my @dep = split( /:/, $dependency );
        $deps{$name} = \@dep;
    }

    ## check for circular dependencies with topological sort based on
    ## http://rosettacode.org/wiki/Topological_sort#Perl
    ## https://web.archive.org/web/20060419115356/http://perlgolf.sourceforge.net/cgi-bin/PGAS/post_mortem.cgi?id=6
    print "Jobs:\n";
    print "-----\n";
    my %ba;
    while ( my ( $before, $afters_aref ) = each %deps ) {
        for my $after ( @{$afters_aref} ) {
            $ba{$before}{$after} = 1 if $before ne $after;
            $ba{$after} ||= {};
        }
    }

    while ( my @afters = sort grep { !%{ $ba{$_} } } keys %ba ) {
        print "@afters\n";
        $$sorted_jobs .= "@afters:";
        delete @ba{@afters};
        delete @{$_}{@afters} for values %ba;
    }

    if ( !!%ba ) { $cycles = 0; }

    print !!%ba ? "Cycle found! " . join( ' ', sort keys %ba ) . "\n" : "---\n";

    return $cycles;
}    #/ check

=head2 manager()
 
Get name of job manager/scheduler

=cut

sub manager {
    my $self = shift;

    my $config = $self->{config};
    my $cfg =
      Config::IniFiles->new( -file => $config, -handle_trailing_comment => 1 );

    croak "$config does not seem to be a valid configuration file ... \n"
      unless defined($cfg);
    croak "job section not found in $config ... \n"
      unless $cfg->SectionExists('job');
    croak "job manager not found in $config ... \n"
      unless $cfg->val( 'job', 'manager' );
    my $job_manager = $cfg->val( 'job', 'manager' );

    return $job_manager;
}

=head2 num_jobs()
 
Get number of jobs 

=cut

sub num_jobs {
    my $self = shift;

    my $num_jobs = $self->{jobs};

    return scalar keys %$num_jobs;
}

=head2 graphviz()
 
Generate graph visualization of the jobs

=head3 parameters

  $dot_filename      : name of the dot file

=head3 output

 - graphviz dot file 

 # convert to pdf
 # dot -Tpdf graphviz_file -O -v

=cut

sub graphviz {
    my ( $self, $dot_filename ) = @_;

    my $num_jobs = $self->num_jobs();
    my $manager  = $self->manager();
    my $jobs     = $self->{jobs};
     
    my $graph_name = $dot_filename;
    $dot_filename = $dot_filename . ".graphviz"
      unless $dot_filename =~ m/.graphviz/;
    
    print "generating graphviz: $dot_filename \n\n";

    open( DOT, ">", $dot_filename )
      or die "could not create graphviz file $dot_filename: $!\n";

    my %name2script;

    my $dot = <<DOT_START;
    digraph $graph_name {
      nodesep=.05;
      fontsize=12;
     //minlen=2;
     //rankdir=LR;

    // job scripts
DOT_START

    for ( my $i = 1 ; $i <= $num_jobs ; $i++ ) {
        my $job_info = $$jobs{$i};
        my ( $script, $name, $program, $dependency ) = split( /\a/, $job_info );
        $name2script{$name} = $script;
        # $dot .= "\"$script\"  [shape=box, color=blue] \n";
	$dot .= "\"$name\"  [shape=box, color=blue] \n";
    }

    $dot .= "// steps \n";
    for ( my $i = 1 ; $i <= $num_jobs ; $i++ ) {
        my $job_info = $$jobs{$i};
        my ( $script, $name, $program, $dependency ) = split( /\a/, $job_info );
        my @deps = split( /:/, $dependency );
        foreach my $dep (@deps) {
            my $dscript = $name2script{$dep};
            # $dot .= "\"$dscript\"->\"$script\" \n";
	    $dot .= "\"$dep\"->\"$name\" \n";
        }
    }
    $dot .= "} \n";
    print DOT $dot;
    print "# generate pdf with: dot -Tpdf $dot_filename -O -v \n\n";

    close(DOT);

}    #/ graphviz

=head2 submit()
 
Submit jobs to the job manager/scheduler defined in the config file

=head3 parameters

  $jobname      : name of the job manager script

=cut

sub submit {
    my ( $self, $jobname ) = @_;

    my $manager = $self->manager();

    # submit jobs to the job manager/scheduler
    if ( $manager eq "condor" ) {
        &submit_condor( $self, $jobname );
    }
    elsif ( $manager eq "make" ) {
        &submit_make( $self, $jobname );
    }
    elsif ( $manager eq "torque" ) {
        &submit_torque( $self, $jobname );
    }
    else {
        ## default to bash
        &submit_bash( $self, $jobname );
    }

}    #/ submit

=head2 submit_bash()
 
Run jobs with bash

=head3 parameters

  $jobname      : name of the job manager script

=cut

sub submit_bash {
    my ( $self, $jobname ) = @_;

    my $num_jobs = $self->num_jobs();
    my $manager  = $self->manager();
    my $jobs     = $self->{jobs};

    my $dir = getcwd;

    my $config = $self->{config};
    my $cfg =
      Config::IniFiles->new( -file => $config, -handle_trailing_comment => 1 );

    croak "$config does not appear to be a valid config file ... \n"
      unless $cfg;

    # check for circular dependencies
    my $sorted_jobs = "";
    my $no_cycle = &check( $self, \$sorted_jobs );

    if ( !$no_cycle ) {
        croak "Can not run jobs with circular dependencies...\n";
    }

    print "manager: bash \n\n";

    # run jobs with bash
    print "running jobs locally...\n";

    my %name2script;
    for ( my $i = 1 ; $i <= $num_jobs ; $i++ ) {
        my $job_info = $$jobs{$i};
        my ( $script, $name, $program, $dependency ) = split( /\a/, $job_info );
        $name2script{$name} = $script;
    }


    my $bash   = can_run("bash") or warn 'bash is not installed!';
     
    foreach my $job ( split( /:/, $sorted_jobs ) ) {
	foreach my $name (split(/\s/,$job)){

          if ( defined( $name2script{$name} ) ) {
            my $script = $name2script{$name};
        
            my $cmd    = "$bash $script";
            my ( $ok, $err ) = run( command => $cmd, verbose => 1 );
            croak $err if $err;

          }
	}
    }


}    #/ submit_bash

=head2 submit_condor()
 
Submit jobs to condor

=head3 parameters

  $jobname      : name of the job manager script

=head3 output

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

=cut

sub submit_condor {
    my ( $self, $jobname ) = @_;

    my $num_jobs = $self->num_jobs();
    my $manager  = $self->manager();
    my $jobs     = $self->{jobs};

    my $dir = getcwd;

    my $config = $self->{config};
    my $cfg =
      Config::IniFiles->new( -file => $config, -handle_trailing_comment => 1 );

    croak "$config does not appear to be a valid config file ... \n"
      unless $cfg;

    # check for circular dependencies
    my $sorted_jobs = "";
    my $no_cycle = &check( $self, \$sorted_jobs );

    if ( !$no_cycle ) {
        croak "Can not run jobs with circular dependencies...\n";
    }

    print "manager: condor \n\n";

    # submit jobs to condor
    print "submitting jobs to condor...\n";

    my $condor_script = "$jobname.condor.dag";

    ## generate condor submit and dagman script
    my $condor_script_content = "";
    my $condor_dag_deps       = "";

    for ( my $i = 1 ; $i <= $num_jobs ; $i++ ) {
        my $job_info = $$jobs{$i};
        my ( $script, $name, $program, $dependency ) = split( /\a/, $job_info );

        croak "$program section not found in $config ... \n"
          unless $cfg->SectionExists($program);

        my $cpu = $cfg->val( $program, 'cpu' );
        $cpu =~ s/^\s+|\s+$//g;
        my $mem = $cfg->val( $program, 'mem' );
        $mem =~ s/^\s+|\s+$//g;

        ### condor submit script
        my $condor_job = "$script.condor";

        my $condor_job_content = "executable=$script\n";
        $condor_job_content .= "output=$script.out.txt\n";
        $condor_job_content .= "error=$script.out.txt\n";
        $condor_job_content .= "log=$script.log.txt\n";
        $condor_job_content .= "request_memory=$mem" . "G\n";
        $condor_job_content .= "request_cpus=$cpu\n";
        $condor_job_content .= "Initialdir=$dir\n";
        $condor_job_content .= "queue\n";

        open( CS, ">", $condor_job )
          or die "could NOT write condor submit  script \'$condor_job\': $!\n";
        print CS "$condor_job_content\n";
        close(CS);

        ### condor dagman script
        my $condor_dag = "Job $name $condor_job\n";

        if ( defined($dependency) and $dependency ne "" ) {
            my $dep_list = "";
            my @dep = split( /:/, $dependency );
            $dep_list = join( " ", @dep );

            $condor_dag_deps .= "PARENT $dep_list CHILD $name\n";
        }
        $condor_script_content .= $condor_dag . "\n";

    }
    $condor_script_content .= $condor_dag_deps . "\n";

    ## write condor dagman submit script
    open( CSD, ">", $condor_script )
      or die
      "could NOT write condor submit dag script \'$condor_script\': $!\n";
    print CSD $condor_script_content, "\n\n";
    close(CSD);

    ## submit jobs to condor
    my $cmd = "condor_submit_dag -f $condor_script";

    my ( $ok, $err ) = run( command => $cmd, verbose => 1 );
    croak $err if $err;

}    #/ submit_condor

=head2 submit_make()
 
Run jobs with make

=head3 parameters

  $jobname      : name of the job manager script

=head3 output

 - make file (.makefile)

  all: hello2 hello1

  hello1:
  	@echo '#make: bash hello1.sh'
	bash hello1.sh

  hello2: hello1
  	@echo '#make: bash hello2.sh'
  	bash hello2.sh

=cut

sub submit_make {
    my ( $self, $jobname ) = @_;

    my $num_jobs = $self->num_jobs();
    my $manager  = $self->manager();
    my $jobs     = $self->{jobs};

    my $dir = getcwd;

    my $config = $self->{config};
    my $cfg =
      Config::IniFiles->new( -file => $config, -handle_trailing_comment => 1 );

    croak "$config does not appear to be a valid config file ... \n"
      unless $cfg;

    # check for circular dependencies
    my $sorted_jobs = "";
    my $no_cycle = &check( $self, \$sorted_jobs );

    if ( !$no_cycle ) {
        croak "Can not run jobs with circular dependencies...\n";
    }

    print "manager: make \n\n";

    # run jobs make make
    print "running jobs with make...\n";

    my $make_file = "$jobname.makefile";

    ## generate makefile
    my $make_file_content = "";

    my $make_option = "-j 1";
    if ( $cfg->SectionExists("make") ) {
        my $cpu = $cfg->val( "make", 'cpu' );
        $cpu =~ s/^\s+|\s+$//g;
        $make_option = "-j $cpu";
    }

    my %job_names;

    for ( my $i = 1 ; $i <= $num_jobs ; $i++ ) {
        my $job_info = $$jobs{$i};
        my ( $script, $name, $program, $dependency ) = split( /\a/, $job_info );

        croak "$program section not found in $config ... \n"
          unless $cfg->SectionExists($program);

        $job_names{$name} = 1;
        my $make_section = "";
        $make_section = "$name:\n";
        $make_section .= "\t\@echo \'#make: bash $script\'\n";
        $make_section .= "\tbash $script\n";

        if ( defined($dependency) and $dependency ne "" ) {
            my $dep_list = "";
            my @dep = split( /:/, $dependency );
            $dep_list = join( " ", @dep );

            $make_section = "$name: " . $dep_list . "\n";
            $make_section .= "\t\@echo \'#make: bash $script\'\n";
            $make_section .= "\tbash $script\n";
        }

        $make_file_content .= $make_section . "\n";

    }

    ## write makefile
    open( M, ">", $make_file )
      or die "could NOT write makefile \'$make_file\': $!\n";
    print M "all: " . join( " ", keys %job_names ) . "\n\n";
    print M $make_file_content, "\n\n";
    close(M);

    ## run with make
    my $make = can_run("make") or warn 'make is not installed!';
    my $cmd = "$make $make_option -f $make_file";

    my ( $ok, $err ) = run( command => $cmd, verbose => 1 );
    croak $err if $err;
}    #/ submit_make

=head2 submit_torque()
 
Submit jobs to torque

=head3 parameters

  $jobname      : name of the job manager script

=head3 output

 - bash script with qsub command (.pbs)

  #!/bin/bash
  cd /home/laperrie/test 
  
  hello1=`qsub   -l nodes=1:ppn=1,mem=1gb,walltime=05:02 -j oe /home/laperrie/test/hello1.sh`
  echo $hello1

  hello2=`qsub   -l nodes=1:ppn=1,mem=1gb,walltime=05:02 -W depend=afterok:$hello1 -j oe /home/laperrie/test/hello2.sh`
  echo $hello2

=cut

sub submit_torque {
    my ( $self, $jobname ) = @_;

    my $num_jobs = $self->num_jobs();
    my $manager  = $self->manager();
    my $jobs     = $self->{jobs};

    my $dir = getcwd;

    my $config = $self->{config};
    my $cfg =
      Config::IniFiles->new( -file => $config, -handle_trailing_comment => 1 );

    croak "$config does not appear to be a valid config file ... \n"
      unless $cfg;

    # check for circular dependencies
    my $sorted_jobs = "";
    my $no_cycle = &check( $self, \$sorted_jobs );

    if ( !$no_cycle ) {
        croak "Can not run jobs with circular dependencies...\n";
    }

    print "manager: torque \n\n";

    # submit jobs to torque
    print "submitting jobs to torque...\n";

    my $torque_script = "$jobname.pbs";

    ## generate torque qsub script
    my $torque_script_content = "";

    for ( my $i = 1 ; $i <= $num_jobs ; $i++ ) {
        my $job_info = $$jobs{$i};
        my ( $script, $name, $program, $dependency ) = split( /\a/, $job_info );

        croak "$program section not found in $config ... \n"
          unless $cfg->SectionExists($program);

        my $cpu = $cfg->val( $program, 'cpu' );
        $cpu =~ s/^\s+|\s+$//g;
        my $mem = $cfg->val( $program, 'mem' );
        $mem =~ s/^\s+|\s+$//g;
        my $time = $cfg->val( $program, 'time' );
        $time =~ s/^\s+|\s+$//g;

        my $qsub_options =
          " -l nodes=1:ppn=" . $cpu . ",mem=" . $mem . "gb,walltime=" . $time;
        if ( defined($dependency) and $dependency ne "" ) {
            my $dep_list = "";
            my @dep = split( /:/, $dependency );
            $dep[0] = "\$" . $dep[0];
            $dep_list = join( ":\$", @dep );

            $qsub_options .= " -W depend=afterok:" . $dep_list;
        }

        my $qsub =
          "\n$name=`qsub  $qsub_options -j oe $dir/$script`\necho \$$name\n";

        $torque_script_content .= $qsub . "\n";

    }

    ## write torque qsub script
    open( QS, ">", $torque_script )
      or die "could NOT write torque qsub script \'$torque_script\': $!\n";
    print QS "#!/bin/bash\n";
    print QS "cd $dir \n";
    print QS $torque_script_content, "\n\n";
    close(QS);

    ## submit jobs to torque
    my $bash = can_run("bash") or warn 'bash is not installed!';
    my $cmd = "$bash $torque_script";

    my ( $ok, $err ) = run( command => $cmd, verbose => 1 );
    croak $err if $err;
}    #/ submit_torque

1;

=head1 Author

David Laperriere dlaperriere@outlook.com

=cut

__END__
 
