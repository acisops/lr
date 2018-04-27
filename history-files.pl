#!/usr/bin/env perl

#This script is designed to automate the history file update 
# process that must be done in the event of an SCS107 safing, 
# or TOO interrupt. 

#written by:  Joe DePasquale
#started:     03 April 2002
#see version 1 for previous history
#
# Update:  March 8, 2016
#          Gregg Germain
#          Commented where GetFluMon can be found
#            - acis60-v
#            - acisocc-v
#            - aciscdp-v
#
# Update:  Dec 1, 2016
#          Gregg Germain
#          V2.15
#          - Modified the scp commands moving things to acis60-v,
#            acisocc-v and aciscdp-v to include the "acisweb" 
#            user name.
#          - Added more much-needed comment lines
#          - "die" clause added to GetOpt
#
# Update:  June 28, 2017
#          Gregg Germain
#          V2.16
#          - Added code to write out entries into the Non-Load Event
#            Tracker file
#          - changed $dir_shanil to $ops_dir
#          - Subroutine latest_time modified to return the
#            time in DOY format as well as the original Status
#            string. This is for MANEUVER labeling in the Non-Load
#            event tracking file.
#          - Added more much-needed comment lines
#          - The dollar sign has been missing on the s107 choice
#            since October 2013
# 
# Update:  October 6, 2017
#          Gregg Germain
#          V2.17
#          - Added query to user regarding the type of Full Stop
#            whether it's an NSM or a BSH.
#          - If NSM, asks for Quaternions and makes entry into the
#            NLET file
####################################################################
#COFT=COMMENTED OUT FOR TESTING
#--------------------------------------------------------------------
#modules used
#--------------------------------------------------------------------
use Fcntl qw(:DEFAULT :flock);
use File::Copy;
use Getopt::Std;
use Getopt::Long;

# MachinePath located in: /data/acis/LoadReviews/script/lib/
# Current routines: GetPathandNode([host])
#                   GetFluMon([host])
#                   GetRTpath([host])
#                   GetPMONpath([host])
#                   GetWebPath([host])
use MachinePath(); #code to find the right directory

#--------------------
# Check user - the user MUST be acisdude. However this can cause problems
#              further on when it's time to copy the history files to some
#              of the V machines (aci60-v, aciscdp-v acisocc-v)
#--------------------
$acisdude_uid=getpwnam "acisdude";
#print " ACISDUDE= $acisdude_uid. Current UID = $<\n";
##COFT
$acisdude_uid == $< or die "Error: Must be logged in as acisdude\n";

#----------------------------------------
#Main variables
#----------------------------------------
#directory definitions
#$ops_dir = </proj/sot/acis/FLU-MON>;
$isBackup = 0;
#--------------------
# directory definitions
#--------------------
#
# lr_suffix.pl tells history-files whether this is running on the 
# backup system or the main system.
$appx = `lr_suffix.pl`;   #  Null or "_bak"
if ($appx)
  {
    $isBackup = 1;
    $base_dir = "/data/acis-bak";
  } 
else
  {
    $isBackup = 0;
    $base_dir = '/data/acis';
  }

# Locate the path of the top of the fluence monitor directory
# path based on the host.
$xcanuck_flu=GetFluMon('xcanuck');

$acis60_v_flu=GetFluMon('acis60-v');
$han_v_flu=GetFluMon('han-v');

$colossus_v_flu=GetFluMon('colossus-v');
$acisocc_v_flu=GetFluMon('acisocc-v');

$aciscdp_v_flu=GetFluMon('aciscdp-v');
$luke_v_flu=GetFluMon('luke-v');

# If this is a backup run then the FLU-MON directory
# is on colossus-v and is /export/acis-flight/FLU-MON/
if ($isBackup)
   {
    $ops_dir = $colossus_v_flu;
   }
 else
   # Otherwise its on xcanuck ???? and is /proj/sot/acis/FLU-MON/
   {
    $ops_dir="${xcanuck_flu}";
   }

# Formulate the path to the ACE-update.pl script (main ops)
# If this is a backup run the file is ACE-update_bak.pl
$ACE_UPDATE="$base_dir/LoadReviews/script/ACE-update$appx.pl";
$choice='x';
#--------------------
# command line options
#--------------------
# New replan loads have been created and approved
$go=0;

