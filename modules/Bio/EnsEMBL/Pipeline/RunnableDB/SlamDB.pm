
=pod

=head1 NAME

Bio::EnsEMBL::Pipeline::RunnableDB::SlamDB

=head1 SYNOPSIS

  get a Bio::EnsEMBL::Pipeline::RunnableDB::SlamDB object:

  $obj = new Bio::EnsEMBL::Pipeline::RunnableDB::SlamDB (
                                                    -dbobj      => $db,
			                            -input_id   => $input_id
                                                    -analysis   => $analysis
                                                       );

  $slamdb->fetch_input();
  $slamdb->run();
  $slamdb->output();
  $slamdb->write_output();

=head1 DESCRIPTION

 This object wraps Bio::EnsEMBL::Pipeline::Runnable::Slam (and uses also Avid and ApproxAlign)
 to add functionality to read and write to databases.
 A Bio::EnsEMBL::Pipeline::DBSQL::Obj is required for databse access.

=head1 CONTACT

ensembl-dev@ebi.ac.uk

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut


=head1 CONTACT

Post general queries to B<ensembl-dev@ebi.ac.uk>

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Pipeline::RunnableDB::SlamDB;

use strict;
use Bio::EnsEMBL::Pipeline::RunnableDB;
use Bio::EnsEMBL::Pipeline::SeqFetcher;
use Bio::EnsEMBL::Pipeline::RunnableI;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::DB::RandomAccessI;
use Bio::EnsEMBL::Pipeline::Runnable::Avid;
use Bio::EnsEMBL::Pipeline::Runnable::Slam;
use Bio::EnsEMBL::Pipeline::Tools::ApproxAlign;

# vars read from Slamconf-File
use Bio::EnsEMBL::Pipeline::Config::GeneBuild::Slamconf qw (
                                                            SLAM_ORG1_NAME
                                                            SLAM_ORG2_NAME
                                                            SLAM_BIN
                                                            SLAM_PARS_DIR
                                                            SLAM_MAX_MEMORY_SIZE
                                                            SLAM_MINLENGTH
                                                            SLAM_MAXLENGTH
                                                            SLAM_COMP_DB_USER
                                                            SLAM_COMP_DB_PASS
                                                            SLAM_COMP_DB_NAME
                                                            SLAM_COMP_DB_HOST
                                                            SLAM_COMP_DB_PORT
                                                            SLAM_ORG2_RESULT_DB_USER
                                                            SLAM_ORG2_RESULT_DB_PASS
                                                            SLAM_ORG2_RESULT_DB_NAME
                                                            SLAM_ORG2_RESULT_DB_HOST
                                                            SLAM_ORG2_RESULT_DB_PORT
                                                           );

use vars qw(@ISA);
@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableDB);

############################################################

sub new {
  my ($class, @args) = @_;

  my $self = {};
  bless $self, $class;
  my ($db, $input_id, $seqfetcher, $analysis) = $self->_rearrange([qw(
                                                                      DB
                                                                      INPUT_ID
                                                                      SEQFETCHER
                                                                      ANALYSIS )],
                                                                  @args);

  &throw("No database handle input for first organsim\n") unless defined($db);
  &throw("No analysis object input") unless defined($analysis);
  $self->analysis($analysis);
  $self->regions($input_id);

  $self->db($db);               #super db() from runnableDB -->needs a DBConnection-Object
  $self->db_org2;
  $self->verbose("1");

  return $self;
}


