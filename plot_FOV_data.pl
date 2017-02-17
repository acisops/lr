#! /bin/env perl
#--------------------------------------------------------------------
# plot_FOV_data
# pull out the pad time and the AE-8 exits from the CRM file
# and put them in an idl data file
#--------------------------------------------------------------------
use Getopt::Std;
use Getopt::Long;
die "\n USAGE: $0 <load info WITH VERSION> -t [test directory]\n" if @ARGV < 1;

$LOAD=@ARGV[0];

$version=substr($LOAD, 7, 1);
$version=~tr/A-Z/a-z/;
$LOAD = substr($LOAD, 0, 7);
$year=substr($LOAD,5,2);


$appx = `lr_suffix.pl`;
GetOptions('t=s' => \$test_dir); #test directory name
if($test_dir){
    $DIR=$test_dir;
    $DATADIR=$DIR;
    print "Test dir= $DIR\n";    
}
else{
    $year=substr($LOAD,5,2);
    $DIR= </data/acis${appx}/LoadReviews/20${year}/$LOAD/ofls${version}>;
    $DATADIR=</data/acis${appx}/LoadReviews/20${year}/$LOAD/ofls${version}>;
}
$perfile=<${DIR}/ACIS-LoadReview.txt>;
$idl_dir=</data/acis${appx}/LoadReviews/script/pros/>;


$CRMfile=`ls ${DIR}/*CRM*.txt`;
$outfile="$DATADIR/perigee_times.pro";
unless(-e $outfile){
    @crm_array=();
    $min_day=0;
    $max_day=0;
    $temp=2000+$year;
    read_CRM_file($CRMfile,\@crm_array);
    read_days($perfile,$temp);

    write_output($outfile,@crm_array);
}
$version=~tr/a-z/A-Z/;


if($test_dir){
    $LV="\'${LOAD}${version}\', test_dir=\'${DIR}\'";
}else{
    $LV="\'${LOAD}${version}\'";
}

execute_plots($LV);
exit;


#--------------------------------------------------------------------
#--------------------------------------------------------------------
sub read_CRM_file{
    #print @_;
    my($filename,$crm_list)= @_;
    open (CRMPAD, "$filename") || warn "Warning! Cannot open CRM $filename!";
    my $si_mode='';
    %list=();

    while (<CRMPAD>)
    {
	$_=trim($_);
	#SET UP COLUMNS FIRST
	if($_ =~ /EVENT/){	
	    my @row = split (/\s{2,15}/, $_);
	    @keys=@row;

	}
	else{
	    if($_ =~ /^X|^E/){	
		my %event_item=(());
		my %per_item=(());
		@line = split (/\s+/, $_);
		$size=@line;
		#assign based on keys
		for ($ii=0;$ii<$size;$ii++){
		    $list{$keys[$ii]}=$line[$ii];
		}
		
		foreach my $key ( keys %list ) {
		    if ($key =~ m/EVENT$/){
			$crm_event = $list{$key};
		    }
		    if($key =~ m/SI_MODE/){
		        $si_mode=$list{$key};
		    }
		    if($key =~ m/ABSOLUTE/){
			if($key =~ m/PERIGEE\)$/){
			    $per_time=$list{$key};
			    
			}
		        if ($key =~ m/adj/ || $key =~ /AE/){		       
			    $crm_rad_time=$list{$key};#ee/ex
				
			}
			else {
			    if($key =~ m/of Pad/){
				$pad_time=$list{$key};#crm
			    }else{
				if ($key =~ m/of/){
				    $crm_ae_time=$list{$key};#AE8
				}
			    }
			}
		    }
		}
		%event_item=(
			     event=>$crm_event,
			     ae8_time=>$crm_ae_time, #AE8 time in backstop
			     rad_time=>$crm_rad_time, #Radmon Disable
			     pad_time=>$pad_time      #time of pad edges
			     );
		push(@crm_array,\%event_item);

		%per_item=(
			     event=>"PERIGEE",
			     ae8_time=>$per_time,
			     rad_time=>0.0,
			     pad_time=>0.0);
	
		push(@crm_array,\%per_item);
		    $si_mode='';
	} #if
    }
} #while
#       DEBUG--Keep this commented for debugging purposes
#foreach $item (@crm_array){
#      print "Event=$$item{event} at $$item{ae8_time} with PAD time of $$item{pad_time}\n";
#  }
  close(CRMPAD);
}
#------------------------------------------------------------
#remove whitespace from front and back of a string
#------------------------------------------------------------
sub trim {
    my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}