# Maneuver load has been created and approved and you need to update the history files 
$man=0;
$test=0;
$satest = "";
$help=0;
@status_array=();
@stoparr=();
@s107arr=();
@tooarr=();
#--------------------
# GLOBALS
#--------------------
$fp_inst = "";
$hetg = "";
$letg = "";
$obsid = "";
$radmon = "";
$format = "";
$dither = "";
@history_files = ("FPHIST-2001", "GRATHIST-2001", "OBSHIST","TLMHIST", 
		  "TSCHIST","DITHHIST");
@obs_hist_files=("FPHIST-2001", "GRATHIST-2001", "OBSHIST", "TSCHIST");
$stop_all="9999:999:99:99:99.999";	
%SIMPOS=("ACIS-S","75624",
	 "ACIS-I","92904",
	 "HRC-S","-99616",
	 "HRC-I","-50504");

$man_doy_last_time = "";
#--------------------------------------------------------------------
#options
#--------------------------------------------------------------------
$callstr="@ARGV\n";
$sa_testdir = "";

#Adding proper argument collection with GetOpt die if the option is illegal
GetOptions ('help|h',\$help,
	    'test',\$test,
	    'satest=s', \$sa_testdir,  # Standalone (not regression) test
	    'go',\$go,
	    'man',\$man,
	    'stop=s{2}',\@stoparr,
	    's107=s{2}',\@s107arr,
	    'too=s{2}',\@tooarr)

         or die "Error: unrecognized command line option - EXITING WITHOUT FURTHER PROCESSING.\n";

#----------------------------------------
# Process Options input
#----------------------------------------
if($help){&print_help; exit(-1);}
if($go){$choice='go';}
if($man){$choice='man';}
if(@stoparr >0){$choice='stop';@status_array=@stoparr;}
if(@s107arr > 0){$choice='s107';@status_array=@s107arr;}
if(@tooarr >0){$choice='too';@status_array=@tooarr;}

#ERROR CHECK for failure to set an option
if($choice =~ /x/)
  {print "ERROR: No acceptable options provided\n";exit(-1)};

if($test || $sa_testdir)
  {
    &set_test_env();
  }

if(@status_array)
  { &validate_input(@status_array); }


#===============================================================================
#                             START OF MAIN CODE
#===============================================================================
if($choice eq "man")
  {
    # Collect the latest non-9999 time in the History files plus whatever info
    # in the status array in the selected file.  The time has already been 
    # decimalized.
    #
    ($man_doy_last_time, @status_array)=latest_time(@obs_hist_files);
  }

#--------------------------------------------------------------------
#If updating for a maneuver or replan load, first run ACE-update.pl 
#to append the most recent history information, then deal with the 9999 line.
#--------------------------------------------------------------------  
if ($choice eq "man" || $choice eq "go")
  {
    print "\nRunning ACE-update$appx.pl to first update history files...";
    print "\n    the command line is: $ACE_UPDATE\n";
    system ("$ACE_UPDATE") == 0 || die "$ACE_UPDATE failed to execute properly\n";
  }

#--------------------------------------------------------------------
# Change to the mission history directory
# Make copies of the files and now update the files for all cases
#--------------------------------------------------------------------

chdir ("$ops_dir");

#copy real history files to temp files for reading and writing
`umask 002`;
##copy each file over
foreach $f (@history_files)
  {
    copy("${f}.dat","${f}-temp.dat");
  }