sub run{
  my ($self) = shift;

  my @subslices;
  my %alltranscripts;
  ####################### IF SEQLENGTH > SLAM_MAXLENGTH WE SPLIT #############################

  if ( (${$self->slices}[0]->length  || ${$self->slices}[0]->length ) > $SLAM_MAXLENGTH) {
    # run avid to cut seqs

    my $avid = $self->runavid( $self->slices);
    print "SlamDB.pm: ".$avid->fasta_filename1."\t".$avid->fasta_filename2."\n" if $self->verbose;

    my $approx_obj = $self->approx_align( $avid->parsed_binary_filename, $avid->fasta_filename1, $avid->fasta_filename2 );


    # cut the first seq according to the positions of the repeats
    # and than try to find equal positions in the second seq by
    # using the aat-file

    my @cuts = @{ $self->calculate_cutting ( $approx_obj ) } ;

    print "SlamDB.pm: CALCULATED CUTTING using the repeats out of db:\n"  if $self->verbose;;

    for (@cuts) {               # contains the 4 offsets for cutting 1 290.000 1 299.000
      my @cut_offset = @$_;
      my $start1 = $cut_offset[0];
      my $end1 = $cut_offset[1];
      my $length1 = $end1 - $start1;
      my $start2 = $cut_offset[2];
      my $end2 = $cut_offset[3];
      my $length2 =$end2 - $start2;
      print "$start1\t$end1\t=$length1\t\t" . "$start2\t$end2\t=$length2\n"  if $self->verbose;
    }
    print "\n\n"  if $self->verbose;

    #  perl test_slam_cutting.pl /tmp/fasta1.fasta /tmp/fasta2.fasta /tmp/aatfile.aat /tmp/rempeatmsk.out 

    # we got the cutting positions in @cuts, we build & store the subslices in @subslices
    # @cuts is an array of arrays [ [start1,end1,start2,end2],[start1,end1,start2,end2] ]

    for my $subseqs (@cuts) {

      # store the subslices in 2nd array of arrays
      my ($start1, $end1) = @{$subseqs}[0,1];
      my ($start2, $end2) = @{$subseqs}[2,3];


      # calculation for allowing bigger slices

      my $diff1 = $end1-$start1;
      my $diff2 = $end2-$start2;


      my $allow_oversize = 50000;

      if (     (($diff1-$SLAM_MAXLENGTH)>$allow_oversize) && (($diff2-$SLAM_MAXLENGTH)>$allow_oversize)) {
        print "NOT OK. We have too large slices\n";


        # region is bigger than SLAM_MAXLENGTH ---> we need to re-cut !!!

        my $lseq1 = $end2-$start2; my $lseq2 = $end1-$start1;
        my $subslice1 = ${$self->slices}[0] -> sub_Slice( $start1, $end1 );
        my $subslice2 = ${$self->slices}[1] -> sub_Slice( $start2, $end2 );

        # construct input-id for re-analysis

        my $e1_start = $subslice1->start;    my $e1_end = $subslice1->end;    my $e1_chr = $subslice1->seq_region_name;
        my $e2_start = $subslice2->start;    my $e2_end = $subslice2->end;    my $e2_chr = $subslice2->seq_region_name;
        print "LOG: region >> slam_max_size ( $SLAM_MAXLENGTH bp) .. SKIPPING REGION:\t " ;
        print "$e1_chr-$e1_start-$e1_end---$e2_chr-$e2_start-$e2_end\n" ;
        print "The region has to be re-calculated\n";
      }else{
        # region fits, so let's get subslices and store them
        my $subslice1 = ${$self->slices}[0] -> sub_Slice( $start1, $end1 );
        my $subslice2 = ${$self->slices}[1] -> sub_Slice( $start2, $end2 );
        push @subslices, [$subslice1,$subslice2];
      }
    }
  } else {
    # no cutting
    push @subslices, $self->slices;
  }

##################### SEQUENCE IS SPLITTED IN SUBSICES, NOW RUN ANALYSIS ! ##############################

  $alltranscripts{$SLAM_ORG1_NAME} = ();
  $alltranscripts{$SLAM_ORG2_NAME} = ();

  ####################### RUN AVID APPROXALIGN and SLAM on each SUBSLICE #############################
  my $slice_counter=0;


  for my $slices (@subslices) {
    $slice_counter++;
    print "\nSlamDB.pm: Subslice-Nr: $slice_counter\n-------------------------------\n"  if $self->verbose;

    ################################ REPEATMASK-STATISTICS ################################

    my $subslice1 = ${$slices}[0] ;
    my $subslice2 = ${$slices}[1] ;

    my $length1 =    $subslice1->length;
    my $unknown1 = ( $subslice1->seq() ) =~tr/N//; # count all occurences of N in the sequence
    my $maskedNs1 =( $subslice1->get_repeatmasked_seq->seq()) =~tr/N//;
    $maskedNs1 = $maskedNs1-$unknown1;


    my $length2 =    $subslice2->length;
    my $unknown2 = ( $subslice2->seq() ) =~tr/N//;
    my $maskedNs2 = ($subslice2->get_repeatmasked_seq->seq() ) =~tr/N//;
    $maskedNs2 = $maskedNs2-$unknown2;

    print "SlamDB.pm: Length 1st subslice " . $length1 ."\t Length 2st subslice " . $length2 ."\n" if $self->verbose;;

    my $rmlength1 = $length1-($unknown1);
    my $rmlength2 = $length2-($unknown2);


#    my $percentage1 = sprintf ( "Percentage of repeats in 1st seq: %1.2f" , (($maskedNs1/$rmlength1)*100) ) ; print $percentage1."%\n";
#    my $percentage2 = sprintf ( "Percentage of repeats in 2nd seq: %1.2f" , (($maskedNs2/$rmlength2)*100) ) ; print $percentage2."%\n";



    ################################### RUNNING AVID ON SUBSLICE ########################################


    print "SlamDB.pm: Running Avid...\n"  if $self->verbose;;

    my $avid_obj = $self->runavid( $slices );

    print "SlamDB.pm: running ApproxAlign\n"    if $self->verbose;;
    my $approx = $self->approx_align( $avid_obj->parsed_binary_filename, $avid_obj->fasta_filename1, $avid_obj->fasta_filename2 );


    my $e1_start = $subslice1->start;    my $e1_end = $subslice1->end;    my $e1_chr = $subslice1->seq_region_name;
    my $e2_start = $subslice2->start;    my $e2_end = $subslice2->end;    my $e2_chr = $subslice2->seq_region_name;

    print "   Region1NEW: $e1_chr-$e1_start-$e1_end \n   Region2NEW: $e2_chr-$e2_start-$e2_end\n"  if $self->verbose;;

    # make new slam-run with subslice
    my $slamobj = new Bio::EnsEMBL::Pipeline::Runnable::Slam (
                                                              -slice1        =>  $subslice1 ,
                                                              -slice2        =>  $subslice2 ,
                                                              -fasta1        => $avid_obj->fasta_filename1 ,
                                                              -fasta2        => $avid_obj->fasta_filename2 ,
                                                              -approx_align  => $approx->aatfile ,
                                                              -org1          => $SLAM_ORG1_NAME ,
                                                              -org2          => $SLAM_ORG2_NAME ,
                                                              -slam_bin      => $SLAM_BIN ,
                                                              -slam_pars_dir => $SLAM_PARS_DIR ,
                                                              -max_memory    => $SLAM_MAX_MEMORY_SIZE,
                                                              -minlength     => $SLAM_MINLENGTH ,
                                                              -debug         => 0 ,
                                                              -verbose       => 0
                                                             );

    # run slam, parse results and set predict. trscpts for both organisms
    print "SlamDB.pm: running Slam\n" if $self->verbose;
    $slamobj->run;

    #    # getting reference to array of predicted transcripts  [ ref[arefhumanpt] ref[arefmousept] ]
    my $predtrans = $slamobj ->predtrans; # predtrans = [HPT HPT HPT][HM HM HM] or 2 empty arrays [ [] [] ]

    #    # testing the length of the predicted transcr
    my @tmp_arrayrefs = @{$predtrans};

    my $aref1 = $tmp_arrayrefs[0];
    my $aref2 = $tmp_arrayrefs[1];

    my @array1 = @{$aref1};
    my @array2 = @{$aref1};

    if (scalar (@array1) >0) {
      # only store defined values
      push (@{$alltranscripts{$SLAM_ORG1_NAME}}, $aref1 ); # [HPT]
    }

    if (scalar (@array2) >0) {
      push (@{$alltranscripts{$SLAM_ORG2_NAME}}, $aref2 ); # [MUS]
    }
  }


  # lets check the length of the two stored arrays
  #  print "checking if storage worked\n";   #debug
  #  foreach my $key(keys    %alltranscripts) {
  #    my $stored_arrayref = $alltranscripts{$key};
  #    my @stor_array = @{$stored_arrayref};
  #    for my $item (@stor_array){
  #      my @refs2pt = @{$item};
  #      for my $defpt (@refs2pt){
  #      }
  #    }
  #  }
  $self->predtrans_both_org (\%alltranscripts);
}