#--------------------------------------------------------------------
#read_CRM_file: Read the CRM file and store the information in an
#               array of hashrefs...
#--------------------------------------------------------------------
sub read_days {
  my($filename,$year)= @_;

  $min_day=`grep $year: $filename |head -1| cut -f1 -d ' '`;
  chop($min_day);
  $max_day=`grep $year: $filename |tail -1| cut -f1 -d ' '`;
  chop($max_day);
  
}




#--------------------------------------------------------------------
#write_outfile:Create several arrays that can be read into IDL
#--------------------------------------------------------------------
sub write_output{
  my($filename,@crm_list)= @_;

  open (OUT, "> $filename") || warn "Warning! Cannot open  $filename !";
 
  my @ee_day;
  my @ee_hour;
  my @ee_min;
  my @ee_sec;
  my @ex_day;
  my @ex_hour;
  my @ex_min;
  my @ex_sec;
  my @crm_ee_day;
  my @crm_ee_hour;
  my @crm_ee_min;
  my @crm_ee_sec;
  my @crm_ex_day;
  my @crm_ex_hour;
  my @crm_ex_min;
  my @crm_ex_sec;
  my @per_day;
  my @per_hour;
  my @per_min;
  my @per_sec;
  my @ae8ee_day;
  my @ae8ee_hour;
  my @ae8ee_min;
  my @ae8ee_sec;
  my @ae8ex_day;
  my @ae8ex_hour;
  my @ae8ex_min;
  my @ae8ex_sec;

  my $min_doy;
  my $min_hour;
  my $min_min;
  my $min_sec;
  my $max_doy;
  my $max_hour;
  my $max_min;
  my $max_sec;
 

  @min_array=split(":",$min_day);
  @max_array=split(":",$max_day);
  
  $min_year=@min_array[0];
  $min_doy=@min_array[1];
  $min_hour=@min_array[2];
  $min_min=@min_array[3];
  $min_sec=@min_array[4];
# subtract 18 hours (0.75 days)
  $min_hour=$min_hour-18.0;
  if($min_hour < 0.0){
      $min_hour=$min_hour+24.0;
      $min_doy=$min_doy-1.0;
  }
  @min_array[2]=$min_hour;
  @min_array[1]=$min_doy;


  $max_year=@max_array[0];
  $max_doy=@max_array[1];
  $max_hour=@max_array[2];
  $max_min=@max_array[3];
  $max_sec=@max_array[4];
  #add 18 hours (0.75 days)
  $max_hour=$max_hour+18.0;
  if($max_hour > 23.0){
      $max_hour=$max_hour-24.0;
      $max_doy=$max_doy+1.0;
  }
  @max_array[2]=$max_hour;
  @max_array[1]=$max_doy;
  $max_day=join(':',@max_array);
  $min_day=join(':',@min_array);
  



  #need to add in the 18 hours
  $min_day_number=split_times($min_day);
  $max_day_number=split_times($max_day);
  
  
 # $orig_min_day=$min_day_number;
  my $last_per_time=$min_day_number;

  foreach $item (@crm_array){
      my @crm_pad_time=split(":",$$item{pad_time}); #CRM
      my @crm_ae8_time = split(":",$$item{ae8_time}); #AE8
      my @crm_rad_time = split(":",$$item{rad_time}); #EE/EX

#uncomment to get Jan on   
#      if(@crm_ae8_time[0]!= $min_year){
#         print "at @crm_ae8_time Min year=$min_year this time year=@crm_ae8_tim
#e[0]\n";
#         $min_day_number=0.00;
#      }


      if($$item{event} =~ /^EE/){
          if(split_times($$item{pad_time}) > $min_day_number &&
             split_times($$item{pad_time}) < $max_day_number){
              push(@crm_ee_day,@crm_pad_time[1]);
              push(@crm_ee_hour,@crm_pad_time[2]);
              push(@crm_ee_min,@crm_pad_time[3]);
              push(@crm_ee_sec,@crm_pad_time[4]);
              push(@ae8ee_day,@crm_ae8_time[1]);
              push(@ae8ee_hour,@crm_ae8_time[2]);
              push(@ae8ee_min,@crm_ae8_time[3]);
              push(@ae8ee_sec,@crm_ae8_time[4]);
              push(@ee_day,@crm_rad_time[1]);
              push(@ee_hour,@crm_rad_time[2]);
              push(@ee_min,@crm_rad_time[3]);
              push(@ee_sec,@crm_rad_time[4]);
          }
      }
      if($$item{event} =~ /^XE/){
          if(split_times($$item{ae8_time}) < $max_day_number &&
             split_times($$item{ae8_time}) > $min_day_number){
              push(@crm_ex_day,@crm_pad_time[1]);
              push(@crm_ex_hour,@crm_pad_time[2]);
              push(@crm_ex_min,@crm_pad_time[3]);
              push(@crm_ex_sec,@crm_pad_time[4]);
              push(@ae8ex_day,@crm_ae8_time[1]);
              push(@ae8ex_hour,@crm_ae8_time[2]);
              push(@ae8ex_min,@crm_ae8_time[3]);
              push(@ae8ex_sec,@crm_ae8_time[4]);
              push(@ex_day,@crm_rad_time[1]);
              push(@ex_hour,@crm_rad_time[2]);
              push(@ex_min,@crm_rad_time[3]);
              push(@ex_sec,@crm_rad_time[4]);   
          }
      }
      if($$item{event} =~ /^PER/){ 
          if(split_times($$item{ae8_time}) < $max_day_number &&
             split_times($$item{ae8_time}) > $min_day_number){
              if($last_per_time != split_times($$item{ae8_time})){
                  push(@per_day,@crm_ae8_time[1]);
                  push(@per_hour,@crm_ae8_time[2]);
                  push(@per_min,@crm_ae8_time[3]);
                  push(@per_sec,@crm_ae8_time[4]);
              }
              $last_per_time=split_times($$item{ae8_time});
             }
      }
  }
  
  
  $str_ee_day=join(",",@crm_ee_day);
  $str_ee_day="crm_ee_day=[${str_ee_day}]\n";
  $str_ee_hour=join(",",@crm_ee_hour);
  $str_ee_hour="crm_ee_hour=[${str_ee_hour}]\n";
  $str_ee_min=join(",",@crm_ee_min);
  $str_ee_min="crm_ee_min=[${str_ee_min}]\n";
  $str_ee_sec=join(",",@crm_ee_sec);
  $str_ee_sec="crm_ee_sec=[${str_ee_sec}]\n";


  print OUT  "$str_ee_day";
  print OUT "$str_ee_hour";
  print OUT "$str_ee_min";
  print OUT "$str_ee_sec";

  $str_ex_day=join(",",@crm_ex_day);
  $str_ex_day="crm_ex_day=[${str_ex_day}]\n";
  $str_ex_hour=join(",",@crm_ex_hour);
  $str_ex_hour="crm_ex_hour=[${str_ex_hour}]\n";
  $str_ex_min=join(",",@crm_ex_min);
  $str_ex_min="crm_ex_min=[${str_ex_min}]\n";
  $str_ex_sec=join(",",@crm_ex_sec);
  $str_ex_sec="crm_ex_sec=[${str_ex_sec}]\n";

  print OUT  "$str_ex_day";
  print OUT "$str_ex_hour";
  print OUT "$str_ex_min";
  print OUT "$str_ex_sec";


  $str_ee_day=join(",",@ee_day);
  $str_ee_day="ee_day=[${str_ee_day}]\n";
  $str_ee_hour=join(",",@ee_hour);
  $str_ee_hour="ee_hour=[${str_ee_hour}]\n";
  $str_ee_min=join(",",@ee_min);
  $str_ee_min="ee_min=[${str_ee_min}]\n";
  $str_ee_sec=join(",",@ee_sec);
  $str_ee_sec="ee_sec=[${str_ee_sec}]\n";


  print OUT "$str_ee_day";
  print OUT "$str_ee_hour";
  print OUT "$str_ee_min";
  print OUT "$str_ee_sec";

  $str_ex_day=join(",",@ex_day);
  $str_ex_day="ex_day=[${str_ex_day}]\n";
  $str_ex_hour=join(",",@ex_hour);
  $str_ex_hour="ex_hour=[${str_ex_hour}]\n";
  $str_ex_min=join(",",@ex_min);
  $str_ex_min="ex_min=[${str_ex_min}]\n";
  $str_ex_sec=join(",",@ex_sec);
  $str_ex_sec="ex_sec=[${str_ex_sec}]\n";

  print OUT  "$str_ex_day";
  print OUT "$str_ex_hour";
  print OUT "$str_ex_min";
  print OUT "$str_ex_sec";

 $str_per_day=join(",",@per_day);
  $str_per_day="per_day=[${str_per_day}]\n";
  $str_per_hour=join(",",@per_hour);
  $str_per_hour="per_hour=[${str_per_hour}]\n";
  $str_per_min=join(",",@per_min);
  $str_per_min="per_min=[${str_per_min}]\n";
  $str_per_sec=join(",",@per_sec);
  $str_per_sec="per_sec=[${str_per_sec}]\n";


  print OUT  "$str_per_day";
  print OUT "$str_per_hour";
  print OUT "$str_per_min";
  print OUT "$str_per_sec";

 
  $str_ae8ee_day=join(",",@ae8ee_day);
  $str_ae8ee_day="ae8ee_day=[${str_ae8ee_day}]\n";
  $str_ae8ee_hour=join(",",@ae8ee_hour);
  $str_ae8ee_hour="ae8ee_hour=[${str_ae8ee_hour}]\n";
  $str_ae8ee_min=join(",",@ae8ee_min);
  $str_ae8ee_min="ae8ee_min=[${str_ae8ee_min}]\n";
  $str_ae8ee_sec=join(",",@ae8ee_sec);
  $str_ae8ee_sec="ae8ee_sec=[${str_ae8ee_sec}]\n";


  print OUT  "$str_ae8ee_day";
  print OUT "$str_ae8ee_hour";
  print OUT "$str_ae8ee_min";
  print OUT "$str_ae8ee_sec";


 

  $str_ae8ex_day=join(",",@ae8ex_day);
  $str_ae8ex_day="ae8ex_day=[${str_ae8ex_day}]\n";
  $str_ae8ex_hour=join(",",@ae8ex_hour);
  $str_ae8ex_hour="ae8ex_hour=[${str_ae8ex_hour}]\n";
  $str_ae8ex_min=join(",",@ae8ex_min);
  $str_ae8ex_min="ae8ex_min=[${str_ae8ex_min}]\n";
  $str_ae8ex_sec=join(",",@ae8ex_sec);
  $str_ae8ex_sec="ae8ex_sec=[${str_ae8ex_sec}]\n";


  print OUT  "$str_ae8ex_day";
  print OUT "$str_ae8ex_hour";
  print OUT "$str_ae8ex_min";
  print OUT "$str_ae8ex_sec";

 
  close(OUT);

}