#----------------------------------------
# ACT on each file now
#----------------------------------------
foreach $file (@history_files)
  {
    trim($file); 
    $temp_file="${file}-temp.dat";
    $mission_hist_file="${file}.dat";
    #print "$temp_file $mission_hist_file\n";
    
    # Open the temporary history file for reading
    open(HIST, "$temp_file") || die "\nERROR! can't open history file: $temp_file";
    
    #----------------------------------------
    #if updating a maneuver load, grab the history info 
    # from last line of history file
    #----------------------------------------
    if ($choice eq "man")
      {
	$foo=<HIST>; #grab first line to find line length in bytes.
       	$goo=length($foo);
	seek HIST,-($goo),2; #set pointer to start oflast line
	$last=<HIST>;
	@last_line=split(/\s+/,$last);
	seek HIST,0,0; #set pointer to first record
      }
    #----------------------------------------
    #open real history files for updating
    #----------------------------------------
    open (OUT, "> $mission_hist_file");
    flock(OUT, LOCK_EX)|| die "Error: Cannot get an exlusive lock on $mission_hist_file";
    
    # While there are lines to be read in the temporary history file
    while (<HIST>)
      {
	#define line by line time in temporary history file
	@line_file = split (/\t/, $_);
	$time_file = trim($line_file[0]);
        # Convert the time from DOY to a decimal time
	$decimal=parse_time($time_file);

	if ($choice eq "stop" || $choice eq "too")
          { stop($decimal); }

	elsif ($choice eq "go")
          { go(int($decimal)); }

	elsif($choice eq "man")
          { stop_obs($decimal,$file); }

	elsif($choice eq "s107")
          { stop_obs($decimal,$file); }
      } # END WHILE  (<HIST>)

    close (HIST);
    #print "Completed copying new mission history.\n";
   
    #---------------------------------------- 
    # Reach end of file, add final entry that will carry the 
    # current state into the future 
    # Essential for fluence monitor!
    #----------------------------------------
    if ($choice eq "stop" || $choice eq "man" || $choice eq "s107"){
	if ($mission_hist_file =~ "FPHIST-2001.dat"){
	    if($choice eq "man"){
		printf OUT "%15s\t%8s\t%6.0f\n",$stop_all,$status_array[1],$status_array[4];
	    }
	    else{ #both items in OBSERVING Slots
		printf OUT "%15s\t%8s\t%6.0f\n",$time_stop,$fp_inst,$obsid;
		printf OUT "%15s\t%8s\t%6.0f\n",$stop_all,$fp_inst,$obsid;
	    }
	}
	elsif ($mission_hist_file eq "GRATHIST-2001.dat"){
	    if ($choice eq "man")
	    {
		printf OUT "%15s\t%8s\t%8s\t%6.0f\n",$stop_all,$status_array[2],$status_array[3],$status_array[4];
	    }
	    else  #Items in OBSERVING SLOTS
	    {
		printf OUT "%15s\t%8s\t%8s\t%6.0f\n",$time_stop,$hetg,$letg,$obsid;
		printf OUT "%15s\t%8s\t%8s\t%6.0f\n",$stop_all,$hetg,$letg,$obsid;
	    }
	}
	elsif ($mission_hist_file eq "OBSHIST.dat"){
	    if ($choice eq "man")
	    {
		printf OUT "%15s\tMP_OBSID\t%9s\n",$stop_all,$status_array[4];
	    }
	    else #obsid in OBSERVING SLOTS
	    {
		printf OUT "%15s\tMP_OBSID\t%9s\n",$time_stop,$obsid;
		printf OUT "%15s\tMP_OBSID\t%9s\n",$stop_all,$obsid;
	    }
	}
	elsif ($mission_hist_file eq "TLMHIST.dat"){
	    if ($choice eq "man")
	    {
		printf OUT "%15s\tCOMMAND_HW\t%10s\n",$stop_all,$last_line[2];
	    }
	    elsif($choice eq "stop") 
	    {
		printf OUT "%15s\tCOMMAND_HW\t%10s\n",$time_stop,$format;
		printf OUT "%15s\tCOMMAND_HW\t%10s\n",$stop_all,$format;
	    }
	    # NO ACTION IN THE CASE OF SCS 107. TLM is in VEHICLE
	}
	elsif ($mission_hist_file eq "TSCHIST.dat"){
	    if ($choice eq "man")
	    {
		printf OUT "%15s\t  SIMTRANS\t%10s\n",$stop_all,$status_array[5];
	    }
	    else  #always stop, should be HRC-S in these cases.
	    {  #need to know the stop instrument, 
		#but in theory, it had better be HRC-S
		$sim= $SIMPOS{$fp_inst};
		printf OUT "%15s\t  SIMTRANS\t%10s\n",$time_stop,$sim;
		printf OUT "%15s\t  SIMTRANS\t%10s\n",$stop_all,$sim;
	    }
	}
	elsif ($mission_hist_file eq "DITHHIST.dat"){	
	    if ($choice eq "man")
	    {
       		printf OUT "%15s\tCOMMAND_SW\t%10s\n",$stop_all,$last_line[2];
	    }
	    elsif($choice eq "stop") #dither is in vehicle
	    {
		printf OUT "%15s\tCOMMAND_SW\t%10s\n",$time_stop,$dither;
		printf OUT "%15s\tCOMMAND_SW\t%10s\n",$stop_all,$dither;
	    }
	    # DO NOTHING in the case of SCS 107. DITHER is in VEHICLE
	}   
    } # ENDIF  ($choice eq "stop" || $choice eq "man" || $choice eq "s107"){

    #--------------------------------------------------
    # This portion adds the status array at the time of load 
    # interruption to hist files (for too's)
    #--------------------------------------------------
    elsif ($choice eq "too")
      {
	if ($mission_hist_file eq "FPHIST-2001.dat"){
	    printf OUT "%15s\t%8s\t%6.0f\n",$time_stop,$fp_inst,$obsid;
	}
	elsif ($mission_hist_file eq "GRATHIST-2001.dat"){
	    printf OUT "%15s\t%8s\t%8s\t%6.0f\n",$time_stop,$hetg,$letg,$obsid;
	}
	elsif ($mission_hist_file eq "OBSHIST.dat"){
	    printf OUT "%15s\tMP_OBSID\t%9s\n",$time_stop,$obsid;
	}
	elsif ($mission_hist_file eq "TLMHIST.dat"){
	    printf OUT "%15s\tCOMMAND_HW\t%10s\n",$time_stop,$format;
	}
	elsif ($mission_hist_file eq "TSCHIST.dat"){
	    $sim= $SIMPOS{$fp_inst};
	    printf OUT "%15s\t  SIMTRANS\t%10s\n",$time_stop,$sim;
	}
	elsif ($mission_hist_file eq "DITHHIST.dat"){	
	    printf OUT "%15s\tCOMMAND_SW\t%10s\n",$time_stop,$dither;
	   }
      } # END  elsif ($choice eq "too")  	
    close(OUT);

    # Don't copy for too or test case..too will do it in ACE-update.pl
    # Test = 0 means NOT TEST
    if ($choice ne "too" && $test == 0)
      {
	print "${ops_dir}/$mission_hist_file has been updated...\n";

        # ACIS60-V
      	print "HF - copying: $mission_hist_file to acis60-v:$acis60_v_flu\n";
	system("scp ${ops_dir}/$mission_hist_file  acisweb\@acis60-v:${acis60_v_flu}");

        # ACISOCC-V
      	print "HF - copying: $mission_hist_file to acisocc-v:$acisocc_v_flu\n";
	system("scp ${ops_dir}/$mission_hist_file  acisweb\@acisocc-v:${acisocc_v_flu}");

        # COLOSSUS-V
      	print "HF - copying: $mission_hist_file to colossus-v:$colossus_v_flu\n";
	system("scp ${ops_dir}/$mission_hist_file colossus-v:${colossus_v_flu}");

        # ACISCDP-V
      	print "HF - copying: $mission_hist_file to aciscdp-v:$aciscdp_v_flu\n";
	system("scp ${ops_dir}/$mission_hist_file  acisweb\@aciscdp-v:${aciscdp_v_flu}");

        # HAN-V
      	print "HF - copying: $mission_hist_file to han-v:$han_v_flu\n";
	system("scp ${ops_dir}/$mission_hist_file han-v:${han_v_flu}");

        # LUKE-V
      	print "HF - copying: $mission_hist_file to luke-v:$luke_v_flu\n";
	system("scp ${ops_dir}/$mission_hist_file luke-v:${luke_v_flu}");

	$i++;   
      }
    elsif ($choice eq "too")
      {
	$i++;
      }
    else
      { 
	print "\n\n$file - History file run under TEST mode.";
	print "\nNo files are copied to acis60-v/acisocc-v/Colossus-v/aciscdp-v during testing";
        print "\nBut if I WERE going to copy files, the commands I'd give would look something like this:";
 
        print "\n  scp /proj/sot/acis/FLU-MON/$mission_hist_file  acisweb\@acis60-v:${acis60_v_flu}";
        print "\n";

      }
} # END foreach $file (@history_files) 



