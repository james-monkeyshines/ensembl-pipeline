#
# module Bio::EnsEMBL::Pipeline::Config::cDNAs_ESTs::EST_GeneBuilder_Conf
#
# Copyright GRL & EBI
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Pipeline::Config::cDNAs_ESTs::EST_GeneBuilder_Conf - imports global variables used by EnsEMBL EST analysis

=head1 SYNOPSIS

    use Bio::EnsEMBL::Pipeline::Config::cDNAs_ESTs::EST_GeneBuilder_Conf;
 
=head1 DESCRIPTION

This class is a pure ripoff of humConf written by James Gilbert.

humConf is based upon ideas from the standard perl Env environment
module.

It imports and sets a number of standard global variables into the
calling package, which are used in many scripts in the human sequence
analysis system.  The variables are first declared using "use vars",
so that it can be used when "use strict" is in use in the calling
script.  Without arguments all the standard variables are set, and
with a list, only those variables whose names are provided are set.
The module will die if a variable which doesn\'t appear in its
C<%EST_GeneBuilder_Conf> hash is asked to be set.

The variables can also be references to arrays or hashes.

Edit C<%EST_GeneBuilder_Conf> to add or alter variables.

All the variables are in capitals, so that they resemble environment
variables.

=head1 CONTACT

=cut


package Bio::EnsEMBL::Pipeline::Config::cDNAs_ESTs::EST_GeneBuilder_Conf;

use strict;
use LowCoverageGeneBuildConf;
use vars qw( %EST_GeneBuilder_Conf );