#------------------------------------------------------------
# Change a colon separated time to a day decimal
#------------------------------------------------------------
sub split_times{
    my($timeline)=@_;
    @times=split /:/, $timeline;
    @secs=split /\./, $times[5];
    $dec_day = $times[1] + $times[2]/24 + $times[3]/1440 + $times[4]/86400;
    
    return $dec_day;
}
#--------------------------------------------------------------------
# execute_plots: Create a temp batch file and run idl
#--------------------------------------------------------------------
sub execute_plots(){
#change this to a temp file
    my($cur_load)=@_;
    if(-e "$DIR/test_idl.pro"){
	unlink("$DIR/test_idl.pro");
    }
    open(FOOBAR, "> $DIR/test_idl.pro") || die "Can't open test_idl.pro";
    print FOOBAR ".comp $idl_dir/plot_angles.pro\n";
    print FOOBAR ".comp $idl_dir/read_angles.pro\n";
    print FOOBAR ".comp $idl_dir/timeconv.pro\n";
    print FOOBAR ".comp $idl_dir/plot_angles.pro\n";
    print FOOBAR "plot_angles, ${cur_load} \n";
    print FOOBAR "exit\n";
    close FOOBAR;
    print "Executing IDL plots\n";
    $idlprog=</usr/local/bin/idl>;
    open (IDL, "|$idlprog") or die "Can't access $idlprog\n";
    print IDL "\@$DIR/test_idl.pro";
    close IDL;
    
    unlink("$DIR/test_idl.pro");
}