#------------------------------
# Update files now for the TOO
#------------------------------
# The dollar sign has been missing on the s107 choice since October 2013
if ($choice eq "too" || $choice eq "stop" || $choice eq "s107")
{
    $tstop = $status_array[0];
    if($test == 0)
      {
	print "Updating crm_saved_time.dat mission_hist_file with load interrupt information...\n";
        system ("base_dir/LoadReviews/script/crm_saved_time_interrupt_updater.pl ${choice} ${tstop}");
      }

    # Special case handling for TOO's
    if($choice eq "too")
      {
	print "Running ACE-update$appx.pl to update history mission_hist_files with TOO load...\n";
        print "\n TOO,STOP, or S107 ACE Update Command: $ACE_UPDATE\n";
        system ("$ACE_UPDATE") == 0 || die "$ACE_UPDATE failed to execute properly\n";
      }
}
if($test == 0){
    open(MAIL, system "echo 'command line: history-files$appx.pl $callstr' |mailx -s 'history-files$appx.pl has just been run' acisdude");
    
    close MAIL;
}

#
# NLET - Thermally Consequential Non-Load Event Tracking
#
# First set the command line to Non-Test
my $NLET_cmd = "/proj/sot/ska/bin/python /data/acis/LoadReviews/script/NONLOADEVENTTRACKER/RecordNonLoadEvent.py ";