# Hash containing config info]
%EST_GeneBuilder_Conf = (
	    # general options for scripts

	    # path to run_ESTRunnableDB
	    	    
	    # for Rat
	    EST_INPUTID_REGEX => '(\S+)\.(\d+)-(\d+)',
	    
	    # path to run_EST_GeneBuilder.pl, script that launches EST_GeneBuilder.pm
	    EST_GENE_RUNNER   => '/nfs/acari/eae/ensembl/ensembl-pipeline/scripts/EST/run_EST_GeneBuilder.pl',
	    
            # where the result-directories are going to go	
    	    EST_TMPDIR        => '/ecs2/scratch5/ensembl/eae/human_estgenes_eae_rerun/',	    
	    # job-queue in the farm
	    EST_QUEUE         => 'acari',
	    
	    EST_GENEBUILDER_BSUBS => '/ecs2/scratch5/ensembl/eae/human_estgenes_eae_rerun/EST_Genebuilder.jobs',
	    
	    ############################################################
	    # each runnable has an analysis
	    ############################################################
	    
	    EST_GENEBUILDER_RUNNABLE   => 'Bio::EnsEMBL::Pipeline::RunnableDB::EST_GeneBuilder',
	    EST_GENEBUILDER_ANALYSIS   => 'hum_cdna_genebuilder',

	    ############################################################
	    # EST_GeneBuilder
	    ############################################################
			 
	    EST_GENEBUILDER_CHUNKSIZE        => 1000000,      #  we use 1000000 (ie 1MB) chunks
		  
	    EST_GENEBUILDER_INPUT_GENETYPE => 'hum_cdna_exonerate',
	    ESTGENE_TYPE                   => 'hum_cdna_genebuilder',
	    

	    # where we have a genome (path to the softmasked, dusted chromosomes | scaffolds), same var as used on Exonerate.pm
	    # It should be a set of fastA files with
	    # each file as chr_name.fa, all with the same line length
	    EST_GENOMIC      => $LC_GENOMICSEQS,

	    # ORFs can be calculated with genomewise (which has a bug (14/08/2003))
	    # or with a simpler method which takes the longest ORF starting with M,
	    # and if there is none, it takes the longest ORF.
	    USE_GENOMEWISE    => 0,			 
	    
			 # if the slice chunk has over this number of ESTs
			 # a filter procedure fires off:
                         USE_EST_DEFAULT_FILTERING => 1,
			 MAX_NUMBER_ESTS    => 200,
	    			 
			 # if this is set to TRUE it will reject ests that do not
			 # have all splice sites correct
			 CHECK_SPLICE_SITES => 1,

			 # if set to a number, it will reject single exon ests that are shorter that this
			 FILTER_ON_SINGLETON_SIZE => 200,

			 # if set to a number, it will reject single exon ests that have score smaller than this
			 RAISE_SINGLETON_COVERAGE => 95,

	                 ## you must choose one type of merging for cdnas/ests: 2 and 3 are the common ones
			 EST_GENEBUILDER_COMPARISON_LEVEL => 2,
			 
			 # for details see documentation 
			 # in Bio::EnsEMBL::Pipeline::GeneComparison::TranscriptComparator
			 # 1 --> strict: exact exon matching (unrealistic). 
			 # 2 --> allow edge exon mismatches
			 # 3 --> allow internal mismatches
			 # 4---> allow intron mismatches
			 # 5---> loose mode - consecutive exon overlap - allows intron mismatches
			 
			 # you can alow a mismatch in the splice sites
			 EST_GENEBUILDER_SPLICE_MISMATCH  => 8,
			 
			 # you can allow matches over small introns 
			 EST_GENEBUILDER_INTRON_MISMATCH => 10,

			 # you can bridge over small introns: we difuse the small intron into one exon
			 # if set to false transcripts with small introns will be rejected
			 BRIDGE_OVER_SMALL_INTRONS => 0,

			 # the maximum size of introns to bridge over
			 EST_MIN_INTRON_SIZE  => 20,
			 

			 # you can choose whether you only want tw ests/cdnas to merge if
			 # they have the same number of exons
			 EST_GENEBUILDER_EXON_MATCH     => 0,
  	    	    
			 # how much discontinuity we allow in the supporting evidence
			 # this might be correlated with the 2-to-1 merges, so we
			 # usually put it =  EST_GENEBUILDER_INTRON_MISMATCH for ESTs
			 EST_MAX_EVIDENCE_DISCONTINUITY  => 2,
			 REJECT_SINGLE_EXON_TRANSCRIPTS  => 1,
			 GENOMEWISE_SMELL                => 0,
			 
			 # exons smaller than this will not be included in the merging algorithm
			 EST_MIN_EXON_SIZE               => 20,

			 # ests with intron bigger than this will not be incuded either
			 EST_MAX_INTRON_SIZE             => 200000,
			 
			 # this says to ClusterMerge what's the minimum
			 # number of ESTs/cDNAs that must be 'included' into a
			 # final transcript
			 CLUSTERMERGE_MIN_EVIDENCE_NUMBER => 1,

			 # maximum number of transcripts allowed to 
			 # be in a gene. Even by tuning the other parameteres
			 # to keep this low, there will be always cases with more 20 even 50 isoforms
			 # which, unless what you're doing is really targetted
			 # to a known case or with very good quality ests/cdnas, it
			 # is not very reliable.
			 MAX_TRANSCRIPTS_PER_GENE => 100000,

			 # If using denormalised gene table, set this option to 1.
			 EST_USE_DENORM_GENES => 0,

			 

			 
	    # database config
	    # IMPORTANT: make sure that all databases involved in each analysis are
	    # not on the same mysql instance 
	    # database contention arises from having too many db conections open to the same database
            # if you have more than a couple of hundred jobs contacting the same database at the same 
            # time you will need multiple database but ifyou only have a few jobs you will probably be 
	    # able to get away with only 1 database.
	    
	    ############################################################
	    # ref_db - holds the static golden path, contig and dna information
	    ############################################################
	    
	    EST_REFDBNAME               => $LC_DBNAME,
	    EST_REFDBHOST               => $LC_DBHOST,
	    EST_REFDBPORT               => $LC_DBPORT,
	    EST_REFDBUSER               => $LC_DBro,
	    EST_REFDBPASS               => '',

	    # this is in general the database where we read the mapped ests/cdnas
	    # from, in order to use them for the EST_GeneBuilder
			 
	    EST_DBNAME                  => $LC_DBprefix."hum_cDNA",
	    EST_DBHOST                  => $LC_DBHOST,
	    EST_DBPORT                  => $LC_DBPORT,
	    EST_DBUSER                  => $LC_DBUSER,
	    EST_DBPASS                  => $LC_DBPASS,

	    # est_gene_db = where we write the genes we produce from e2g transcripts
	    EST_GENE_DBNAME                  => $LC_Dbprefix."hum_cDNAgene",
	    EST_GENE_DBHOST                  => $LC_DBHOST,
	    EST_GENE_DBPORT                  => $LC_DBPORT,
	    EST_GENE_DBUSER                  => $LC_DBUSER,
	    EST_GENE_DBPASS                  => $LC_DBPASS,
	    
	    # if you want to use ests together with cdnas in EST_GeneBuilder
	    # and your cdnas are in a SEPARATE DATABASE, you can specify it here:
	    USE_cDNA_DB                  => 0,  # set it to a def/undef value if you do/don't want to use it
	    
	    cDNA_DBNAME                  => '',
	    cDNA_DBHOST                  => '',
	    cDNA_DBPORT                  => '',
	    cDNA_DBUSER                  => '',
	    cDNA_DBPASS                  => '',
	    cDNA_GENETYPE                => '',	  

	   );

sub import {
    my ($callpack) = caller(0); # Name of the calling package
    my $pack = shift; # Need to move package off @_

    # Get list of variables supplied, or else
    # all of EST_GeneBuilder_Conf:
    my @vars = @_ ? @_ : keys( %EST_GeneBuilder_Conf );
    return unless @vars;

    # Predeclare global variables in calling package
    eval "package $callpack; use vars qw("
         . join(' ', map { '$'.$_ } @vars) . ")";
    die $@ if $@;


    foreach (@vars) {
	if ( defined $EST_GeneBuilder_Conf{ $_ } ) {
            no strict 'refs';
	    # Exporter does a similar job to the following
	    # statement, but for function names, not
	    # scalar variables:
	    *{"${callpack}::$_"} = \$EST_GeneBuilder_Conf{ $_ };
	} else {
	    die "Error: EST_GeneBuilder_Conf: $_ not known\n";
	}
    }
}

1;
