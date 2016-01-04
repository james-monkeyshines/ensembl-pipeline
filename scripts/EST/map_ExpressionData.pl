#!/usr/bin/env perl


# Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


=head1 NAME

map_ExpressionData.pl

=head1 SYNOPSIS
 
this is a clone of run_EST_RunnableDB

=head1 DESCRIPTION


=head1 OPTIONS

    -dhhost    host name for database (gets put as host= in locator)

    -dbport    For RDBs, what port to connect to (port= in locator)

    -dbname    For RDBs, what name to connect to (dbname= in locator)

    -dbuser    For RDBs, what username to connect as (dbuser= in locator)

    -dbpass    For RDBs, what password to use (dbpass= in locator)

    -input_id  The input id for the RunnableDB

    -runnable  The name of the runnable module we want to run

    -analysis  The number of the analysisprocess we want to run
=cut

use warnings ;
use strict;
use Getopt::Long qw(:config no_ignore_case);

# this script connects to the db it is going to write to

use Bio::EnsEMBL::Pipeline::RunnableDB::MapGeneToExpression;
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Pipeline::Config::cDNAs_ESTs::GenesToExpression qw ( EST_DBNAME
                                                                       EST_DBHOST
                                                                       EST_DBPORT
	                                                               EST_DBUSER
	                                                               EST_DBPASS
                                                                     );


use Bio::EnsEMBL::DBSQL::DBAdaptor;
#use Bio::EnsEMBL::DBLoader;

my $dbtype = 'rdb';
my $dbname = $EST_DBNAME;
my $dbuser = $EST_DBUSER;
my $dbpass = $EST_DBPASS;
my $host   = $EST_DBHOST;
my $port   = $EST_DBPORT; 


my $runnable;
my $input_id;
my $write  = 0;
my $check  = 0;
my $params;
my $pepfile;
my $acc;
my $analysis;

# can override db options on command line
GetOptions( 
	     'input_id:s'    => \$input_id,
	     'runnable:s'    => \$runnable,
             'analysis:s'    => \$analysis,
	     'write'         => \$write,
             'check'         => \$check,
             'parameters:s'  => \$params,
             'dbname|db|D:s'      => \$dbname,
             'host|dbhost|h:s'      => \$host,
             'user|dbuser|u:s'      => \$dbuser,
             'pass|dbpass|p:s'      => \$dbpass,
             'port|dbport|P:s'      => \$port
	     );

$| = 1;

die "No runnable entered" unless defined ($runnable);
(my $file = $runnable) =~ s/::/\//g;
require "$file.pm";


if ($check) {
   exit(0);
}

#print STDERR "args: $host : $dbuser : $dbpass : $dbname\n";



my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
    -host             => $host,
    -port             => $port,
    -user             => $dbuser,
    -dbname           => $dbname,
    -pass             => $dbpass,
    -perlonlyfeatures => 0,
);

print STDERR "db: $db, dbname: $dbname, dbhost: $host, dbport $port\n";

die "No input id entered" unless defined ($input_id);

my $analysis_obj = $db->get_AnalysisAdaptor->fetch_by_logic_name($analysis);

my %hparams;
# eg -parameters param1=value1,param2=value2
if (defined $params){
  foreach my $p(split /,/, $params){
    my @sp = split /=/, $p;
    $sp[0] = '-' . $sp[0];
    $hparams{$sp[0]} =  $sp[1];
  }
}


my $runobj = "$runnable"->new(-db       => $db,
			      -input_id => $input_id,
                              -analysis => $analysis_obj,
			      %hparams,
			     );


$runobj->fetch_input;
$runobj->run;



if ($write) {
  $runobj->write_output;
}