# Now, if this was a history-files.pl -t or SATEST command, add the -t switch
# NOTE: IT is RecordNonLoadEvent.py that decides to which file the data gets written
if($test || $sa_testdir)
  { $NLET_cmd = "/proj/sot/ska/bin/python /data/acis/LoadReviews/script/NONLOADEVENTTRACKER/RecordNonLoadEvent.py -t "; }

my $descr = "None Given";

# Get some sort of description from the user
if ( $choice eq "too" || $choice eq "stop" || $choice eq "s107" || $choice eq "man" || $choice eq "go")
  {
       print STDOUT "\nEnter a one line description as to event cause and the date: ";
       $descr=<STDIN>; 
       chop($descr);
   }

# Now record this event in the NonLoadTrackedEvents.txt file
# PROCESS STOP
if ($choice eq "stop")
  {
    # First record the Actual STOP
    #           Type             Time                       Source                  Status array
   `$NLET_cmd $choice --event_time $status_array[0] --source history_files.pl --status_line $status_array[1] --desc "$descr" `; 

    # Determine if this is a Normal Sun Mode action

    my $nsm_q = "";
    
    while ( ( $nsm_q ne "Y") & ( $nsm_q ne "N"))
      {
       print STDOUT "\nIs this a NORMAL SUN MODE action? [y/n - RET = NO]: ";
       $nsm_q=<STDIN>; 
       chop($nsm_q);
    
       # Uppercase the response
       $nsm_q = uc $nsm_q;
    
       # If the user just hit Return, take that as a no
       if ($nsm_q eq "")
         {
          print "\nYou just hit return so I'll take that as a NO\n";
          $nsm_q = "N";
         }
    
       # If the user typed something other than Y, N or RET, then
       # prompt again
       if ( ( $nsm_q ne "Y") & ( $nsm_q ne "N"))
         {print "\nYou entered: $nsm_q. \nPlease Enter Y, N or hit Return (RET = NO).\n"}
    
      } # End While ( ( $nsm_q ne "Y") | ( $nsm_q ne "N")
    
    
    print "\nUser Response to:  Is this an NSM? is: $nsm_q\n";
    
    # Create flag to determine if any quaternion value is
    # bogus, and therefore non-normalized. Initialize to
    # False - the quaternions are NOT bogus
    my $q_bogus = 0;

    # If the user typed YES, then obtain 4 Quaternions
    if ($nsm_q eq "Y")
      {
        # Prompt user.....
        print STDOUT "\nPlease enter Q1: ";
        # Get the user intput.....
        $q1=<STDIN>; 
	# Chop the <CR>
        chop($q1);
        # If the user just hit Return set the Q to a bogus value
        # and set the q_bogus flag to True (1)
        if ($q1 eq "")
          {$q1 = "None";
           $q_bogus = 1;
          }
        
        print STDOUT "\nPlease enter Q2: ";
        $q2=<STDIN>; 
        chop($q2);
        if ($q2 eq "")
          {$q2 = "None";
           $q_bogus = 1;
          }
        
        print STDOUT "\nPlease enter Q3: ";
        $q3=<STDIN>; 
        chop($q3);
        if ($q3 eq "")
          {$q3 = "None";
           $q_bogus = 1;
          }
        
        print STDOUT "\nPlease enter Q4: ";
        $q4=<STDIN>; 
        chop($q4);
        if ($q4 eq "")
          {$q4 = "None";
           $q_bogus = 1;
          }

        # Print out the user's data responses
        print "\nUser Data Responses for this NSM:\n $q1 $q2 $q3 $q4\n";

        # Determine if the user hit Return for any of the Q's
        # If so, then Warn the user that the NLET file MUST be updated
        # before running a model.
        if ($q_bogus)
	{
	    print "\n\nWARNING!!!!!!  You have entered a bogus value for one or more of the Quaternion values.\nThese values will be entered in the Non-Load Event Tracking file as is.\n\nHOWEVER, you MUST edit the file:\n\n/data/acis/LoadReviews/NonLoadTrackedEvents.txt\n\n... and insert the Correct Values BEFORE you attempt to run a thermal model.\n";
	}


        # Now record the Maneuver in the NLET file
        # You have to make another call to RecordNonLoadEvent.py in order to record
        # The fact that the spacecraft transitioned to Normal Sun Mode
         `$NLET_cmd MAN --event_time $status_array[0] --source history_files.pl --desc "NSM Pitch to 90 degrees"  --q1 $q1 --q2 $q2 --q3 $q3 --q4 $q4 `; 
      } # End IF ($nsm_q eq "Y")
    
    
   } # END IF CHOICE == STOP
    