################################################################################
# checks if the array ref is defined and stores it if necessary in db
sub write_dbresults {
  my ($self,$db,$slice,$org,$apt,$analysis) = @_;

  my $pred_adp = $db->get_PredictionTranscriptAdaptor;
  my %allpredtrans = %$apt;

  # the refrence-"cascade":
  # step 1: get predictionTranscript $pT  and add exons to it                                : $pT = MY_TRANSCRIPT
  # step 2: store all predicted Transcripts $pt in an array @prediTrans                      : @prediTrans               = (pt1 pt2 pt3)
  # step 3: set refrence $ary_ref_prediTrans to the array @predicted_transcripts             : $aref_prediTrans          = \@prediTrans
  # step 4: add the reference to an array of all predicted transcripts @all_aref_prediTrans  : @all_aref_prediTrans      = ($aref_prediTrans, $aref_prediTrans $aref_prediTrans)
  # step 5  store reference $aref_allprediTrans to array @allprediTrans                      : $aref_all_aref_prediTrans = \@all_aref_prediTrans
  # step 6: store the refrence to the array $are_all_aref_prediTrans in a hash (key:organismname)      : $allpredtrans{'H.sapiens'} = $aref_all_aref_allprediTrans

  my $aref_all_aref_prediTrans = $allpredtrans{$org};

  # test if there are any prediction transcripts defined (if so, put'em in db)
  if (defined $allpredtrans{$org}) {

    my @all_aref_prediTrans = @{ $aref_all_aref_prediTrans}; 
    foreach my $aref_prediTrans (@all_aref_prediTrans) {
      my @prediTrans = @{$aref_prediTrans} ;
      for my $pT (@prediTrans) {
        # here are the prediction transcripts we like to process
        $pT->analysis($analysis);
      }
      $pred_adp->store(@prediTrans);
    }
  }
}