elsif ($choice eq "too")
  {
    #           Type             Time                       Source                  Status array
   `$NLET_cmd $choice --event_time $status_array[0] --source history_files.pl --status_line $status_array[1] --desc "$descr" `; 
  }
elsif ($choice eq "s107")
  {
    #           Type             Time                       Source                  Status array
   `$NLET_cmd $choice --event_time $status_array[0] --source history_files.pl --status_line $status_array[1] --desc "$descr" `; 
  }
elsif ($choice eq "man")
  {
     my @man_status_array = join (",", $status_array[2], $status_array[3], $status_array[4]) ;
     #          Type             Time                       Source                 Status array
     `$NLET_cmd $choice --event_time $man_doy_last_time --source history_files.pl  --status_line @man_status_array --desc "$descr" `; 
  }
elsif ($choice eq "go")
  {
      #                 Source                                   Type 
     `$NLET_cmd $choice --source history_files.pl --desc "$descr" `; 
  }
else
{
    print "\n****************I DID NOT RECOGNIZE A TYPE\n";
}
exit();

#--------------------------------------------------------------------
#                                         SUBROUTINES
#--------------------------------------------------------------------

#Stop_obs: 
#only stop certain files.
sub stop_obs {
    #only stop certain files.
    my ($_decimal) = $_[0];
    my ($_file_name) = $_[1];
    
    #define time of load stoppage
    $time_stop = trim($status_array[0]); #WAIT... 
    $decimal_day_stop=parse_time($time_stop);
    

    #loop through history file comparing time in file to time load stopped
    #------------------------------
    #if time of the stop in ARGV[2] is greater or equal to file time,
    #keep the file line with print statement

    if(($decimal_day_stop > $_decimal) || 
       abs($decimal_day_stop-$_decimal) < 1.0e-6 ){ #allow for close information
	print OUT "$_"; #

    }
    else{#okay, we past the interupt time so stop on some files.
	if($_file_name =~ /DITH/ ||
	   $_file_name =~ /TLM/)
	{ 
	    if ($_decimal < 9999){ 
		print OUT "$_";
	    }
	    
	}
    }
}


sub stop
 { #stop all files
    my ($_decimal) = $_[0];
    
    #define time of load stoppage
    $time_stop = trim($status_array[0]); #WAIT... 
    $decimal_day_stop=parse_time($time_stop);



    #loop through history file comparing time in file to time load stopped
    #------------------------------
    #if time of the stop in ARGV[2] is greater than file time,
    #keep the file line with print statement

    if($decimal_day_stop > $_decimal)
      {
	print OUT "$_";
      }
 } # END sub stop

sub go {
#copy as long as the year is less than 9999
    my ($_year) = $_[0];
    
    if ($_year < 9999){ 
	print OUT "$_";
    }
   
}



sub LOCK_SH()  { 1 }     #  Shared lock (for reading)
sub LOCK_EX()  { 2 }     #  Exclusive lock (for writing)
sub LOCK_NB()  { 4 }     #  Non-blocking request (don't stall)
sub LOCK_UN()  { 8 }     #  Free the lock (careful!)