# POSSIBILITES :
# compare repeats of first seq in db with repeats after RM-run
# transfer db-repeats in RM-outfile for first seq 
# or 
# transfer RM-outfile-repeats in array which is used by this script (format START - END)
#
# cut the sequence in diffrent parts --- but do we have to to it ? what are the needs for it ?
# Which programs are working with it ?
# Which programs need to read the files, which get slices ?
# Why is the RM done ? (logic in slam.pl)
# AND WHAT ABOUT THE COORDINATES ???  ->no prob, 'cause ya using slices!

# make cuts according to position of repeats in first sequence
#   FORMAT OF AN AAT-FILE
# output-format of aat-file (one row for each base, slam needs the same input)
#   base lowerBound upperBound
#   0        0          881
#   1        2          882
#   2        843        883
#   3        843        884
#   4        849        885
#   5        850        886
#   6        851        887
#   7        852        888
#   8        853        889
#   9        856        898

sub calculate_cutting{
  my ($self,$ApproxAlign) = @_;

  # getting attributes of object
  my @slices  = @{$self->slices};

  my @all_repeats = @{$self->get_repeat_features};

  my $len1 = $slices[0]->length;

  print "MaxLen : $SLAM_MAXLENGTH\n" ; #  if $self->verbose;

  my @cuts1 = (1);
  my $targetcut = $SLAM_MAXLENGTH;
  while ($targetcut < $len1) {
    my $cut = undef;
    while (1) {
      # $all_repeats[0]->[0] = start of repeat
      # $all_repeats[0]->[1] = end of repeat

      if ((@all_repeats==0) || ($all_repeats[0]->[0] > $targetcut)) {

        # No repeats or startpos of first repeat is bigger than targetcut, there are no repeats before target-cuttingposition, so cut
        last;

      } elsif ($all_repeats[0]->[1] >= $targetcut) {
        # end of repeat is "bigger" than targetcut (repeat spans target, cool, see example1 above)
        $cut = $targetcut;
        last;

      } else {
        # Store end of repeat as the best-yet value, then move on.
        $cut = $all_repeats[0]->[1];
        shift(@all_repeats);
      }
    }

    if ( (!defined($cut)) || (($targetcut-$cut+1) > ($SLAM_MAXLENGTH/2)) ) {
      # If no repeats before targetcut or cut too far away, then cut at target anyway
      $cut = $targetcut;
    }
    push(@cuts1,$cut);
    $targetcut = $cut + $SLAM_MAXLENGTH;
  }                             # while(1)

  # last cut is length of seq
  # now we got cutting-positions for the first sequence

  push(@cuts1,$len1) if($cuts1[$#cuts1] < $len1);


  ################################################################################
  # Make array of matching cuts in other sequence using the approximate alignment
  #
  # what is the lower bound for the first cut ? What generally is a lowerBound ?
  # get first cut for second sequence

  my @cuts2 = (1+$ApproxAlign->lowerBound($cuts1[0]-1));

  for (my $i=1; $i < (scalar(@cuts1)-1); $i++) {
    push(@cuts2,sprintf("%d",($ApproxAlign->lowerBound($cuts1[$i]-1) + $ApproxAlign->upperBound($cuts1[$i]-1))/2.0));
  }

  push(@cuts2,(1+$ApproxAlign->upperBound($cuts1[$#cuts1]-1)));

  my @splits = ();              # nr of cuts
  $cuts1[0] = $cuts1[0]-1;
  $cuts2[0] = $cuts2[0]-1;

  for (my $i=0; $i < (scalar(@cuts1)-1); $i++) {
    if ($cuts2[$i]+1 > $cuts2[$i+1]) {
      # skip if we have an insertion in the base seqeunce.
      next;
    } else {
      # cuts in the first seq     cuts in the second seq
      push(@splits,[ $cuts1[$i]+1, $cuts1[$i+1], $cuts2[$i]+1, $cuts2[$i+1] ] );

      ##      print "cut1: $cuts1[$i]+1 \tcut2: $cuts1[$i+1]\tcut1b: $cuts2[$i]+1\tcut2b: $cuts2[$i+1]\n";


      # Format of cutfile:
      # human_contig.fasta_mice_contig.fasta.cut.1      1       100500  1       93943
      # human_contig.fasta_mice_contig.fasta.cut.2      100501  119071  93944   100090
    }
  }
  return(\@splits);
}




# gets a reference to an array of slices to run avid on, and returns a reference to an avid-object

sub runavid{
  my ($self,$sliceref) = @_;

  my $avid =  new Bio::EnsEMBL::Pipeline::Runnable::Avid (
                                                          -slice1      => ${$sliceref}[0],
                                                          -slice2      => ${$sliceref}[1],
                                                         );

  $avid->run;
  return $avid;
}


# gets name of parsed binary and fastanames
# returns name of written modified approximate alignment
sub approx_align{
  my ($self, $parsed_bin,$fasta1,$fasta2) = @_;

  my $approx_obj = new Bio::EnsEMBL::Pipeline::Tools::ApproxAlign(
                                                                  -aat =>  $parsed_bin, # /path/to/parsedbinaryfile
                                                                  -seqY => $fasta1, # /path/to/firstfasta.fasta
                                                                  -seqZ => $fasta2 # /path/to/secondfasta.fasta
                                                                 );
  $approx_obj->expand( $approx_obj->exonbounds );
  $approx_obj->makeConsistent();

  if ($approx_obj->isConsistent) {
    $approx_obj->write();       #write aatfile ($approx_obj->aatfile)
  } else {
    die "Error: final aat is not consistent (shouldn't have happened).\n"
  }
  return $approx_obj;
}




############################################################
# method is called by runSlamDB.pl / testRunnable.pl

sub fetch_input {
  my $self = shift;
  $self->slices([$self->db,$self->db_org2]);
}


# fetching slices for each org out of specified db

############################################################


sub slices{
  my ($self ,$db) = @_;

  if ($db) {
    my @slices;
    my @coords = @{$self->regions};
    for (my $i=0;$i<=1;$i++) {
      my $sa = ${$db}[$i]->get_SliceAdaptor();
      print "fetching slice $coords[$i]\n";
      my $slice = $sa->fetch_by_name($coords[$i]);
      push @slices, $slice;
    }
    $self->{_slices}=\@slices;
  }
  return $self->{_slices};
}

# splits input-id and sets the diffrent regions
sub regions {
  my ($self,$input_id) = @_;

  if (defined $input_id) {

    ### NEW FORMAT: chromosome:NCBI35:1:1:245442847:1---chromosome:NCBI35:1:1:245442847:-1

    my @input = split /---/,$input_id;
   $self->{_regions}=\@input;
  }
  return $self->{_regions};
}


############################################################

=head2 db_org2

    Title   :   db_org2
    Usage   :   $self->db_org2($obj);
    Function:   Gets or sets the value of db_org2
    Returns :   A Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor org2liant object
                (which extends Bio::EnsEMBL::DBSQL::DBAdaptor)
    Args    :   A Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor compliant object

=cut

sub db_org2 {
  my( $self) = shift;

  # data of db for writing results of second organism analysis (out of Conf/Genebuild/Slamconf.pm)

  my  $db_result_org2 = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
                                                            -user   => $SLAM_ORG2_RESULT_DB_USER,
                                                            -dbname => $SLAM_ORG2_RESULT_DB_NAME,
                                                            -host   => $SLAM_ORG2_RESULT_DB_HOST,
                                                            -pass   => $SLAM_ORG2_RESULT_DB_PASS,
                                                            -port   => $SLAM_ORG2_RESULT_DB_PORT,
                                                            -driver => 'mysql'
                                                           );

  # attaching dna-db for data retreival

  my  $dnadb = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
                                                   -user   => $SLAM_COMP_DB_USER,
                                                   -dbname => $SLAM_COMP_DB_NAME,
                                                   -host   => $SLAM_COMP_DB_HOST,
                                                   -pass   => $SLAM_COMP_DB_PASS,
                                                   -port   => $SLAM_COMP_DB_PORT,
                                                   -driver => 'mysql'
                                                  );
  $db_result_org2 -> dnadb($dnadb);
  $self->{'_db_org2'} = $db_result_org2;

  return $self->{'_db_org2'};
}


=head2 predtrans_both_org

  Title    : predtrans
  Usage    : $obj->predtrans
  Function : Sets/gets a hash of predicted transcripts for both organismas (key=species)
  Returns  : Ref. to an hash (keys: org1 org2) with 2 arrays of predicted transcripts
  Args     : References to a hash || none

=cut

sub predtrans_both_org{
  my ($self,$ref_predtrans) = @_;

  if ($ref_predtrans) {
    $self->{_ref_predtrans} = $ref_predtrans;
  }
  return $self->{_ref_predtrans};
}


sub write_output {
  my ($self) = @_;
  #writing output for both organisms to different databases
  $self->write_dbresults ( $self->db,      ${$self->slices}[0], $SLAM_ORG1_NAME , $self->predtrans_both_org, $self->analysis );
  $self->write_dbresults ( $self->db_org2, ${$self->slices}[1], $SLAM_ORG2_NAME , $self->predtrans_both_org, $self->analysis );
}



# writing the results to the given database (mouse/human/rat)
# gets a database to write to, a slice and a reference to an array of predicted transcripts
# looks up for the analysis




#                           REPEATS AND SPLITTING
# get the start/end-positions of repeats in the FIRST sequence (LTRs, LINEs and SINEs)
# out of the db and look for a good place to cut. Good positions are if the expexted
# cuttingposition (which is the max. length of seqslice to compare) lies in a region 
# with repeats (ex1)
# or
#
# ex1:  ..._repeat_repeat_repeat_CUTTINGPOSITION_repeat_repeat_repeat_...
#
# ex2:  ..._
#
# gets the repeat features for the first slice and returns a reference to an array with
# repeat-features

sub get_repeat_features {
  my $self = shift;

  my @slices = @{$self->slices};
  my $slice = $slices[0];

  my (@all_rpt);
  # repeat-types to look for
  my @repeats =('LTRs','Type I Transposons/LINE','Type I Transposons/SINE');
  my @all;

  # get all repeats of the given types (above) and write them in @array
  for my $arpt (@repeats) {
    for my $rpt ( @{$slice->get_all_RepeatFeatures(undef,"$arpt")}) {

      my $rpt_start = $rpt->start;
      my $rpt_end = $rpt->end;

      push (@all_rpt , [ $rpt_start , $rpt_end ] );
      push (@all , [ $rpt_start , $rpt_end , $rpt->display_id] );
    }
  }

  # sort startpos of rpt ascending order
  @all_rpt = sort { $a->[0] <=> $b->[0] } @all_rpt;

#  my $repeatfilename = "/tmp/db_repeats.out";
#  print "Writing $repeatfilename\n";
#  open(RP,">$repeatfilename") || die "write error $repeatfilename\n";
#  for my $r (@all_rpt) {
#    my @r=@{$r};
#    for (@r) {
#      print RP "\t $_";
#    }
#    print RP "\n";
#  }
#  close(RP);

  return \@all_rpt;
}

sub verbose{
  my ($self,$verbose) = @_;

  $self->{_verbose} = '0' if (!defined $verbose && !defined $self->{_verbose});
  $self->{_verbose} = $verbose if (defined $verbose);
  return $self->{_verbose};
}