#--------------------------------------------------------------------
#parse_times: parse the string YYYY:DOY:HH:MM:SS.SSS into a decimal year
#--------------------------------------------------------------------
sub parse_time {
    my($str)=@_;
    #split on colons
    @time_line = split (/:/, $str);
    $days_in_year=365.0;
    $year = $time_line[0];
    $day = $time_line[1];
    $hour = $time_line[2];
    $minute = $time_line[3];
    @seconds=split(/\s+/,$time_line[4]); #junk at end of line
    $second = $seconds[0];
    
    #Check for Leap Year
    if((($year % 4 == 0) && ($year % 100 != 0) )|| ($year % 400 == 0)){
	$days_in_year=366.0;
    }


    #convert first to a decimal day
    #Then to decimal year.
    $decimal_day=$day+($hour/24.)+($minute/(60.*24.))+($second/(3600.0*24.));
    $decimal = $year+($decimal_day/$days_in_year);
    return $decimal;
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
#print help: print the help message
#--------------------------------------------------------------------
sub print_help() {

    die "ERROR!\nUSAGE: There are five ways to use this script...\n 1. if loads just stopped (for SCS107) and you need to update the history files, run: \n history-files.pl [-s107] [time of load stop] [current state] \n \n 3. if loads stop due to any other safing action and you need to update the history files, run: \n history-files.pl [-stop] [time of load stop] [current state] \n \n 3. if new replan loads have been created and approved and you need to update the history files accordingly, run: \n history-files.pl [-go]\n\n 4. A fast TOO has been approved and you need to update the history files to reflect this.  \n history-files.pl [-too] [time of load interrupt] [current state] \n\n 5. A maneuver load has been created and approved and you need to update the history files to reflect this.  \n history-files.pl [-man] \n\nEXAMPLES:\n 1. This option removes all obseriving history after the stop time and inserts '9999' line with current status. Load stopped at 2002:090:01:43:57.095\n history-files.pl -s107 2002:090:01:43:57.095 HRC-S,HETG-OUT,LETG-OUT,2118,OORMPDS,CSELFMT2,ENAB \n\n 2. This option removes all history after the stop time and inserts '9999' line with current status. Load stopped at 2002:090:01:43:57.095\n history-files.pl -stop 2002:090:01:43:57.095 HRC-S,HETG-OUT,LETG-OUT,2118,OORMPDS,CSELFMT2,ENAB \n\n 3. This option automatically runs ACE-update.pl to update history files and then removes the extra '9999' line in each history file.\n history-files.pl -go\n\n 4. This option cuts the history files at the point of load interruption and then runs ACE-update.pl to update the new load history.\n history-files.pl -too 2002:281:01:43:57.095 HRC-S,HETG-OUT,LETG-OUT,2118,OORMPDS,CSELFMT2,ENAB \n\n 5. This option runs ACE-update.pl to append maneuver load history, then moves the '9999' line to the bottom of each history file to preserve the history.\n history-files.pl -man\n";

} 

#--------------------------------------------------------------------
#validation_input
#--------------------------------------------------------------------
sub validate_input(){
    my @array=@_;
    my @time=split(':',$array[0]);
   

    #confirm proper time array
    
    if (@time != 5){
	die "ERROR! Please double check your command line and start over, time is given in YEAR:DAY:HOUR:MIN:SEC\n";
    }
    elsif ($time[0] !~ /^20\d\d/){
	die "ERROR! The year $time[0] is invalid! Please check your command line arguments and start over.\n";
    }
    elsif ($time[1] gt 366 || $time[1] lt 0){
	die "ERROR! The day of year $time[1] is invalid! Please check your command line arguments and start over.\n";
    }
    elsif ($time[2] gt 23 || $time[2] lt 0){
	die "ERROR! The hour $time[1] is invalid! Please check your command line arguments and start over.\n";
    }    
    elsif ($time[3] gt 59 || $time[3] lt 0){
	die "ERROR! The minute $time[1] is invalid! Please check your command line arguments and start over.\n";
    }    
    elsif ($time[4] gt 59.999 || $time[4] lt 0){
	die "ERROR! The second $time[1] is invalid! Please check your command line arguments and start over.\n";
    }   
    
    #check the status array
    
#Error trap for invalid status array
    @stat = split(/,/,$array[1]);

    if (@stat != 7){
	die "ERROR! Please double check your command line and start over, the status array should have 7 fields:\nFPINST,HETG-[IN/OUT],LETG-[IN/OUT],OBSID,RADMON[ENAB/DISAB],FORMAT,DITHSTATUS\n";
    }else{
	#define GLOBAL current state of spacecraft
	$current_state = trim($array[1]);
	@states = split(/,/, $current_state);
	$fp_inst = $states[0];
	$hetg = $states[1];
	$letg = $states[2];
	$obsid = $states[3];
	$radmon = $states[4];
	$format = $states[5];
	$dither = $states[6];
	 
    }
}
#--------------------------------------------------------------------
# set test: sets up the script for testing
#--------------------------------------------------------------------
sub set_test_env()
 {
#    $test_dir = "/pool14/acisdude/history-files/test";
# NOTE: Upgrade to following line once history-files regression
# is made to conform to standard lr regression protocol 
    if (! $sa_testdir)
      {  # Test is part of regression suite
	$test_dir = "/pool14/duderg/src/regress/history-files";
	$ops_dir="$base_dir/acisdude/reg_script/${choice}test";
	
	$ACE_UPDATE="${test_dir}/ACE-update.pl -test $ops_dir";
	foreach $f (@history_files)
            {
	    copy("${ops_dir}/in/${f}.dat", "$ops_dir/${f}.dat") ||
		die "Copy of ${ops_dir}/in/${f}.dat failed: $!";;
            }
      } #ENDIF  (! $sa_testdir)
    
    else
      {

	# Assumes desired input global files in $sa_testdir before 
	# calling history-files.pl or history-files_bak.pl.
	$ops_dir = $sa_testdir;
	$ACE_UPDATE="$ACE_UPDATE -test $ops_dir";
      }
    $test = 1; # So we don't have to check for both $test and $satest

    print "TESTING:\n $ACE_UPDATE\n $ops_dir\n";
}

#------------------------------------------------------------
# Function to find LATEST non-9999 Time
#------------------------------------------------------------
sub latest_time{

 # Grab the list of files from the argument
 my(@file_list)=(@_);
 
# Initialize the status array to empty.
 my @internal_status_array=();

 # Convert 1999 to decimal time. This is the earliest time possible
 # and the starting time for subsequent comparisons.
 my $last_time=parse_time("1999:001:00:00:00.00"); # earliest possible in DECIMAL form
 my $doy_last_time = "1999:001:00:00:00.00";       # earliest possible in STRING form

 # Find the latest time of all the files.
 foreach $f (@file_list)
   {     
     # Get the last non-9999 line in the file
     $str=get_last_time("$ops_dir/${f}.dat");

     # Split the string out
     @time_string=split(/\s+/,$str);

     # Save the DOY version of the time
     $doy_time = $time_string[0];

     # Convert the file time from DOY to decimal
     $time=parse_time($time_string[0]);

     # Which is later? The last time? Or the one you just extracted?
     # Whichever, set last_time to the latest
     if ($last_time<$time)
         {
	   $last_time=$time;
           $doy_last_time = $doy_time;
         }

     # Set the first element in the resultant status array to the 
     # latest time you've found so far.
     $internal_status_array[0]=$last_time;

     # Then add the status array values which are appropriate to the
     # type of History file
     if ($f =~ /FP/) {
	 $internal_status_array[1]=$time_string[1];
     } elsif ($f =~ /GRAT/) {
	 $internal_status_array[2]=$time_string[1];
	 $internal_status_array[3]=$time_string[2]; 
     } elsif ($f =~ /OBS/) {
	 $internal_status_array[4]=$time_string[2];
     } elsif ($f =~ /TSC/) {  
	 $internal_status_array[5]=$time_string[5]; 
     } else {
	 break;
     }
   } # ENDFOREACH foreach $f (@file_list)
  
 # Return the DOY version of the time and the status array
 return ($doy_last_time,  @internal_status_array);
}

#--------------------------------------------------------------------
#get_last_time(){ - Get the last two lines in the file and
#                   return the latest line whose time is not
#                   9999
#--------------------------------------------------------------------
sub get_last_time(){
    my($filename)=(@_);
    print $filename;
    @list=`tail -2 $filename`;
    # If the last line in the file is a 9999 line
    # return the second to the last line
    if($list[1] =~ /9999:999/)
       {
	return $list[0];
       }
    else # Otherwise return the last line
       {return $list[1]};
}
