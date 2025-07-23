#! /bin/env perl  
#--------------------------------------------------------------------
# Note: /usr/local/bin on Solaris contains the most up to date perl
#       /usr/local/bin on Linux points to /usr/bin, the most up to date perl
# SCRIPT USAGE:
#       /data/acis/LoadReviews/script/acis-backstop.pl <full path to current week's OFLS version>/CDAY.hhmm.backstop <full path to preceding week's approved OFLS version>/ACIS-History.txt
#
# EXAMPLE:
#      acis-backstop.pl {path/*.backstop} {path/ACIS-History.txt}
#      acis-backstop.pl $SOTMP/2000/SEP1200/ofls/CMI256:1602.backstop $SOTMP/2000/SEP1200/ofls/ACIS-History.txt
#

# WORKING AREA: /data/acis/LoadReviews/script/
#
#--------------------------------------------------
#
# Produces as output in the directory the script was executed within:
#       ACIS-LoadReview.txt      <-- Reviewed by ACIS Ops
#       ACIS-History.txt         <-- To be used in the next load
#       ACIS-FPHIST.dat          <-- To be used by SNV in his ACIS orb fluence mon
#       ACIS-GRATHIST.dat        <-- To be used by SNV in his ACIS orb fluence mon
#       ACIS-OBSHIST.txt         <-- Used in ACIS Real-time web page
#       ACIS-TLMHIST.txt         <-- Used in ACIS Real-time web page
#       ACIS-TSCHIST.txt         <-- Used in ACIS Real-time web page
#       ACIS-DITHHIST.dat        <-- Used in ACIS Real-time web page
#
# UPDATE - June 26, 2016
#          Royce Beuhler
#          V2.15
#          Added logic for the "bak" suffix capability.
#
# UPDATE - December 5, 2016
#          Gregg Germain
#          V2.16
#          Changed from "Browser" username to "acisops" for access
#          to the OCAT
#
# Update: January 31, 2017
#         Gregg Germain
#         - Modified program to always attempt to collect Dither
#           information from the OCAT. 
#         - Modified program to always print out Dither
#           information and put it before the "Cycle" printout
#         - Always collect Dither info from the OCAT
#
# Update: June16, 2017
#         Gregg Germain
#         - Modified code to handle the fact that ECS measurement Obsid's 
#           now start at 38000.
#         - Variables $min_cti_obsid and $max_special_obsid were created 
#           to make any future Obsid limit change easy to implement.
#         - Modified code to print out a row of "-cti"'s when a Perigee Passage
#           CTI measurement is completed.
#         - Added numerous comments
#
# Update: January 6, 2022
#         Gregg Germain
#         V3.3
#         - Modified the "triplet" code to include WSPOW00000 as a legal
#           triplet power command.  Also combined the 2 individual sections
#           of triplet power command test code into one which now includes the WSPOW0.
#
# Update: April 4, 2022
#         - Incorporating HIST_File_Utilities_Class and creating
#           ACIS-SCS155HIST.dat in OFLS directory
#
#  Called from LR with this line:
#
#        /data/acis/LoadReviews/script/acis-backstop.pl -s server  CR*.backstop_path  Cont_Load_ACIS-History.txt
#                          server - ocatsqlsrv   
#                          Review Load backstop file path  - /data/acis/LoadReviews/2022/MAR2821/oflsa/CR086_2107.backstop
#                          hist - $prev_load_dir/ACIS-History.txt
#
# Update: August 18, 2022
#              - V3.5
#              - Perigee Passage TXGING Quiet checks removed
#
# Update: October 25, 2024
#               - V3.6
#               - Solve the ACIS-HRC-ACIS SI mode issue when the two ACIS SI
#                 modes are the same.
#
# Update: July 23, 2025
#               V3.7
#               - Eliminate the false error when acis-backstop uses the incorrect AA00 to
#                 calculate the time between the Stop Science and Obsid Change
#
#--------------------------------------------------------------------
use DBI;
use Text::ParseWords;
use IO::File;
use File::Basename;
use POSIX qw(tmpnam ceil floor);
use Getopt::Std;
use Getopt::Long;
use Time::Local;
use Date::Calc qw(Add_Delta_Days);
#  ($year, $month, $day = Add_Delta_Days($year,1,1, $doy - 1);
use Date::Calc qw(Add_Delta_DHMS);

use Scalar::Util qw(reftype);

#----------------------------------------
#Variables:
#----------------------------------------

# ARGV[2] contains the full path to the Review load CR*.backstop file
# Extract the full path to the directory
$last_slash_pos = rindex($ARGV[2], "/");

# Extract the substring up to but not including the final /
$rev_load_dir_path = substr($ARGV[2], 0, $last_slash_pos);

# Create the Review Load SCS-155 Deadman History file ACIS-SCS155HIST.dat
system("python3 /data/acis/LoadReviews/script/UTILITIES/Create_Weekly_155_HIST_file.py $rev_load_dir_path");

$Rec_Time="";			# read the record and split
$Rec_VCDU="";			# VCDU counter
$Rec_MC="";			# Command
$Rec_Event="";			# event information
$Rec_Eventdata="";		# event data
$wspow="";			# wspow command, via sacgs

# As of June, 2017 Perigee Passage CTI obsids can be as low as 38000
$min_cti_obsid = 38000;
# Special observations such as Long Term CTI measurements, and others,
# are given Obsid's in the 60,000's. Various tests
$max_special_obsid = 69999;

$server="ocatsqlsrv"; #default server.

$ctifmtcheck=0;
$startscitime=0;
$startsciflag=0;

$science_running_flag = 0;
$first_stop_science_time = -1.0;
$last_pblock_loaded = "";

$lastCmdAcisFlag=0;
$lastCmdAcisTime=0;
$loadpblockflag=0;
$commflag=0;
$commstart=0;
$commend=0;
$radmonon=0;
$radmonff=0;
$radmonoff=0.0;
 
$hrcStime=0;
$elec1ent=0;
$elec1exit=0;
$NILpad=0;
$simtest1=0;
$simtest2=0;
$tstop=0;
$obsstart=0;
$exposure=0;
$obsend=0;
$delobs=0;

$enter_rad=0;
$perevt=0.0;
$timeindex=0;
$nom_zsim=0;
$delta_zsim=0;
$per_stopsci=0;
$per_vidalldn=0;
$perigee_time=0;
$per_oldstopsci=0;
$check_acis_sci=0;
$nil_flag=0;			# doing a NIL measurement
$cti_flag=0;			# doing a CTI measurement
#$quiet_flag=0;               # quieted the threshold crossings
                                        # Removed for FSW GIJ-58
$dec_day=0;
$pad=0;
$pad2=0;
$simtrans=0;
$viddwn_cnt=0;
$pblock_ef="N";			# pblock eventfilter(for win)
#
# For Cycles 1 through 10, eventAmplitdueRange was 15.0
# From 11 onward the new value was 13.
$pblock_lea=0.08;			# Pblock lowerEventAmplitude(for win)
$pblock_ear=13.0;			# pblock eventAmplitdueRange(for win)

$sys_cnt=0;
$huff_cnt=0;
$start_sci_cnt=0;
$stop_sci_count=0;
$obsid_cnt=0;
$letg_in_cnt=0;
$letg_out_cnt=0;
$hetg_in_cnt=0;
$hetg_out_cnt=0;

$start_comm=0;
$stop_comm=0;
$perigee_cnt=0;


$loaded_ocat=0;   #has the ocat been loaded.
$compare=0;      #has the ocat/pblock compare been done?
$flag_pblock=0; #pblock correctly loaded?
$flag_params=0; #Ocat & params match?
$flag_setup=0;  #instrument setup ok?
$flag_ccds=0;   #correct CCDs?
$flag_windows=0;#correct window?
@pblock_list;   #obsids with pblock errors
@param_list;    #Obsids with param errors
@setup_list;    #Obsids with setup errors
@ccd_list;      #Obsids with ccd errors
@window_list;   #obsids with window errors
@error_list;    #list of errors;
$tstart_orig=0; #time of start sci
$biasength="";
@biasinfo=0;

$biastime=0;
$tstart=0;#time of startsci+bias
$tstop=0;
$exposure=0;
$new_exposure=0;
$clear_buffer_time=0; #time to clear the buffers
$bitscleared=4320.0; #kbits in the buffers
$fmt_change=0.0; #time of format change;

$HETGin=0;
$LETGin=0;

$Test_Passed = 1;
#$Test_PassedC = 1;

#stored parameter blocks and window blocks.
$WTval="";
$WCval="";
$W2val="";
$W1val="";
$last_simode="";

$FPSI="??";
$HETG="??";
$LETG="??";
$FMT="??";
$DITH="UNKN";
$OBSID=999999;
$sim_z=0;
%pblock_entries=();
%ocat_entries=();
%window_entries=();
@window_wblock_array;  #leave empty, array of window hash for wblock
@window_ocat_array;    #leave empty, array of window hash for OCAT
$pow_cmd="";
$simode="";                     # current Simode
$ocat_simode="";		# OCAT SI_mode
$cti_simode="";                 # Radzone SImode
$nil_simode="";                 # Nil simode
$needwindow=1;			# need a window for this obs?
$inocat=0;			# is this in the ocat?
$triplet_check=0;		# check for radzone triplet
$dhhtr_state=0;			# state of the detector heater 0=off 1=on
#$obs = {      # Doesn't seem to be used anywhere. Uncomment 
#    $start=>0.0,  # these for lines or else delete.
#    $stop=>0.0,
#};
@crm_array;
@nil_array;   
%command_list=();
%si_mode_list=();
%chandra_status=();
%perigee_status=();
$min_perigee_time=55.00;# min ks on 140+pitch in perigee
@maneuvers=();  # array of maneuver hash
$first=1;
#--------------------------------------------------------------------
#SCRIPT START *** SCRIPT START *** SCRIPT START *** SCRIPT START ***
#--------------------------------------------------------------------
#Check for options: will remove options from argv
 $server="ocatsqlsrv";
 GetOptions( 's=s' => \$server); #to be passed to acisparams.pl

if(@ARGV != 2){
    die "ERROR! TWO INPUTS REQUIRED!\nUSAGE: $0 {current_week_path/*.backstop} {preceding_week_path/ACIS-History.txt}\n";
}
#--------------------------------------------------------------------
# NEW CODE to allow one acis-backstop.pl to run in regular and backup 
# modes
# SET UP the directory for the scripts
#--------------------------------------------------------------------
#if($0 =~ /bak/){
#called as acis-backstop_bak.pl
if (`lr_suffix.pl`) { # Null string if not on backup machine
    $base_dir=</data/acis-bak>;
}
else{
    $base_dir=</data/acis>;
}

$script_dir="$base_dir/LoadReviews/script";
$sacgs_dir="$base_dir/sacgs/bin";
$tln_file="$base_dir/LoadReviews/script/ACIS_current.tln";
$sacgs_dir="$base_dir/LoadReviews/Linux/scripts";
$egrep="/bin/egrep";


#print "The base directory is $base_dir\n";
#SETUP ITEMS for the script
setup_command_list(\%command_list);
setup_SI_MODES(\%si_mode_list);

read_history($ARGV[1],\%chandra_status);
#need to read the perigee passage
read_perigee($ARGV[0],$ARGV[1],\%perigee_status);

# Extract the last SI mode from the Continuity load ACIS-History.txt file.
$last_simode=$chandra_status{last_simode};
$first_simode=1; #flag to allow the OFLS to repeat the parameter blocks
#--------------------------------------------------------------------
#Open all files to be used
#--------------------------------------------------------------------
umask(002);
open_files(SIMTSC,">ACIS-TSCHIST.dat");
open_files(OBSIDHIST,">ACIS-OBSHIST.dat");
open_files(FPHIST,">ACIS-FPHIST.dat");
open_files(GRATHIST,">ACIS-GRATHIST.dat");
open_files(DITHHIST,">ACIS-DITHHIST.dat");
open_files(TLMHIST,">ACIS-TLMHIST.dat");
open_files(LR, ">ACIS-LoadReview.txt");
open_files(HIST_OUT, ">ACIS-History.txt");
open_files(PERIGEE_OUT,">ACIS-Perigee.txt");
open_files(STOREHIST, ">ACIS-STORED-HIST.txt");
open_files(BACK,$ARGV[0]);
#------------------------------------------------------------
# Read and store the manuever start and stop times
# File is the directory of the backstop/mm*.sum
#--------------------------------------------------------------------
###NOTE- Make some changes to get rid of the extra calls to the maneuver
#FILE
$dir = dirname($ARGV[0]);
$dir2=dirname($ARGV[1]);
$last_manfile=`ls ${dir2}/mm*.sum 2>/dev/null`;
$manfile=`ls ${dir}/mm*.sum 2>/dev/null`;
&read_manuever($manfile,\@start_man,\@stop_man);
#read last and current maneuvers
&read_maneuver_hash($last_manfile,\@maneuvers);
&read_maneuver_hash($manfile,\@maneuvers);
#--------------------------------------------------------------------
# Read and store the CRM and NIL file information
# CRM file is backstop/*CRM*
# NIL file is backstop/*.er
#--------------------------------------------------------------------
$CRMfile=`ls ${dir}/DO*CRM_Pad.txt 2>/dev/null`;
read_CRM_file($CRMfile,\@crm_array);
$NILfile=`ls ${dir}/*.er 2>/dev/null`;
read_NIL_file($NILfile,\@nil_array);

print LR "\n-------------------------------------------------\n";
print LR "ACIS LOAD REVIEW OUTPUT:\n";
print LR "FOR REVIEW BY CXC ACIS OPS PERSONNEL\n";
print LR "\n";
print LR "-------------------------------------------------\n";
print LR "\n";
print LR "USING $ARGV[0]\n\n";
print LR "LOAD HISTORY FROM: $ARGV[1]\n\n";
print LR "-- CHANDRA LOAD START --\n\n";



#--------------------------------------------------------------------
#Open the database ONCE, connect NOW
#--------------------------------------------------------------------
#Connect to the database:
# OLD BROWSER USERNAME database username, password, and server
#$user="browser";
#$passwd="newuser";

# Browser replacement TEST OCAT
#$user="acisops";
#$passwd="aopspd22";

# Connect to the database: OPERATIONAL
# NEW OCAT USERNAME database username, password, and server
$user="acisops";
$passwd="gpCjops)";

$serverstr="dbi:Sybase:${server}";

#open connection to sql server
my $dbh = DBI->connect(($serverstr, $user, $passwd)) || die "Unable to connect to database". DBI->errstr;

# use axafocat and clean up
$dbh->do(q{use axafocat}) || die "Unable to access database axafocat". DBI->errstr;

#---------------------------------------------------------
# Main, read the next record in the backstop file
#--------------------------------------------------------------------
while ( <BACK> ) 
{
    Process_Next_Record($_);
    $scs_val=$Rec_Eventdata{SCS}; #new, record SCS data
    push (@timecont,$dec_day);
    #----------------------------------------
    #if first time, update histories
    #----------------------------------------
    if($first == 1){
	update_history_files(FPHIST,\%chandra_status);
	update_history_files(GRATHIST,\%chandra_status);
	update_history_files(TLMHIST,\%chandra_status); 
	update_history_files(OBSIDHIST,\%chandra_status);
	update_history_files(DITHHIST,\%chandra_status);
	update_history_files(LR,\%chandra_status);
        $first=0;
    }
    #----------------------------------------
    #Confirm that this is a command we care about
    #----------------------------------------
    if ($Rec_Event eq "ACISPKT" ||
	$command_list{($Rec_Eventdata{TLMSID})} ||
	$command_list{($Rec_Eventdata{TYPE})}  ||
	$command_list{($Rec_Event)}  ||
	$Rec_Eventdata{TLMSID} =~ /CSELFMT/ ||  #FORMAT
	$Rec_Eventdata{TLMSID} =~ /\A1/) {      #ACIS HARDWARE COMMANDS
	#----------------------------------------
	# We care. Handle each set of commands
	#----------------------------------------
	check_scs($scs_val); #check if this a valid for ACIS in vehicle load
	#----------------------------------------
	SWITCH: {
	    #Comms:
	    if($Rec_Eventdata{TLMSID} =~ /CTX/){
		process_comm();
		last SWITCH;
	    }
	    #Gratings:
	    if($Rec_Eventdata{TLMSID} =~ /ETG/){
		process_TG(\%chandra_status);
		last SWITCH;
	    }
	    
	    #Dither:
	    if($Rec_Eventdata{TLMSID} =~ /DITH/){
		process_dither(\%chandra_status);
		last SWITCH;
	    }
	    
	    #Radiation Monitor
	    if($Rec_Eventdata{TLMSID} =~ /OORMP/)
	    {
		process_radmon(\%chandra_status,\%perigee_status,@crm_array);
		last SWITCH;
	    }
	    
	    #Format Change
	    if($Rec_Eventdata{TLMSID} =~ /CSELFMT/)
	    {
		process_format(\%chandra_status);
		last SWITCH;
	    }

	    
	    #RadZone Entry and Exit
	    if($Rec_Event =~ /ORBPOINT/){
		process_radzone(@crm_array);
		last SWITCH;
	    }
	    
	    #SIM FOCUS and Translations
	    if($Rec_Event =~ /^SIM/)
	    {
		process_sim(\%chandra_status);
		last SWITCH;
	      } # END SIMTRANS

	    #Obsid Changes in response to an MP_OBSID command
	    if ($Rec_Event =~ /MP_OBSID/)
	      {
		obsid_change(\%chandra_status);
		last SWITCH;
	      } # END OBSID CHANGES
	    
	    #Stop Sciences
	    if ($Rec_Eventdata{TLMSID} =~ /AA00000000/)
	      {
	  	  process_stop_science();
		  confirm_packet_space();
		  last SWITCH;
	      } 
	    
	    #Start Science
	    if ($Rec_Eventdata{TLMSID} =~ /XTZ0000005/ || 
		$Rec_Eventdata{TLMSID} =~ /XCZ0000005/)
	     {
		 # Process the start science command
		 process_start_science();
		 
		check_acistime();		
		last SWITCH;
  	    }
	    
	    #Load Parameter blocks
	    if ($Rec_Eventdata{TLMSID} =~ /WT0*/  ||
		$Rec_Eventdata{TLMSID} =~ /WC0*/ )
	    {
		check_acistime();
		load_pblock(\%chandra_status);
		last SWITCH;
	      }
	    #Load Window Blocks
	    if ($Rec_Eventdata{TLMSID} =~ /W100*/ ||
		$Rec_Eventdata{TLMSID} =~ /W200*/)
	       {
	 	  load_windowblock(\%chandra_status);
		  check_acistime();
		  last SWITCH;
	      }
	    #all other ACIS commands:
	    else
	      {
		#process_acispkt();
		process_acispkt(\%perigee_status);
		check_acistime();
	      }
	}#end SWITCH   
      }#end lines we care about -  if ($Rec_Event eq "ACISPKT" ||.....
    } #END WHILE BACK - end processing backstop file

end_load(\%chandra_status);
check_errors();
#cleanup

close(SIMTSC);
close(OBSIDHIST);
close(FPHIST);
close(GRATHIST);
close(DITHHIST);
close(TLMHIST);
close(LR);
close(HIST_OUT);
close(STOREHIST);
close(PERIGEE_OUT);
if(-f "/tmp/temp.tln"){
    unlink("/tmp/temp.tln");
    }
exit;

#--------------------------------------------------------------------
# SUBROUTINES SUBROUTINES SUBROUTINES SUBROUTINES SUBROUTINES
#--------------------------------------------------------------------
#--------------------------------------------------------------------
# Setup_command_list: take an array of commands that are
#                     actually used from the backstop file and
#                     fill a hash table with them for easy lookup
#--------------------------------------------------------------------
sub setup_command_list{ 
    my($comms)=(@_);
    @commands= ("AFIPD",#items that are $Rec_Eventdata{TLMSID}
		"AODSDITH",
		"AOENDITH",
		"CTXAON",
		"CTXAOF",
		"CTXBON",
		"CTXBOF",
		"OORMPDS",
		"OORMPEN",
		"CSELFMT*",		
		"4ISHGBEN",#enable insert HETG
		"4EXHGBEN",#start move
                "4EXHGBDS",#end move
		"4RTHGBEN",#enable retract HETG
		"4OLETGIN",#Inerted LETG
		"4OLETGRE",#Retracted LETG
		"4OHETGIN",#inserted HETG
		"4OHETGRE",#Retracted HETG
		"EEF1000", #rad zone entry #$rec_Eventdata{TYPE}
		"EE1RADZ0",#rad zone entry
		"EE2RADZ0",#rad zone entry
		"EP2RADZ0",#rad zone exit
		"EP1RADZ0",#rad zone exit
		"XEF1000", #rad zone exit
		"EPERIGEE",#Perigee
		"EAPOGEE", #Apogee
		"SIMTRANS",
		"SIMFOCUS",
		"MP_OBSID",
		"\A1");
    $i=1;
    foreach $f (@commands){
	$$comms{$f} = $i++;
    }
    return;
}
#--------------------------------------------------------------------
#setup_SI_MODES- set up an associative array for 
#                diagnostics NOT in the ocat
#--------------------------------------------------------------------
sub setup_SI_MODES{
    my($si_mode_array)=(@_);

    #NEED THE ACIS UNDERCOVER SOMEHOW
    $si_mode_array->{"WT007AC024"}="TE_007AC"; #new CTI
    $si_mode_array->{"WT007EC024"}="TE_007AE"; #new CTI
    $si_mode_array->{"WT00B26014"}="TE_00B26"; #new CTI
    $si_mode_array->{"WT0021C034"}="TE_0021C"; #CTI S-array
    $si_mode_array->{"WT00216034"}="TE_00216"; #CTI I-array
    $si_mode_array->{"WT008EA024"}="TE_008EA"; #CTI mixed
    $si_mode_array->{"WT00452024"}="HIE_0002"; #HRC-I event histogram
    $si_mode_array->{"WT00452024"}="HIO_0002"; #HRC-I event histogram
    $si_mode_array->{"WT00DAA014"}="H2C_0002"; #HRC-I event histogram
    $si_mode_array->{"WT0023C024"}="HSE_0002"; #HRC-S event histogram (windows)
    $si_mode_array->{"WT0023A024"}="HSO_0002"; #HRC-S event histogram (windows)
    $si_mode_array->{"WT000B5024"}="TN_000B4"; #TN_000B4B raw mode I0-I3,S2,S3
    $si_mode_array->{"WT000B7024"}="TN_000B6"; #TN_000B6B raw mode S0-S5
    $si_mode_array->{"WT00549034"}="TN_00548"; #CHARGE INJECTION
    $si_mode_array->{"WT0054B034"}="TN_0054B"; #CHARGE INJECTION
    $si_mode_array->{"WT0054D034"}="TN_0054C"; #CHARGE INJECTION
    $si_mode_array->{"WT006C2024"}="TE_006C2";#Focal Plane cooling test 
    $si_mode_array->{"WT007AC024"}="TE_007AC"; #ACIS-I, all but g255
    $si_mode_array->{"WT007AE024"}="TE_007AE"; #ACIS-S, all but g255
    $si_mode_array->{"WC000C4024"}="CC_000C4"; #ACIS-S, all but g255 CC
    $si_mode_array->{"WC000C6024"}="CC_000C6"; #ACIS-I, all but g255 CC

    #---
    #alternating exp mode to calibrate particle background
    #correction 4.0/3.2s frametimes, I0-I3,S2,S3
    $si_mode_array->{"WT0031D024"}="TE_0031C";
    $si_mode_array->{"WT0031C024"}="TE_0031C";
    #---
    #alternating exp mode to calibrate particle background
    #correction 2.0/3.2s frametimes,  I0-I3,S3
    $si_mode_array->{"WT00681024"}="TE_00680";
    $si_mode_array->{"WT00680024"}="TE_00680";
    #---
    #alternating exp mode to calibrate particle background
    #correction 2.5/3.2s frametimes,  I0-I3,S3
    $si_mode_array->{"WT00683024"}="TE_00682";
    $si_mode_array->{"WT00682024"}="TE_00682";
    #---
    #alternating exp mode to calibrate particle background
    #correction 3.0/3.2s frametimes,  I0-I3,S3
    #---
    $si_mode_array->{"WT00685024"}="TE_00684";
    $si_mode_array->{"WT00684024"}="TE_00684";
    #---
    #alternating exp mode to calibrate particle background
    #correction 3.5/3.2s frametimes,  I0-I3,S3
    $si_mode_array->{"WT00687024"}="TE_00686";
    $si_mode_array->{"WT00686024"}="TE_00686";
    #---
    #alternating exp mode to calibrate particle background
    #correction 4.0/3.2s frametimes,  I0-I3,S3
    $si_mode_array->{"WT00689024"}="TE_00688";
    $si_mode_array->{"WT00688024"}="TE_00688";
    #---
    #alternating exp mode to calibrate particle background
    #correction 1.5/3.2s frametimes,  I0-I3,S3
    #---
    $si_mode_array->{"WT0068F024"}="TE_0068E";
    $si_mode_array->{"WT0068E024"}="TE_0068E";

    return;
}
#--------------------------------------------------------------------
#open_files: subroutine to open all files and to make the code easier 
#            to read
#--------------------------------------------------------------------
sub open_files{
    my($fileh,$filename)=(@_);
    open ($fileh,$filename)  or die "ERROR!\nCould not OPEN $filename; file not created!\nUSAGE: acis-backstop.pl {current_week_path/*.backstop} {preceding_week_path/ACIS-History.txt}\n";
    return;
}

#--------------------------------------------------------------------
# read_history: subroutine to read the history file and return 
#               a hash with the items
#--------------------------------------------------------------------
sub read_history{
    my($hist_file,$histref)=(@_);

$histind = 0;

open_files(HIST,$hist_file);
while ($line = <HIST>) {
    if($line =~ 'CHANDRA'){
	#instead of an index, find the line that matches CHANDRA 
	chop($line);
	$histline=$line;
    }
}
close(HIST);

$delim=",";
$where=index($histline,'(');

if($where != -1){
    $histline=substr($histline,$where,120);
    $histline=~s/\(//;
    $histline=~s/\)//;
}
else{die "ERROR!\n Improper format in History File:$hist_file\n";}

$histline=~s/\(//;
$histline=~s/\)//;
@words=quotewords($delim,$keep,$histline);

    $$histref{"FPSI"}  = $words[0];
    $$histref{"HETG"}  = $words[1];
    $$histref{"LETG"}  = $words[2];
    $$histref{"OBSID"} = $words[3];
    $$histref{"radmonstatus"} = $words[4];
    $$histref{"FMT"} = $words[5];
    $$histref{"DITH"} = $words[6];
#parse out the stored values on board.
    $$histref{"WTval"} = $words[7];
    $$histref{"WCval"} = $words[8];
    $$histref{"W2val"} = $words[9];
    $$histref{"W1val"} = $words[10];
    $$histref{"last_simode"} = $words[11];
    close(HIST);

  return
}#--------------------------------------------------------------------
# read_perigee: subroutine to read the perigee file and return 
#               a hash with the items
#--------------------------------------------------------------------
sub read_perigee{
    my($backstop_file,$hist_file,$periref)=(@_);

    #parse out directory from history file add on perigee file name
    $dirname  = dirname($hist_file);
    $peri_file="${dirname}/ACIS-Perigee.txt";
    $curdirnam= dirname($backstop_file);
    
    $periind = 0;

    #in the case of an interrupt, the Perigee edit file will exist
    if($dirname eq $curdirnam){
	if( -e "${dirname}/ACIS-Perigee_edit.txt"){
	    $peri_file="${dirname}/ACIS-Perigee_edit.txt";
	}
    }
    print "NOTE: Using $peri_file\n";
    open_files(PERIGEE,$peri_file);
    while ($line = <PERIGEE>) {
	if($line =~ 'CHANDRA'){
	    #instead of an index, find the line that matches CHANDRA 
	    chop($line);
	    $histline=$line;
	}
    }
    close(PERIGEE);

    $delim=",";
    $where=index($histline,'(');
    
    if($where != -1){
	$histline=substr($histline,$where,80);
	$histline=~s/\(//;
	$histline=~s/\)//;
    }
    else{die "ERROR!\n Improper format in Perigee File:$peri_file\n";}
    
    $histline=~s/\(//;
    $histline=~s/\)//;
    @words=quotewords($delim,$keep,$histline);
    
    $$periref{"radtime"}  = $words[0]; # time of last radtime
    $$periref{"offtime"}  = $words[1];  # time of last housing heater OFF
    $$periref{"ontime"}  = $words[2];   # time of last housing heater ON
    $$periref{"TRIPLET"}  = $words[3]; # is radzone triplet set?
    close(PERIGEE);

#set the global values
    if($words[0] != 0.00){
	$radmonoff=parse_time($words[0]);
    }

    if($words[3] =~ /YES/){
	$triplet_check=3;
    }
    
    $htroff=parse_time($words[1]);
    $htron=parse_time($words[2]);
    
    if($htron > $htroff){ #if the heater turn on was AFTER the off
	$dhhtr=1; #the heater is ON
    }

  return
}
#--------------------------------------------------------------------
# Print Status
#--------------------------------------------------------------------
sub print_status{
    my($FILEH,$stat) = (@_);
    $FP=$$stat{"FPSI"};
    $HETG=$$stat{"HETG"};
    $LETG=$$stat{"LETG"};
    $OBSID=$$stat{"OBSID"};
    $RADMON=$$stat{"radmonstatus"};
    $FMT=$$stat{"FMT"};
    $DITH=$$stat{"DITH"};
    print $FILEH "\n====> CHANDRA STATUS ARRAY=($FP,$HETG,$LETG,$OBSID,$RADMON,$FMT,$DITH)\n\n";
    return;
}

#-----------------------------------------------------------------------------------
# Update Status - Update the specified member of the
#                           $chandra_status hash with the specified value
#                           
#------------------------------------------------------------------------------------
sub update_status
{
    # Get the arguments - hash key, new value, the chandra_status hash
    ($key,$val,$stat) = (@_);
    # Update the item
    $$stat{$key}=$val;
    return;
  }
#--------------------------------------------------------------------
# update_history_files: Update the history files
#--------------------------------------------------------------------
sub update_history_files{
     my($FILEH,$stat) = (@_);
     $FP=$$stat{"FPSI"};
     $HETG=$$stat{"HETG"};
     $LETG=$$stat{"LETG"};
     $OBSID=$$stat{"OBSID"};
     $RADMON=$$stat{"radmonstatus"};
     $FMT=$$stat{"FMT"};
     $DITH=$$stat{"DITH"};
     $W2val=$$stat{"W2val"};
     $W1val=$$stat{"W1val"};
     $WTval=$$stat{"WTval"};
     $WCval=$$stat{"WCval"};
   SWITCH:{
       if ($FILEH =~ /FP/){
	   printf FPHIST "%15s\t%8s\t%6.0f\n",$fields[0],$FP,$OBSID;
	   last SWITCH;
       }	 
       if ($FILEH =~ /GRAT/){
	   printf GRATHIST "%15s\t%8s\t%8s\t%6.0f\n",$fields[0],$HETG,
	                  $LETG,$OBSID;
	   last SWITCH;
       }
       if ($FILEH =~ /TLM/){
	   printf TLMHIST "%15s\tCOMMAND_HW\t%10s\n",$fields[0],$FMT;
	   last SWITCH;
       }
       
       if ($FILEH =~ /OBSID/){
	   printf OBSIDHIST "%15s\tMP_OBSID\t%9s\n",$fields[0],$OBSID;
	   last SWITCH;
       }
       if ($FILEH =~ /DITH/){
	   printf DITHHIST "%15s\tCOMMAND_SW\t%10s\n",$fields[0],$DITH;
	   last SWITCH;
       }
	   ;
       if ($FILEH =~/HIST_OUT/){
	   printf HIST_OUT "%15s====> CHANDRA STATUS ARRAY AT LOAD END = ($FP,$HETG,$LETG,$OBSID,$RADMON,$FMT,$DITH,$WTval,$WCval,$W2val,$W1val,$last_simode)\n\n",$fields[0];
	   last SWITCH;
       }
       if($FILEH =~ /LR/){
	   print LR  "CHANDRA STATUS ARRAY AT START OF LOAD REVIEW (FROM PREVIOUS LOAD HISTORY FILE):\n";
	   print LR "(FP SI,HETG status,LETG status,current OBSID,RadMon status,current TLM FMT,Dither)\n";
	   print LR "\t\t = ($FP,$HETG,$LETG,$OBSID,$RADMON,$FMT,$DITH)\n\n";
	   last SWITCH;
       }
       # Can't do these on Filehandle
       if ($FILEH =~ /W2val/){
	   printf STOREHIST "%15s\tCOMMAND_SW\t%10s\n",$fields[0],$W2val;
	   last SWITCH;
       }
        if ($FILEH =~ /W1val/){
	   printf STOREHIST "%15s\tCOMMAND_SW\t%10s\n",$fields[0],$W1val;
	   last SWITCH;
       }
       if ($FILEH =~ /WTval/){
	   printf STOREHIST "%15s\tCOMMAND_SW\t%10s\n",$fields[0],$WTval;
	   last SWITCH;
       }
        if ($FILEH =~ /WCval/){
	   printf STOREHIST "%15s\tCOMMAND_SW\t%10s\n",$fields[0],$WCval;
	   last SWITCH;
       }
       die "Error: Do not recognize $FILEH\n";
   }
     return;
 }
#--------------------------------------------------------------------
#Update Perigee History: record the last radmon off. heater times and
#                        if the triplet was recorded
#--------------------------------------------------------------------
sub update_perigee_history{
    my($FILEH,$perigee_stat)= @_;
    $raddis=$$perigee_stat{radtime};
    $htroff=$$perigee_stat{offtime};  # time of last housing heater OFF
    $htron=$$perigee_stat{ontime};
    $trip="NO";
    if($triplet_check == 3){
	$trip = "YES";
    }
    printf $FILEH  "load end ====> (radmon disab time, dhhtr off time, dhhtr on time, rad zone triplet)\n";
    printf $FILEH  "%15s====> CHANDRA PERIGEE INFO AT LOAD END = ($raddis,$htroff,$htron,$trip)\n\n",$fields[0]; 
    
    return;
}


#--------------------------------------------------------------------
#read_CRM_file: Read the CRM file and store the information in an
#               array of hashrefs...
#--------------------------------------------------------------------
sub read_CRM_file{
  my($filename,$crm_list)= @_;
  open (CRMPAD, "$filename") || warn "Warning! Cannot open CRM $file!";
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
		@line = split (/\s+/, $_);
		$size=@line;
		#print "Size is $size\n @line\n";
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
			if ($key =~ m/adj E/ || $key =~ /AE/){
			    $crm_event_time1=$list{$key};
			}
		    }
		    if($key =~ m/PAD/){
		        $padd=$list{$key}/86400.;
		    }
		}

     
		if(length($si_mode) < 8){ #empty
		    foreach $l (@line){
			if($l =~ m/[A-Z]{2}_[A-Z|0-9]{5}/){
			    $si_mode=$l;
			    last;
			}
		    }
		}
		
					

	       	my @crm_event_time = split(":",$crm_event_time1);
		my $crm_ae_time = $crm_event_time[1] + $crm_event_time[2]/24 + 
		    $crm_event_time[3]/1440 + $crm_event_time[4]/86400;
		my $time_str=sprintf("%03d:%02d:%02d:%02d\n",$crm_event_time[1],
				     $crm_event_time[2],$crm_event_time[3],
				     $crm_event_time[4]);
	      
		
		%event_item=(
			     event=>$crm_event,
			     time=>$crm_ae_time,
			     pad=>$padd,
			     SI=>$si_mode,
			     string=>$time_str,
			     );
		
		
		push(@crm_array,\%event_item);
		$si_mode='';
	    } #if
	}
    } #while
#       DEBUG--Keep this commented for debugging purposes
  #foreach $item (@crm_array){
  #    print "Event=$$item{event} at $$item{time} with SI of $$item{SI}\n";
  #}
  close(CRMPAD);
}
#--------------------------------------------------------------------
# read_NIL_file :read records from NIL file
#--------------------------------------------------------------------
sub read_NIL_file{
  my($filename,$nil_list)= @_;
  $flag=0;		# flag a record
  open (NIL_ER, "$filename") || print "There are no NIL observations scheduled for this load.\n";
  while (<NIL_ER>){
      
      if($_ =~ /,ID=/ && 	# found a record
	 $_ !~ /COMMENT/){      #ignore the comments
	  my %nil_item;
	  my @row = split (/=/, $_);
	  my @val=split(/,/,$row[1]);
	  $id=trim($val[0]);
	  $foo=<NIL_ER>;
	  @row = split (/=/, $foo);
	  @val=split(/,/,$row[1]);
	  $inst=trim($val[0]);
	  $foo=<NIL_ER>;
	  @row = split (/=/, $foo);
	  @val=split(/,/,$row[1]);
	  $simode=trim($val[0]);
	  
	  #remove C, replace with 0
	  #if not 09, add 10000 to 
	  #get obsids for cycle 10 and up
	  $id =~ s/^C/0/;
	  if($id !~ m/^09/){
	      $id=10000+$id;
	  }

	  %nil_item=( id=>$id,
		       inst=>$inst,
		       simode=>$simode,
		       );
          push(@$nil_list,\%nil_item);
      }
	  
  }  #while
  close(CRMPAD);
}

#--------------------------------------------------------------------
# process_comm: record the comm start and stop
#--------------------------------------------------------------------
sub process_comm{
#NOte this only reports the antena on, not the actual comm
    $lastCmdAcisFlag=0;
    if($Rec_Eventdata{TLMSID} eq "CTXAON" ||
       $Rec_Eventdata{TLMSID} eq "CTXBON") {
	$loc_time = str_to_loc_time($fields[0]);
	printf LR "\n%15s\tREAL-TIME COMM BEGINS\t%19s\n\n",
	$fields[0], $loc_time;
	$commstart=$dec_day;
	$commflag=1;
	$start_comm=$start_comm+1;
    }
    
    if ($commflag == 1 && 
	($Rec_Eventdata{TLMSID} eq "CTXAOF" ||
	 $Rec_Eventdata{TLMSID} eq "CTXBOF")) {
	$loc_time = str_to_loc_time($fields[0]);
	printf LR "\n%15s\tREAL-TIME COMM ENDS\t%19s\n\n",
	$fields[0], $loc_time;
	$commend=$dec_day;
	$stop_comm=$stop_comm+1;
	$commspan=($commend-$commstart)*1440;
	if ($commspan < 100000) {
	    printf LR "  ==> COMM DURATION: %6.2f mins.\n\n",$commspan;
	}
	$commflag=0;
    }  
	
}#end sub

#--------------------------------------------------------------------
# str_to_loc_time: Convert Zulu yyyy:ddd:hh:mm:ss.sss to local time
#--------------------------------------------------------------------
sub str_to_loc_time {
    my($zulu_str) = (@_);
    my $hour;
    @zulu= split(":", $zulu_str);
    ($yr, $month, $day) = 
	Add_Delta_Days($zulu[0],1,1, $zulu[1] - 1);
    
    $time = timelocal(0.0 + $zulu[4], 0 + $zulu[3], 0 + $zulu[2],
		      $day, $month - 1, $yr);
    
    @time_str = localtime($time);
    $isDaylight = $time_str[8];
    $deltaHours = 5;
    $zoneTag= "EST";
    if ($isDaylight) { 
	$deltaHours = 4;
	$zoneTag = "EDT";
    }
# From Date::Calc
#  Add_Delta_DHMS
    ($year,$month,$day, $hour,$min,$sec) =
	Add_Delta_DHMS($yr,$month,$day, 
		       0 + $zulu[2],
		       0 + $zulu[3],
		       0 + $zulu[4],
		       0, -$deltaHours, 0, 0);
    $local_doy = $zulu[1];
     if (24 - $hour < $deltaHours) {
	$local_doy = $zulu[1] - 1;
    }
    $hr_str = "$hour";
    if ($hour < 10) {
	$hr_str = "0$hr_str"
    }
    return "$year:$local_doy:$hr_str:$zulu[3]:$zulu[4] $zoneTag\n";
}

#--------------------------------------------------------------------
# process_TG: Process any HETG and LETG commands
#--------------------------------------------------------------------
sub process_TG{
     my($stat) = (@_);

     printf LR "%15s%10s%12s%10s\n\n",$fields[0],$Rec_VCDU,
                $Rec_Event,$Rec_Eventdata{TLMSID};
     #get Current Values
     $LETG=$$stat{"LETG"};
     $HETG=$$stat{"HETG"};
     $OBSID=$$stat{"OBSID"};
     #In each case, choose if the sim trans or the start sci w/ bias is longer.
     if ($startsciflag == 1){
	 $tstart=($dec_day >= $tstart)?$dec_day: $tstart;
	 $calstarttime=$fields[0];
     }
     $lastCmdAcisFlag=0; #reset acis cmd flag
   SWITCH:{
       if ($Rec_Eventdata{TLMSID} eq "4OLETGIN") {
	   $LETG="LETG-IN";  
	   $letg_in_cnt=$letg_in_cnt+1;
	   last SWITCH;
       }
       if ($Rec_Eventdata{TLMSID} eq "4OLETGRE") {
	   $LETG="LETG-OUT";
	   $letg_out_cnt=$letg_out_cnt+1;
	   last SWITCH;
       }
       if ($Rec_Eventdata{TLMSID} eq "4OHETGIN") {
	   $HETG="HETG-IN";
	   $hetg_in_cnt=$hetg_in_cnt+1;
	   last SWITCH;
       }
       if ($Rec_Eventdata{TLMSID} eq "4OHETGRE") {
	   $HETG="HETG-OUT";
	   $hetg_out_cnt=$hetg_out_cnt+1;
	   last SWITCH;
       }
       $nothing=1;
   }
     #Update the Chandra Status Array
     update_status("HETG",$HETG,$stat);
     update_status("LETG",$LETG,$stat);
     #Write to the Grating History file
     update_history_files(GRATHIST,\%chandra_status);
#     printf GRATHIST "%15s\t%8s\t%8s\t%6.0f\n",$fields[0],$HETG,$LETG,$OBSID;  

}#end sub
#--------------------------------------------------------------------
# process_dither: read and report the dither status
#--------------------------------------------------------------------
sub process_dither{ 
    my($stat)=(@_);
    
    printf LR "%15s%10s%9s%10s\n",$fields[0],$Rec_VCDU,$Rec_Eventdata{TLMSID},
           $Rec_Eventdata{MSID};
    $lastCmdAcisFlag=0; #reset ACIS Cmd flag
    if($Rec_Eventdata{TLMSID} eq "AOENDITH"){
	printf LR "  ==> DITHER ENABLED\n\n";
	$DITH = "ENAB";
    }
    else{
	printf LR "  ==> DITHER DISABLED\n\n";
	$DITH = "DISA";
    }
    
    update_status("DITH",$DITH,$stat);
    update_history_files(DITHHIST,\%chandra_status);
#    printf DITHHIST "%15s\tCOMMAND_SW\t%10s\n",$fields[0],$DITH;
} # END PROCESS_DITHER

#--------------------------------------------------------------------
# process_radmon: read and record the radmon status
#--------------------------------------------------------------------
sub process_radmon{ 
    my($stat,$perigee_stat,@crm_list)=(@_);
   
    printf LR  "%15s%10s%12s%9s\n\n",$fields[0],$Rec_VCDU,$Rec_Event,
                $Rec_Eventdata{TLMSID};
    $lastCmdAcisFlag=0; #reset the acis cmd flag
     #get Current Value of SI instrument
     $FP=$$stat{"FPSI"};

    # Confirm that the HRC-S is in the focal plane
    if($Rec_Eventdata{TLMSID} eq "OORMPDS")
      {
	$radmonoff=$dec_day;
	$$perigee_stat{radtime}=$fields[0];
	$ctifmtcheck=1;
	if ($FP ne "HRC-S")
	  {
	    print LR  ">>> ERROR: ABOUT TO ENTER THE BELTS! NO SIM TRANSLATION YET!\n    FOCAL PLANE INSTRUMENT is $FP\n\n";
	    add_error("o. RadMon was disabled prior to radbelt transit but we were NOT at HRC-S yet.\n\n");
	  }
	$ocat_simode=find_radzone_simode($Rec_Eventdata{TLMSID},$dec_day,
					 @crm_list);
	print LR "\n==>The requested SI_MODE for the inbound CTI is $ocat_simode\n\n";
	$cti_flag=1;
	#$$perigee_stat{"radtime"}="000"; WHY IS THIS IN HERE?????
      }
    
    #ENABLED
    if ($Rec_Eventdata{TLMSID} eq "OORMPEN") {
	$$perigee_stat{"radtime"}=$fields[0];
	$ctifmtcheck=0;
	$radmonon=$dec_day;
	$pad2=($radmonon-$elec1exit)*86.4;
	printf LR "  ==> Exit leg pad time is %5.2f ks.\n\n",$pad2;
	
	pad_check($Rec_Eventdata{TLMSID},$radmonon,$pad2,
		  $elec1exit,@crm_list);
	
	#Check the science status
	if($cti_flag == 1)
	  {
	    #Is science running
	      if($startsciflag == 0)
	        { #check the timing
    		   $cti_flag=0;	# science run is done, CTI is done
    		   $radstop_diff=($radmonon - $stopscitime)*1440.; #in min
    		   if($radstop_diff >= 3.25)
    		     { # 3.25 minutes
    			printf LR "\n>>>ERROR: RADMON occurs %5.2f min AFTER stop science.\n\n",$radstop_diff;
    			add_error("o. RADMON occured more than 3.25 minutes AFTER stop science.\n\n");
    		     }
  	      } # END if $startsciflag == 0, science is still RUNNING! don't clear CTI flag
	  } # END  if($cti_flag == 1)

	# Old heater info, keep for now
	$htroff=parse_time($$perigee_stat{offtime});
	$htron=parse_time($$perigee_stat{ontime});
	$htr_diff=($htron-$htroff)*86.4;

	#$radmonon=0;
	$elec1exit=0;
	if ($pad2 > 15.0) {
	    print LR "\n>>>ERROR: RadMon EN occurs well after an E1 exit (>15ks).\n";
	    print LR "    -OR-  RadMon EN encountered prior to a XE1RADZ0/XEF1000.\n\n";
	    add_error("o. Either Radmon was NOT ENABLED at least 15 ks after an electron 1 exit.\n");
	    add_error("   -OR- Radmon was NOT enabled after electron 1 exit.\n\n");
	}
    }
    
     update_status("radmonstatus",$Rec_Eventdata{TLMSID},$stat);
} # END PROCESS_RADMON

#--------------------------------------------------------------------
# process_format: read format, report errors if a change
#                 happens too soon
#--------------------------------------------------------------------
sub process_format{ 
    my($stat)=(@_);

    printf LR "%15s%10s%12s%10s\n\n",$fields[0],$Rec_VCDU,$Rec_Event,
            $Rec_Eventdata{TLMSID};
    printf TLMHIST "%15s\t%10s\t%10s\n",$fields[0],$Rec_Event,
	$Rec_Eventdata{TLMSID};

    
    $oldFMT=$$stat{"FMT"};
    update_status("FMT",$Rec_Eventdata{TLMSID},$stat);
    $FMT=$Rec_Eventdata{TLMSID};
    $lastCmdAcisFlag=0; #reset last acis cmd flag
    #------------------------------------------
    #Check if we are in an observation
    # and to make sure we can clear the buffers
    #------------------------------------------ 
    $old_fmt=$fmt_change;
    $fmt_change=$dec_day;
    
    $checktime = ($fmt_change - $stopscitime)*1440; #convert time to minutes
    if($checktime < 2.999 &&
       $bitscleared < 0.0){ #less than clear buffer time for FMT2
	if($oldFMT eq "CSELFMT2"){
	    $rate=24.0; #24.0 kbits/sec
	}
	elsif($oldFMT eq "CSELFMT1"){
	    $rate=0.5; #0.5 kbits/sec;	
	    printf LR ">>>ERROR: SWITCH TO FMT1 OCCURS %6.2f MINS AFTER A STOPSCI!\n\n",$checktime;
	    add_error("o. There is a change to FMT1 less than 3 mins after an ACIS stop science.\n\n");
	}
	else{
	    $rate=0.0; #no telemetery in other formats;
	}
	$bitscleared=$bitscleared-($rate*($checktime*60.)) 
	}
#Check we are not in an observation
    if ($FMT ne "CSELFMT2" &&
	$startsciflag == 1) {
	print LR ">>>ERROR: CHANGE FROM FMT2 OCCURS BEFORE A STOP SCIENCE!\n\n";
	add_error("o. There is a change from FMT2 before an ACIS stop science.\n\n");
    }
} # END PROCESS_FORMAT

#--------------------------------------------------------------------
# process_radzone: Record items for the radzone
#--------------------------------------------------------------------
sub process_radzone{
    my(@crm_list,$stat)=@_;
    #Note, need a way to deal with missing entries
    printf LR "%15s%10s%10s%11s\n",$fields[0],$Rec_VCDU,$Rec_Event,$Rec_Eventdata{TYPE};
   
    $FP=$chandra_status{"FPSI"};
    $lastCmdAcisFlag=0; #reset last cmd acis flag

    # If the command is EPERIGEE, process it.
    if ($Rec_Eventdata{TYPE} eq "EPERIGEE")
      {
	$perevt=$dec_day;
	$entrydelta=($perevt-$EE1evt)*24;
	if($enter_rad == 0)
	  {
	    print LR "\n>>>WARNING: No EEF1000 seen before EPERIGEE. Is the load starting in the belts?\n";
	    $enter_rad = 1; #by definition, in the rad zone
    	  }
	if ($entrydelta < 3.98)
	  { #Switch to 4 hours with a 1.2 min buffer
	    print LR "\n>>>ERROR: Time delta between EE1RADZ0/EEF1000 and EPERIGEE is less than 4.0 hrs.\n\n";
  	  }

	if($triplet_check != 3)
	  {
	    print LR "\n>>>ERROR: The radzone ACIS commanding triplet was not seen\n\n";
	    add_error("o. The radzone ACIS commanding triplet was not seen.\n\n");
	  };
	$triplet_check = 0;#reset
	#NEED TO CLEAN THIS UP
	$perigee_cnt=$perigee_cnt+1;
	$perigee_time=$dec_day;
     
	$checkWStime = ($per_vidalldn - $per_oldstopsci)*1440;
	
	if ($checkWStime > 10.0)
	  {
	      printf LR ">>>ERROR: Time delta between the last WSVIDALLDN and the 2nd last AA00000000 is greater than 10.0 mins!\n\n";
	      add_error("o. Time difference between a WSVIDALLDN command and the 2nd AA00000000 that precedes it is greater than 10 mins.\n\n");
            }	
	
      } # END ($Rec_Eventdata{TYPE} eq "EPERIGEE")

    # EEF1000 or EE1RADZ0 - process this command.
    if (($Rec_Eventdata{TYPE} eq "EE1RADZ0" ||
	 $Rec_Eventdata{TYPE} eq "EEF1000") &&
	 $enter_rad == 0 ){
	$enter_rad=1;
	$elec1ent=$dec_day;
	$EE1evt=$dec_day;
	$NILpad=($elec1ent-$hrcStime)*86.4;
	
	$simtest1=$dec_day;
	$pad=($elec1ent-$radmonoff)*86.4;
	
	if ($NILpad < $pad) {
	    print LR   "\n>>>ERROR: SIM translation occurs during the pad/CTI time.\n\n";
	    add_error("o. There is a SIM translation during the entry leg pad time of a rad transit.\n\n");
	}
	    
	if ($FP ne "HRC-S") {
	    print LR ">>> **MAJOR ERROR**: ABOUT TO ENTER THE BELTS! NO SIM TRANSLATION YET!\n\n";
	    print LR ">>> **MAJOR ERROR**: ABOUT TO ENTER THE BELTS! NO SIM TRANSLATION YET!\n\n";
	    print LR ">>> **MAJOR ERROR**: ABOUT TO ENTER THE BELTS! NO SIM TRANSLATION YET!\n\n";	 
	    add_error("o. Entered the belts with ACIS in the focal plane.\n\n");
	}  
	
	
	printf LR  "\n  ==> Entry leg pad time is %5.2f ks.\n\n",$pad;
	pad_check($Rec_Eventdata{TYPE},$radmonoff,$pad,$elec1ent,@crm_list);
	    
	$elec1ent=0;
	#$radmonoff=0;
	if ($pad > 15.0) {
	    print LR "\n>>>ERROR: RadMon DS occurs well before E1 entry (>15 ks).\n";
	    print LR "    -OR-  EE1RADZ0/EEF1000 encountered prior to a RadMon DS.\n";
	    print LR "    -OR-  EE1RADZ0/EEF1000 occurs very close to EPERIGEE.\n";
	    print LR "    -OR-  MULTIPLE EE1RADZ0/EEF1000 XE1RADZ0/XEF1000 entries encountered.\n\n"; 
	    add_error("o. Either Radmon is DISABLED at least 15 ks before electron 1 entry.\n");
	    add_error("   -OR- Radmon was NOT disabled before electron 1 entry.\n\n");
		}
    }
    
    #note, by requiring perigee, we are forcing 
    # the mid-radzone loads to be wrong

    # XEF1000 - process this command
    if (($Rec_Eventdata{TYPE} eq "XE1RADZ0" ||
	 $Rec_Eventdata{TYPE} eq "XEF1000"))
    {
	$elec1exit=$dec_day;#set this exit everytime...deals with missed perigees.
	if($perevt != 0.0)
	  { #we've seen perigee
		$elec1exit=$dec_day;
		$simtest2=$dec_day;
		if ($simtrans > $simtest1 and $simtrans < $simtest2)
		  {
		    print LR "\n>>>ERROR: SIM translation occurs during perigee transit.\n";
		    print LR "    -OR- EE1RADZ0/EEF1000 is missing for this orbit.\n\n"; 
		    add_error("o. There is a SIM translation during rad zone transit.\n");
		    add_error("   -OR- EE1RADZ0/EF1000 was missing for an orbit. \n\n");
		    
		  }
		$ocat_simode=find_radzone_simode($Rec_Eventdata{TYPE},
						 $dec_day,@crm_list);
		print LR "\n==> The requested SI_MODE for the outbound CTI is ${ocat_simode}\n\n";
		$cti_flag=1;
		$exitdelta=($elec1exit-$perevt)*24;
		
		if ($exitdelta < 3.25 )
		  {
		    print LR "\n>>>ERROR: Time delta between XE1RADZ0/XEF1000 and EPERIGEE is less than 3.25 hrs.\n\n";
	  	  }
		$perevt=0.0;
		$enter_rad=0;
	  } # END if($perevt != 0.0)
      } # END IF XEF1000 command
	    	
    } # END SUBROUTINE process_radzone.
#--------------------------------------------------------------------
# Process_sim : Process all SIM translations and Focus
#--------------------------------------------------------------------
sub process_sim{
    my($stat)=(@_);
    $lastCmdAcisFlag=0; #reset acis cmd flag
    $OBSID=$$stat{"OBSID"};
    if ($Rec_Event eq "SIMTRANS") {
	$old_SI=$$stat{"FPSI"};
	$simtrans=$dec_day;
        if ($startsciflag == 1) {      
	    #choose if the sim trans or the start sci w/ bias longer.
	    #Warning...bug here for EVENT histograms
	    $tstart=($dec_day >= $tstart) ? $dec_day : $tstart;
            $calstarttime=$fields[0];
	}    
	$position=$Rec_Eventdata{POS};
	if ($position > 70000 && $position < 82000) {
	    $SI2="ACIS-S"; 
	    $nom_zsim = 75624;
	    $delta_zsim = ($position - $nom_zsim)/397.67;
	}
	elsif ($position > 82001) {   
	    $SI2="ACIS-I";
	    $nom_zsim = 92904;
	    $delta_zsim = ($position - $nom_zsim)/397.67;
        }
        elsif ($position < -20000 && $position > -78000) {
	    $SI2="HRC-I";
        }
        elsif ($position < -78001) {
	    $SI2="HRC-S";
	    $hrcStime=$dec_day;
        }	
	else{
	    printf LR "\n ==> SIM is in an unusual position. Please check SIM location.\n\n";
	}
	#Not sure if we can protect against ACIS undercover observations.
	update_status("FPSI",$SI2,$stat);
	update_history_files(FPHIST,\%chandra_status);
	printf SIMTSC "%15s\t%10s\t%10s\n",$fields[0],$Rec_Event,$position;
	
	# Two commands here to deal with spacing
	unless($SI2 =~ /HRC/){
	    printf LR "%15s%10s%10s%9s  (%6s)\n",$fields[0],$Rec_VCDU,$Rec_Event,$position,$SI2;
	    printf LR "\n  ==> THERE IS A Z-SIM OF %5.2f mm FOR THIS OBSERVATION.\n\n",$delta_zsim;        
	    #check if radmon is enabled
	    $RADMON=$$stat{"radmonstatus"};
	    if ($RADMON =~ /DS/){
		printf LR "\n>>>ERROR: SIM TRANSLATION TO %s WHILE RADMON IS DISABLED!\n",$SI2;
		add_error("o. A SIM Translation to ACIS occurs while RADMON is DISABLED.\n\n");
	    }
	}
	else{
	    printf LR "%15s%10s%10s%9s   (%5s)\n",$fields[0],$Rec_VCDU,$Rec_Event,$position,$SI2;
	}
	#Why reset these?
	$sim_z = $delta_zsim;
	$delta_zsim = 0;
	
	#Confirm that the SIM Translation happens within the first 60 minutes of an observation??? WHY 60????
	if ($startsciflag == 1) {
	    $stopscitime=($dec_day-$startscitime)*1440;
	    if ($stopscitime > 60) {
		if ($SI2 =~ /HRC/ &&
		    $old_SI =~ /HRC/){
		    printf LR ">>>WARNING: There is a SIM translation from %s to %s %6.2f minutes AFTER an ACIS start science\n            Confirm this is a NIL test\n\n",$old_SI,$SI2,$stopscitime;
		}
		else{
		    printf LR "\n>>>ERROR: SIM TRANSLATION OCCURS %6.2f minutes AFTER A START SCIENCE.\n\n",$stopscitime;
		    #$Test_Passed = 0;
		    add_error("o. There is a SIM translation that occurs DURING an ACIS science run.\n\n");
		}
	    }
        }
    }
    #Do we want a check on the SIM Focus? Yes, what are the values?
    if ($Rec_Event eq "SIMFOCUS") {
	printf LR "%15s%10s%10s%9s\n\n",$fields[0],$Rec_VCDU,$Rec_Event,$Rec_Eventdata{POS};
	if ($startsciflag == 1) {      
	    #choose if the sim trans or the start sci w/ bias is longer.
	    $tstart=($dec_day >= $tstart)?$dec_day: $tstart;
	    $calstarttime=$fields[0];
	}
	if($Rec_Eventdata{POS} > -400 ||
	   $Rec_Eventdata{POS} < -1100){
	    printf LR "\n>>>ERROR: SIM FOCUS POSITION IS BEYOND THE RANGE OF -400 to -1100. Please confirm SIM FOCUS.\n";
	    add_error("o. There is a SIM FOCUS that extends beyond the accepted range.\n\n");
	}
    }
   

    return($sim_z);
} # END PROCESS_SIM

#--------------------------------------------------------------------
# obsid_change: record and set obsid, collect information from ocat
#              input:  chandra_status array
#--------------------------------------------------------------------
sub obsid_change{
    my($stat)=(@_);
    
    printf LR "%15s%10s%10s%9s\n\n",$fields[0],$Rec_VCDU,$Rec_Event,
	$Rec_Eventdata{ID};
    # Set the obsid variable to the OBSID specified in the MP_OBSID load command
    $obsid=$Rec_Eventdata{ID};

    # Update $chandra_status with the obsid
    update_status("OBSID",$obsid,$stat);

    # Update the indicated history file with the appropriate member of the
    # $chanda_status hash
    update_history_files(OBSIDHIST,$stat);
    
    $lastCmdAcisFlag=0; #reset ACIS last cmd flag 

    $obsid_cnt=$obsid_cnt+1;
    $obsend=$dec_day;
    $delobs=($obsend-$obsstart)*1440; #in minutes
    
    # Calculate the time delta between the obsid change and the time of the first stop science
    # command after a start science
    $obsid_change_date = $fields[0];
    $obsid_change_time = parse_time($obsid_change_date);
    
    $three_min_check_delta_t = ($obsid_change_time  -  $first_stop_science_time) * 1440.0;

    $delstart=($obsend-$startscitime)*1440.;  # 1440 minutes in a day
    $late_change_time=($dec_day-$startscitime)*1440.; #obsid changes after startsci
    #------------------------------
    #Check timing issues
    #------------------------------
    if ($delobs < 100)
       { #why 100?
	printf LR "  ==> ObsID change occurs %3.1f minutes after stop science.\n\n",$delobs
       }

    if ($three_min_check_delta_t < 2.999999999 && $science_running_flag == 0 && $first_stop_science_time != -1 && $last_pblock_loaded != "WT00DAA014")
    {
	# Now clear out the $first_stop_science_time and date
	$first_stop_science_time = -1;
	$first_stop_science_date = "1998";
	print LR ">>>ERROR: ObsID change occurs less than 3 minutes after a stop science command.\n\n";
	add_error("o. The OBSID change to $obsid that occurs less than 3 mins after a stop science.\n\n");
    }

    # Clear out observation start and end times
    $obsend=0;
    $obsstart=0;
    
    if($check_acis_sci == 1 && ( !(($obsid >= $min_cti_obsid) && ($obsid <= $max_special_obsid)) ) )
      {
	#We expect the 60000-50000 series to change often
	print LR ">>>ERROR: There is not an ACIS start science command between this obsid and the previous obsid.\n\n";
	add_error("o. There is an ACIS observation that is missing a start science.\n\n");
	$check_acis_sci = 0;
      }

    if(($startsciflag == 1 && $late_change_time > 5.00) && ($last_pblock_loaded != "WT00DAA014") &&
      ( !(($obsid >= $min_cti_obsid) && ($obsid <= $max_special_obsid)) ))
       {
 	 print LR ">>>ERROR: The OBSID change to $obsid occurs more than 5 mins after a start science.\n\n";
         add_error("o. The OBSID change to $obsid occurs more than 5 mins after a start science.\n\n");
       }

  
    #------------------------------
    # Now get OCAT info based on the OBSID info
    #First make a temp file to pass into acisparams.csh
    # try new temporary filenames until we get one that didn't already exist
    #------------------------------
    print LR  "LATEST OCAT INFO FOR OBSID $obsid:\n";
    do { $ocatname = tmpnam() }
    until $fh = IO::File->new($ocatname, O_RDWR|O_CREAT|O_EXCL);

    # $ocatinfo is a returned status flag.
    $ocatinfo=acisparams($obsid, $ocatname);
    
    print LR  "\n\n";
    %ocat_entries=(); #clear hash

    # Read the important OCAT entries for that OBSID
    %ocat_entries=read_ocat($ocatname);

    # Set the flag saying you tried to read the OCT entries.
    $inocat = 1;

    # If the read of the OCAT information was sucessful, set the loaded_ocat
    # flag to 1.  
    if($ocatinfo == 0)
      {
	$loaded_ocat = 1;
      }

    #If this is an ACIS obs and if this obsid is NOT an ECS measurement or a test, then we should
    #set a test flag...
    if ($ocatinfo == 0 and (! (($obsid >= $min_cti_obsid) && ($obsid <= $max_special_obsid))) )
       {
 	 $check_acis_sci = 1; 
	 $simode=$ocat_entries{"SI Mode"};
	 $ocat_simode=$simode;
       }
    else
       {
	$check_acis_sci = 0;
       }
    
    #------------------------------
    # check for NIL
    #------------------------------
    #  $ocatinfo eq 2 means HRC observation
    if ($ocatinfo == 2 and (! (($obsid >= $min_cti_obsid) && ($obsid <= $max_special_obsid))) )
    {
	 $ocat_simode=find_NIL_simode($obsid,\@nil_array);
	 if ($ocat_simode =~ /_/)
            {
	    $nil_flag=1;
	    print LR "==> NIL SI_Mode is $ocat_simode\n\n";
	    }
	 else
	 {$nil_flag=0 };
        }  
    else
        {$nil_flag=0};

    # Want to grab the window information  IF ACIS OBSERVATION
    if($ocatinfo == 0 &&
       $ocat_entries{"Window Filter"} =~/Y/i){
	#print window information:
	do { $winname = tmpnam() }
	until $fh = IO::File->new($winname, O_RDWR|O_CREAT|O_EXCL);
	print LR "LATEST OCAT WINDOW INFO FOR OBSID $OBSID:\n";
	
	#Remember that if pblock has an event filter,
	#we need this for the window
	if($ocat_entries{"Event Filter"} =~ /Y/i){
	    #Pull out the event filter information
	    $pblock_ef  = "Y";
	    $pblock_lea = $ocat_entries{"Lower Energy"};
	    $pblock_ear = $ocat_entries{"Range"};
	}
	else{
	    $pblock_ef = "N";
	    $pblock_lea=0.08;
	    $pblock_ear=15.0;
	}
	$wininfo = winparams($obsid,$winname);
	
	@window_ocat_array=read_ocat_win($winname);
	unlink ($winname);
	$loaded_ocat = 1;
    } #end IF ACIS OBSERVATION
   

    unlink($ocatname);
    # If you have processed a START SCIENCE and OCAT data was
    # loaded from the OCAT do a parameter check
    if($startsciflag == 1  && $loaded_ocat == 1)
    {
	parameter_check($stat);
	#$temp=compare_pblock();
	$compare = 1;
       }
} # END OBSID_CHANGE

#--------------------------------------------------------------------
# process_stop_science
#--------------------------------------------------------------------
sub process_stop_science
{
    
    $obsid=$chandra_status{"OBSID"};
    $FP=$chandra_status{"FPSI"};
    $rad=$chandra_status{"radmonstatus"};
    
    printf LR "%15s%10s%9s%15s\n\n",$fields[0],$Rec_VCDU,$Rec_Event,
              $Rec_Eventdata{TLMSID};	     		  
    
    #Special section to deal with radzone
    if($startsciflag != 0)
      {
	#if we have  started science
	$compare = 0; #reset these at the end of the observation only
	$loaded_ocat = 0;
#	$quiet_flag = 0;
      }
    #!done radzone
    $check_acis_sci=0;
    $startsciflag=0;
    $stopscitime = $dec_day;

    # If this is the first Stop Science after a Start Science, then capture the
    # decimal date which will be used for the 3 minute buffer empty check
    if($science_running_flag == 1)
    {
	# Capture the decimal date
	$first_stop_science_time = parse_time($fields[0]);;
        $first_stop_science_date = $fields[0];

	# Set the science runing flag to zero so that the captured date
	# will not be overwritten
	$science_running_flag = 0;
      }
    $per_oldstopsci = $per_stopsci;
    $per_stopsci = $dec_day; 
    $tstop=$dec_day;
    $obsstart=$dec_day;
    $new_start=&manuever_time($tstart,$tstop,\@start_man,\@stop_man);

    # if the manuver doesn't matter...(ie 6xxxx  or 5xxxx observation)
    if ( (($obsid >= $min_cti_obsid) && ($obsid <= $max_special_obsid)) || ($tstart==0) )
       { # Calculate the exposure time in seconds (86.4ksec in a day)
	 $exposure=($tstop-$tstart)*86.4;
	 # Ratio is actual exposure/expected exposure *100
         # It's the percentage calculated and displayed at the end of the obs
         # Set it to a nonsense number INDICATES ECS RUN
	 $ratio=-99.00;
       }
    else
       {
	#add an if not event histogram
	$exposure=($tstop-$new_start)*86.4;
	$expected_expo=$ocat_entries{"Exposure Time"};
        # Set it to 100% which means legal and acceptable exposure time
	if ($expected_expo == 0.0)
           {$ratio=100.0; }
        else   # ELSE calculate the actual ratio
           { $ratio=($exposure/$expected_expo)*100.0;}
       } # END ELSE 

    #ADD a CTI CHECK
    if ($cti_flag == 1 && $rad =~ "OORMPEN")
       {
	 #turned on radmon BEFORE this stop science
	 $cti_flag = 0; 
	 $radstop_diff=($stopscitime-$radmonon)*1440.; #in min
	     if ($radstop_diff >= 3.25)
                { # 3.25 minutes
		  printf LR "\n>>>ERROR: RADMON occurs %5.2f min BEFORE stop science.\n\n",$radstop_diff;
		  add_error("o. RADMON occured more than 3.25 minutes BEFORE stop science.\n\n");
	        }
       } # ENDIF ($cti_flag == 1 && $rad =~ "OORMPEN")
    
    # Hard numbers for $ratio like -99.0 and -100.0 are used to make decisions and avoid
    # recording errors such as the less than 90% exposure time rule.
    if ($exposure < 200.0)
       {
	 printf LR "  ==> ACIS integration time of %5.2f ks.\n\n",$exposure;
 	 if ($ratio ne -99.00)
            {
	      printf LR " This is %5.2f\%% of the requested time.\n\n",$ratio;
	      if ($ratio < 90.00)
                 {
		 print LR "\n  ==>ERROR: Scheduled time is less than 90%.\n\n";
	         }
	      if ($ratio > 110.00)
                 {
	 	 print LR "\n  ==>ERROR: Scheduled time is greater than 110%.\n\n";
		 }

	    } # ENDIF  ($ratio ne -99.00)

 	    # Punctuate end of science run.
            # If this was a science observation.....
            if ($obsid < $min_cti_obsid)
	      {
	        print LR "-@" x 35 . "\n";
	        print LR "-@" x 35 . "\n\n\n";
	      }
            else  # Just finished a CTI measurement 
              {
	       # Punctuate end of CTI run.
	       print LR "-CTI" x 18 . "\n";
	       print LR "-CTI" x 18 . "\n\n\n";
              }

        #set up the rad zone triplet check
	if ( (($obsid >= $min_cti_obsid) && ($obsid <= $max_special_obsid))  &&
	   ($rad =~ "OORMPDS"))
           {    #Just finished a CTI measurment 
	      $triplet_check = -1;  # will record for BOTH ingress and egress
	   }
       } # ENDIF if ($exposure < 200.0)

    elsif ($triplet_check == -1 && (($obsid >= $min_cti_obsid) && ($obsid <= $max_special_obsid)) &&
	  ($rad =~ "OORMPDS") )
          {
	    $triplet_check = 1; #see the stop science	
          }
    
    $tstop=0;
    $tstart=0;
    $biastime=0;
    $stop_sci_count=$stop_sci_count+1;
}   # END SUB PROCESS_STOP_SCIENCE

#--------------------------------------------------------------------
# process_start_science
#--------------------------------------------------------------------
sub process_start_science
  {
     my($stat)=(@_);
    $start_sci_cnt=$start_sci_cnt+1;
    printf LR "%15s%10s%9s%15s\n",$fields[0],$Rec_VCDU,$Rec_Event,
	$Rec_Eventdata{TLMSID};

   #This was added to confirm that the ocat has been loaded at this point
   #to deal with late obsid updates
    if(($loaded_ocat == 1 && $compare == 0) ||
       $cti_flag || $nil_flag)
    {
	parameter_check($stat);
    }
      else
    {
	# This is the fix for the ACIS-HRC-ACIS bug which erroneously expects the
	# second ACIs observation to be without bias if the SI modes of the two acis observations
	# are the same.
	$last_simode = $simode
    }

     #add bias time check here
     $startsciflag=1;
     $tstart=$dec_day+$biastime;
     $tstart_orig=$dec_day;
     $calstarttime=$fields[0];

     # Set the time of the start of the science run to the time stamp of this command.
     $startscitime=$dec_day;
     
     # Set the flag indicating that a science run has begun.
     $science_running_flag = 1;

    print_status(LR,\%chandra_status);
  }  # END SUB PROCESS_START_SCIENCE

#--------------------------------------------------------------------
# check parameters for observation
#   input: chandra_status
#--------------------------------------------------------------------
sub parameter_check{
    my($stat)=(@_);
    print LR "---------------------------------------------------------------------------\n";
    print LR " Parameter block and set up check for $obsid\n";
    print LR "---------------------------------------------------------------------------\n";
    #--------------------
    #Parameter block check (only if in OCAT,CTI or NIL simode known)
    #--------------------
    if ($ocat_simode =~ /_/ )
      {
	check_simode($ocat_simode,$last_simode);
      }

    #--------------------
    #Check the windows if they exist, then clear the SI_MODE
    #--------------------
    $window=check_windows($simode);
    #window should be loaded by now...
    if($needwindow == 1){
	$tmp=compare_windows(\@window_wblock_array,\@window_ocat_array,$si_prefix);
    $needwindow=0;
    }
    $inocat = 0;
    
    $check_acis_sci = 1; #reset the acis science command
    
    $obsid=$chandra_status{"OBSID"};
    $FP=$chandra_status{"FPSI"};
    $FMT=$chandra_status{"FMT"};
    #------------------------------     
    #If not a 60000 OR 5000 obsid, compare the gratings and FP 
    #------------------------------
    if ( (! (($obsid >= $min_cti_obsid) && ($obsid <= $max_special_obsid)) ) &&
       $nil != 1 && 
       $ocatinfo != 2)
       {
	$tmp=compare_states(\%ocat_entries,
			    $chandra_status{"HETG"},
			    $chandra_status{"LETG"},
			    $FP,$sim_z);
	$flag_setup = $flag_setup | $tmp;
	#print LR "***DEBUG*** flag_setup=$flag_setup\n";
	if ($tmp)
           {
	    push(@setup_list,$obsid);
	    $Test_Passed=0;
	   }
       } #ENDIF  ( (! (($obsid >= $min_cti_obsid) && ($obsid <= $max_special_obsid)) ) &&

    #--------------------------------------------------
    # Report error if not the right parameter block
    #--------------------------------------------------
    if($recompbias == 0 &&
       $simode !~ /$last_simode/){
	print LR ">>>WARNING: This parameter block is NOT recalculating a bias\n";
	print LR "   Please confirm the parameter block for $obsid\n";
	print LR "   This SI_MODE is $simode. Previous SI_MODE is $last_simode\n\n";
    }
    #------------------------------
    # if no parameter block was loaded
    # set to last
    #------------------------------
    if($loadpblockflag != 0){
	$last_simode=$simode;
	$simode="";
	$temp4=compare_pblock(); #moved from load_pblock
    }
    
    $loadpblockflag = 0;
    
    #----------------------------------------
    # Various Error checks. May be moved
    #----------------------------------------
    #For radzone
    if ($FP eq "HRC-S")
       {
	if ($ctifmtcheck == 1)
           {
	    if ($FMT ne "CSELFMT2")
               {
		print LR ">>>ERROR: WE ARE DOING A CTI MEASUREMENT BUT WE ARE NOT IN FMT 2!\n\n";
		add_error("o. RadMon was disabled prior to radbelt transit but we were NOT at HRC-S yet.\n\n");  
	       }
	   } # ENDIF ($ctifmtcheck == 1)
        } # ENDIF   ($FP eq "HRC-S")

         if ($FP ne "HRC-S" and (($obsid >= $min_cti_obsid) && ($obsid <= $max_special_obsid)) )
       {
 	 print LR ">>>WARNING: SIM is NOT at HRC-S and OBSID > 50000!\n\n";
	 print LR ">>>-------  CONFIM THAT A SIM TRANSLATION OCCURS PRIOR TO RADBELT TRANSIT!\n\n";
	 if ($FMT ne "CSELFMT2")
            {
	      print LR ">>>ERROR: WE ARE DOING A CTI MEASUREMENT BUT WE ARE NOT IN FMT 2!\n\n";
	      add_error("o. RadMon was disabled prior to radbelt transit but we were NOT at HRC-S yet.\n\n");  
	    }   
	add_error("o. We were about to start a CTI run but we were not at HRC-S yet.\n\n");
       } # ENDIF  ($FP ne "HRC-S" and (($obsid >= $min_cti_obsid) && ($obsid <= $max_special_obsid)) )

    #For standard ACIS observations
    if ($FP eq "ACIS-I" or $FP eq "ACIS-S") 
       {
	if ($chandra_status{"radmonstatus"} ne "OORMPEN")
           {
	    add_error("o. There are ACIS observations for which the RadMon has not been enabled.\n\n");
	    print LR ">>>ERROR: ACIS IS IN THE FOCAL PLANE BUT RADMON IS NOT ENABLED!\n\n";
	   }
	if ($FMT ne "CSELFMT2")
           {
	    print LR ">>>ERROR: ACIS IS IN THE FOCAL PLANE BUT WE ARE NOT IN FMT 2!\n\n";
	    add_error("o. ACIS was in the focal plane but we were NOT in FMT 2 at the time.\n\n");
	   }
	
	if ($chandra_status{"DITH"} eq "DISA")
           {
	    add_error("o. Dither was disabled at the time of a start science.\n\n");
	    print LR ">>>ERROR: ACIS START SCIENCE ISSUED; ACIS IN FOCAL PLANE, BUT DITHER IS DISABLED\n\n";
	   }
       } # ENDIF ($FP eq "ACIS-I" or $FP eq "ACIS-S") 

    if ( (!(($obsid >= $min_cti_obsid) && ($obsid <= $max_special_obsid))) )
       { $compare=1; }
    else
    { $compare=0; }
} #END SUB PARAMETER_CHECK
    

#--------------------------------------------------------------------
# process acispkt
#--------------------------------------------------------------------
sub process_acispkt{
    my($stat)=(@_);
    

    if($Rec_Event =~ /COMMAND_HW/ &&
       $Rec_EventData{TLMSID} =~ /^1*/){
	printf LR "%15s%10s%12s%9s\n",$fields[0],$Rec_VCDU,$Rec_Event,
	$Rec_Eventdata{TLMSID};
	if($Rec_Eventdata{TLMSID} =~ /1HHTRBOF/){
	    $$stat{offtime}=$fields[0];
	    $dhhtr=0;
	}
	if($Rec_Eventdata{TLMSID} =~ /1HHTRBON/){
	    $$stat{ontime}=$fields[0];
	    $dhhtr=1;
	}
    }
    else{
	printf LR "%15s%10s%9s%15s\n",$fields[0],$Rec_VCDU,$Rec_Event,
	       $Rec_Eventdata{TLMSID};
    }
    #------------------------------
    # WSPOW- power chip and FEPS
    #------------------------------
    if ($Rec_Eventdata{TLMSID} =~ /WSPOW*/) {
	$pow_cmd=$Rec_Eventdata{TLMSID};
	$pow_cmd=$Rec_Eventdata{TLMSID};
	$wspow = `${sacgs_dir}/wspow $pow_cmd`;
	print LR "\n  ==> WSPOW COMMAND LOADS: $wspow\n";
    }
    #------------------------------
    # Table dump
    #------------------------------
    if($Rec_Eventdata{TLMSID} eq "RT_0000001"){
	print LR "\n  Dumping ACIS on-orbit Tables\n";
	if($chandra_status{"RADMONstatus"} ne "OORMPDS"){
	    print LR  "\n>>>WARNING: Dumping ACIS on-orbit Tables while RADMON is enabled\n";
	}
	$rtdel=($dec_day-$obsstart)*1440;
	printf LR "  ==> Dumping ACIS Tables occurs %3.1f minutes after stop science.\n\n",$rtdel;
	if ($rtdel < 3.00){
	    print LR  "  ==> ERROR: Need 3.0 minutes between stop science and Dumping ACIS Tables\n\n"
	    }	
    }
    
    #----------------------------------------
    # Video all down
    #----------------------------------------

    #----------------------------------------
    # New power command which leaves three 
    # FEP boards left up.  This is to prevent
    # things from getting too warm during Perigee
    # passages (when in the past 6 were left running).
    # In addition, it was decided to keep 3 up and not
    # shut them all down so as to keep the box from getting
    # too cool.
    # It was implemented in loads Jan. 2018
    # 
    #  The above triplet treatment for WSVIDALLDN
    #  is left in there for old loads to still work
    #----------------------------------------

    # Code which captures a WSPOW00000, WSPOW0002A, and WSVIDALLDN
    # capture check for the post-outbound perigee passage ECS triplet power command.
    if (($Rec_Eventdata{TLMSID} eq "WSPOW00000") ||
       ($Rec_Eventdata{TLMSID} eq "WSPOW0002A") ||
       ($Rec_Eventdata{TLMSID} eq "WSVIDALLDN"))
      {
	$viddwn_cnt=$viddwn_cnt+1;
  	$per_vidalldn=$dec_day;
        # Increment the value of triplet_check indicating you have obtained
        # the first two items of the triplet
	if($triplet_check == 1)
          { $triplet_check = 2; }
      }


    #----------------------------------------
    # System dump
    #----------------------------------------
    if ($Rec_Eventdata{TLMSID} eq "RS_0000001") {
	$sys_cnt=$sys_cnt+1;
	if($triplet_check == 2){
	    $triplet_check=3;
	}
    }
    #----------------------------------------
    # Huffman dump
    #----------------------------------------
    if ($Rec_Eventdata{TLMSID} eq "RH_0000001") {
	$huff_cnt=$huff_cnt+1;
    }   
    #----------------------------------------
    # Quiet Threshold Crossings
    #----------------------------------------
#    if ($Rec_Eventdata{TLMSID} eq "WBTX_QUIET") { 
#	$quiet_flag=1;
#    }
   
} # END SUB PROCESS_ACISPKT

#--------------------------------------------------------------------
#load_pblock: record information for parameter blocks
#                     input: chandra_status
#--------------------------------------------------------------------
sub load_pblock{
    my($stat)=(@_);
   
    printf LR "%15s%10s%9s%15s\n",$fields[0],$Rec_VCDU,$Rec_Event,
	$Rec_Eventdata{TLMSID};

    # Capture the pblock name
    $last_pblock_loaded = $Rec_Eventdata{TLMSID};
    
    $loadpblockflag=1;
    #Create a temporary file for the pblockreader and pass it in.
    # try new temporary filenames until we get one that didn't already exist
    do { $pblockname = tmpnam() }
    until $fh = IO::File->new($pblockname, O_RDWR|O_CREAT|O_EXCL);
    $pbread = `${script_dir}/pblockreader.pl $Rec_Eventdata{TLMSID} $pblockname`;
    print LR "\nACIS PBLOCK LOADS:\n";
    open (PBLOCK,"$pblockname");
    while ($pbline = <PBLOCK>)
        {
	print LR "$pbline"
	}
    print LR "\n\n";
    close(PBLOCK);
    #----------------------------------------
    #Check for the SI MODE that goes with this parameter block
    #----------------------------------------
    
    #check if the TLMSID is in our table
    $tmp_simode=$si_mode_list{$Rec_Eventdata{TLMSID}};
    if($tmp_simode =~ /_/)
    {
	if($nil_flag == 0 &&
	   $cti_flag == 0 )
	  { #clear the old if not NIL or CTI
	     $ocat_simode="";
 	  }
	$simode=$tmp_simode;
    }
    elsif ($simode!~ /_/)
       {
	# if not one in our array, check the tln table..slow
	$simode=find_simode($Rec_Eventdata{TLMSID});
       } #ENDIF ($simode!~ /_/)
    
    #----------------------------------------
    #Store this as the new loaded parameter block
    # Either update it with a WT or, if it's not a WT,  assume it's a WC
    #----------------------------------------
    if($Rec_Eventdata{TLMSID} =~ "WT"){
	$si_prefix="TE";
	update_status("WTval",$Rec_Eventdata{TLMSID},$stat);
	update_history_files("WTval",$stat);
    }
    else{
	$si_prefix="CC";
	update_status("WCval",$Rec_Eventdata{TLMSID},$stat);
	update_history_files("WCval",$stat);
    }
    
    #--------------------------------------------------
    #If CTI, check that the quiet flag has been set
    #--------------------------------------------------
#    if($cti_flag){
#	if($quiet_flag == 0){
#	    printf LR "\n>>>ERROR: There is no WBTX_QUIET command before loading the parameter block for a CTI measurement.\n\n";
#	    add_error("o. There is no WBTX_QUIET command before loading the parameter block for a CTI measurement.\n\n");
#	    }
 #   }
	    
    #------------------------------
    #Store entries,and compare with OCAT
    #------------------------------
    #CLEAR THE HASH!--Need to watch when this occurs
    %pblock_entries=(); #clear hash
    %window_entries=(); #clear hash
    %pblock_entries=read_pblock($pblockname);
    $recompbias=$pblock_entries{"recomputeBias"};
    #$temp4=compare_pblock(); #should this be moved?
    #Collect the bias informaton HERE. We have if this is a bias or no.
    #And we have the information for the parameter block. 
    if($recompbias == 1)
       {
#	print "Biaslength start\n";=()
#	print "${sacgs_dir}/biaslength.pl\n";
	$biaslength=`${sacgs_dir}/biaslength.pl -d ${base_dir}/cmdgen/sacgs/current.dat $Rec_Eventdata{TLMSID}`; 
#	print "Biaslength stop\n";
	@biasinfo=split(/\s+/,$biaslength); #Split on white space
	$biastime=($biasinfo[1]-99.0)/86400.0; #subtract 99 from it. 
       }
    else
       {
	$biastime=0;
       }

} # END SUB LOAD_PBLOCK

#--------------------------------------------------------------------
# load_windowblock: record information for window blocks
#--------------------------------------------------------------------
sub load_windowblock{
    my($stat)=(@_);
    printf LR "%15s%10s%9s%15s\n",$fields[0],$Rec_VCDU,$Rec_Event,
               $Rec_Eventdata{TLMSID};
    #Create a temporary file for the pblockreader and pass it in.
    # try new temporary filenames until we get one that didn't already exist
    do { $pblockname = tmpnam() }
    until $fh = IO::File->new($pblockname, O_RDWR|O_CREAT|O_EXCL);
    $pbread=`${script_dir}/pblockreader.pl $Rec_Eventdata{TLMSID} $pblockname`;
    
    if ($Rec_Eventdata{TLMSID} =~ /W20*/  )  {
	print LR "\nACIS 2D WINDOW BLOCK LOADS:\n";
	update_status("W2val",$Rec_Eventdata{TLMSID},$stat);
	update_history_files("W2val",$stat);
  }
    else{ 
	print LR "\nACIS 1D WINDOW BLOCK LOADS:\n";
	update_status("W1val",$Rec_Eventdata{TLMSID},$stat);
	update_history_files("W1val",$stat);
    }

    open (PBLOCK,"${pblockname}");
    while ($pbline = <PBLOCK>) {
	print LR "$pbline"
	}
    print LR "\n\n";
    close(PBLOCK);
    if($nil_flag != 1){
	@window_wblock_array=(());
	%window_entries=read_wblock($pblockname,\@window_wblock_array);
	#DEBUG print_window_items();
#	$tmp4=compare_windows(\@window_wblock_array,\@window_ocat_array,$si_prefix);
	$needwindow = 1;
    }
    unlink($pblockname);
} # END SUB LOAD_WINDOWBLOCK

#--------------------------------------------------------------------
# find_radzone_simode: return the SI_mode for the CTI measurement
#                      based on the CRM file
#--------------------------------------------------------------------
sub find_radzone_simode{
    my($event_type,$event_time,@crm_list)=@_;
    #event_time is in decimal day
    foreach $crm (@crm_list){
	$radtime=$$crm{time}+$$crm{pad};
	$time_diff = ($$crm{time}-$event_time);
	$si="";
	#add a buffer to the pad time of 300 sec
	$pad=$$crm{pad}+(300./86400);
#	print LR "***DEBUG*** $$crm{string} $$crm{time}. Event time is $event_time Time diff is $time_diff Pad is $pad\n";
	
	if(abs($time_diff) <= $pad){ 
	    if($event_type eq "OORMPDS" &&
	       $$crm{event} =~ /EEF1000/){
		#this is the one we want:
		$si=$$crm{SI};
		last;
	    }
	    elsif($event_type eq "XEF1000" &&
		  $$crm{event} =~  /XEF1000/){   
	#	print LR "***DEBUG*** $$crm{string} $$crm{time}. Event time is $event_time Time diff is $time_diff Pad is $pad\n";
		#this is the one we want:
		#print "Outbound, I found $$crm{time}. Event time is $event_time Time diff is $time_diff Pad is $pad\n";
		$si=$$crm{SI};
		last;
	    }
	}
	
    }
    return $si;
} # END SUB FIND_RADZONE_SIMODE

#--------------------------------------------------------------------
# find_NIL_simode: read the NIL er and look for the simode that 
# matches this obsid
#--------------------------------------------------------------------
sub find_NIL_simode{
    my($obsid,$nil_list)=@_;
    
    my $id;
    my $simode="";
    foreach $nil (@$nil_list){
	$foo= $$nil{id};
	$id=$$nil{id};
	$simode=$$nil{simode};
	if($id =~ $obsid){
	    return $simode;
	}
    }
    return "";
} # END SUB FIND_NIL_SIMODE

#--------------------------------------------------------------------
#pad_check: replace Joe's script with a subroutine
#--------------------------------------------------------------------
sub pad_check{
     my($event_type,$event_time,$pad_time,$backstop_time,@crm_list)=@_;
     
     $event=$event_type;
     if($event_type =~ /OORMPEN/){$event = "XE1RADZ0"}
     if($event_type =~ /EEF1000/){$event = "EE1RADZ0"}
     #print "The event is $event\n";
     
     foreach $crm (@crm_list){
	#DEBUG print "$$crm{event},$$crm{time},$$crm{pad},$$crm{SI}\t$$crm{string}\n";
	 $crm_event=$$crm{event};
	 #anomalously late entries: flag them 
	 if ($crm_event =~ /A$/){$flag=1}
	 #force use of old rad zone names for comparison checks - 3/19/04
	 if ($crm_event =~ /EE1RAD/ ||
	     $crm_event =~ /EEF/) {
	     $crm_event = "EE1RADZ0";
	 }
	 elsif ($crm_event =~ /XE1RAD/ ||
		$crm_event =~ /XEF/) {
	     $crm_event = "XE1RADZ0";
	 }
	 
	 my $time_diff = abs($backstop_time - $$crm{time});
	 
	 #allow up to 7 hour time difference between CRM 
	 #pad file times and backstop times
	 # this accounts for late entries
	 if ($crm_event eq $event && $time_diff < 0.3125)
	 {
	     $crm_pad=$$crm{pad}*86.4;
	     #allow up to 500 sec difference between pad times
	     $diff = abs($pad_time - $crm_pad);
	     #Convert times to hour/min/sec
	     $hour = ($backstop_time - int($backstop_time))*24;
	     $int_hour = int($hour);
	     $min = ($hour - $int_hour)*60;
	     $int_min = int($min);
	     $sec = ($min - $int_min)*60;
	     $int_sec = int($sec);
	     
	     printf LR "AE-8 EVENTS TIME CHECK:\n from backstop: $event = %03d:%02d:%02d:%02d\n",int($backstop_time),$int_hour,$int_min,$int_sec;
	     printf LR " from CRM file: $crm_event = $$crm{string}";
	     if ($diff < 0.5){
		 printf LR " \n ==> CRM Pad Time: $crm_pad ks and Backstop Pad Time: %5.2f ks agree.\n\n",$pad_time;
	     }
	     elsif ($diff >= 0.5){
		 if ($flag == 0){
		     printf LR " \n>>>CRM Pad Time: $crm_pad ks and Backstop Pad Time: %5.2f ks do not agree!!\n",$pad_time;
		     printf LR"     This could be due to extended CTI measurement\n     -OR- error in the load.\n\n"
		     }
		 elsif ($flag == 1){
		     print LR " >>>This $crm_event is an anomalously late AE-8 entry!\n";
		     printf LR " \n>>>CRM Pad Time: $crm_pad ks and Backstop Pad Time: %5.2f ks do not agree!!\n",$pad_time;
		 }
	     }
	 }
     }    
} # END SUB PAD_CHECK
    
#--------------------------------------------------------------------
# check_errors: check all error flags and report any errors at the 
#               end of the load
#--------------------------------------------------------------------
sub check_errors{
#    if ($start_comm ne $stop_comm) {
#	print LR "---WARNING: THE NUMBER OF COMM STARTS DOES NOT EQUAL THE NUMBER OF COMM ENDS.\n\n";
#	$Test_PassedC = 2;
#    }
    if ($perigee_cnt == 0) {
	add_error( "o. There are no PERIGEE CROSSINGS in this load; Are orbital events provided?\n\n");
    }
    
    if ($obsid_cnt < $start_sci_cnt) {
	add_error("o. There are fewer OBSIDs than there are start science commands.\n\n");
    }

    
    if (($stop_sci_count-$perigee_cnt) < $start_sci_cnt) {
	add_error("o. There are fewer AA00000000 commands than there are XTZ0000005 commands.\n\n");
    }
    
    if ($huff_cnt < $start_sci_cnt) {
	add_error("o. There are fewer RH_0000001 commands than there are XTZ0000005 commands.\n\n");
    }
    
     if (($sys_cnt) < $huff_cnt) {
	add_error("o. There are fewer RS_0000001 commands than there are RH_0000001 commands.\n\n"); 
    }
    
    
    if ($Test_Passed == 0) {
	print LR "--------------------------------------------------------------------------\n\n";
	print LR "AT LEAST ONE INSTANCE OF THE FOLLOWING TYPES OF WARNINGS OR ERRORS WERE ENCOUNTERED:\n\n";
	foreach $item (@error_list){
		print LR "$item";
	    }
	if ($flag_params == 1){
	    print LR "o. OCAT and the parameter block did NOT match for obsid(s)\n";
	    foreach $item (@param_list){
		print LR "   - $item\n";
	    };
	    print LR "\n";
	}
	if ($flag_setup == 1){
	    print LR "o. The Instrument, SIM-Z or Grating was incorrect for obsid(s) \n";
	    foreach $item (@setup_list){
		print LR "   - $item\n";
	    };
	    print LR "\n";
	}
	if ($flag_ccds == 1){
	    print LR "o. The CCDs selection was incorrect for obsid(s) \n";
	    foreach $item (@ccd_list){
		print LR "   - $item\n";
	    };
	    print LR "\n";
	}
	if ($flag_windows == 1){
	    print LR "o. The OCAT and the window block did NOT match for obsid(s) \n";
	    foreach $item (@window_list){
		print LR "   - $item\n";
	    };
	    print LR "\n";
	}
	if ($flag_pblock == 1){
	    print LR "o. The parameter block was incorrect for obsid(s) \n";
	    foreach $item (@pblock_list){
		print LR "   - $item\n";
	    };
	    print LR "\n";
	}
	print LR "--------------------------------------------------------------------------\n\n";
	print LR " ACIS LOAD REVIEW FAILED\n";
    }
    else{
	print LR "ACIS BACKSTOP: No failures or warnings found\n";
	print LR "--------------------------------------------------------------------------\n\n";
	print LR " ACIS LOAD REVIEW PASSED\n";
    }
    
  
} # END SUB CHECK_ERRORS

#--------------------------------------------------------------------
#END LOAD
#--------------------------------------------------------------------
sub end_load{
    my($stat)=(@_);
    
    update_history_files(FPHIST,\%chandra_status);
    update_history_files(GRATHIST,\%chandra_status);
    update_history_files(TLMHIST,\%chandra_status);
    update_history_files(OBSIDHIST,\%chandra_status);
    update_history_files(DITHHIST,\%chandra_status);
    update_perigee_history(PERIGEE_OUT,\%perigee_status);

   

print LR "\n-- CHANDRA LOAD END --\n\n";
print LR "\n";
print LR "************************\n";
print LR "ACIS LOAD REVIEW SUMMARY\n";
print LR "************************\n";
print LR "\n\n";
printf LR "THERE ARE %2g REAL-TIME COMM PASSAGES IN THIS LOAD.\n", $start_comm;
print LR "\n";
print LR "FREQUENCY OF ACIS COMMAND OCCURRENCES TABLE:\n";
print LR "----------------------------------------------------------------------\n";
print LR "  OBSIDs  WSVIDALLDNs  RS_0000001  RH_0000001  X[TC]Z0000005  AA00000000 \n";
print LR "----------------------------------------------------------------------\n";
print LR "    $obsid_cnt        $viddwn_cnt           $sys_cnt          $huff_cnt          $start_sci_cnt          $stop_sci_count\n";
print LR "\n";
print LR "**NOTE: There are $perigee_cnt perigee crossings in this load.\n";
print LR "\n";
 print LR "FREQUENCY OF OTG INSERTIONS/RETRACTIONS:\n";
    print LR "--------------------------------------------\n";
    print LR "  LETG_INs  LETG_REs  HETG_INs  HETG_REs\n";
    print LR "--------------------------------------------\n";
    printf LR "     $letg_in_cnt         $letg_out_cnt         $hetg_in_cnt         $hetg_out_cnt\n";
    print LR "\n";

print LR "--------------------------------------------------------------------------\n\n";
print LR "\n";

print LR "--------------------------------------------------------------------------\n\n";


    update_history_files(HIST_OUT,$stat);

} # END SUB END_LOAD

#--------------------------------------------------------------------
#check_acistime: make sure there are at least 2 minutes after start science
#--------------------------------------------------------------------
sub check_acistime{
    $command = $Rec_Eventdata{TLMSID};
    if($Rec_Eventdata{TYPE} =~ /COMMAND_HW/ &
       $command =~ /^1/){#don't check hardware commands
	return;
    }
    confirm_packet_space();
    if ($startsciflag == 1) {
	$acispkt_time_diff = ($dec_day - $startscitime)*1440;
	if ($acispkt_time_diff > 120.){
	    printf LR "\n>>>ERROR: $command OCCURS %4.2f mins AFTER A START SCIENCE.\n\n",$acispkt_time_diff;
	    add_error("o. An ACIS command occurs more than 2 mins after a start science.\n\n");
	}
    }
}
#--------------------------------------------------------------------
#confirm_packet_space: make sure there is at least 1 second between 
# acis packets
# Note: actual H&S requirement is 3 VCDU's - ~ 3/4 second.
#--------------------------------------------------------------------
sub confirm_packet_space{
    $command = $Rec_EventData{TLMSID};
    if($Rec_Eventdata{TYPE} =~ /COMMAND_HW/ &
       $command =~ /^1/){#don't check hardware commands
	return;
    }
    #if ($lastCmdAcisFlag == 1) {
	$acispkt_time_diff = ($dec_day - $lastCmdAcisTime)*86400;
	if ($acispkt_time_diff < 0.9){
	    printf LR "\n>>>ERROR: Two ACIS commands occur less than 1 second apart\n\n",$acispkt_time_diff;
	    add_error("o. Two ACIS commands occur less than 1 second apart.\n\n");
	}
    $lastCmdAcisTime=$dec_day;
    #}
    #else{$lastCmdAcisFlag = 1}; #set the command flag if we ended up here
}
#--------------------------------------------------------------------
#Instead of the acisparams.pl code
#--------------------------------------------------------------------
sub acisparams{

    my($obsid,$outfile)=(@_);
    # return value:0=ACIS 1=failure 2=HRC

    # check for obsid, report error in output file if not in ocat
    my ($sth)=$dbh->prepare(qq{select obsid from target where obsid=?}) || die "The error is " . $sth->errstr;

    $sth->execute($obsid) || die "Unable to access the obsid".$sth->errstr;
    $res = $sth->fetchrow_array();
    $sth->finish();
    if ($res !~ $obsid){
	#call failed
	print LR "No ocat info found for obsid $obsid\n";
	return(1);
    }
    
# Get OCAT information from target table, clean up
    $sth=$dbh->prepare(qq{ select targname,si_mode,instrument,grating,approved_exposure_time,y_det_offset,z_det_offset,acisid,type,rem_exp_time,dither_flag,spwindow_flag,obs_ao_str,obj_flag from target where obsid = ? }) || die "Unable to prepare" . $sth->errstr;
    $sth->execute($obsid) || die "Unable to query table axafocat..target" . $sth->errstr;
    @targetdata=$sth->fetchrow_array();
    $sth->finish();

# define stuff from target table
    ($targetname,$simode,$instrument,$grating,$appexptime,$ydetoffset,$zdetoffset,$acisid,$type,$remexptime,$dither_flag,$spwin,$ao_str,$obj_flag)=@targetdata;
    
    unless ($instrument=~/ACIS/) {
	print LR "No ACIS info found for obsid $obsid.\nThis is an ${instrument} observation.\n";
	return(2);
}
    # Collect the DITHER parameters from the OCAT
    $sth=$dbh->prepare(q{select y_amp,y_freq,y_phase,z_amp,z_freq,z_phase from dither where obsid=?});
    $sth->execute($obsid) || die "unable to collect dither" . $sth->errstr;
    @ditherdata=$sth->fetchrow_array();
    $sth->finish();
    ($y_amp,$y_freq,$y_phase,$z_amp,$z_freq,$z_phase)=@ditherdata;
    
# get stuff from acis table, clean up
    $sth=$dbh->prepare(q{select exp_mode,ccdi0_on,ccdi1_on,ccdi2_on,ccdi3_on,ccds0_on,ccds1_on,ccds2_on,ccds3_on,ccds4_on,ccds5_on,bep_pack,onchip_sum,onchip_row_count,onchip_column_count,frame_time,subarray,subarray_start_row,subarray_row_count,duty_cycle,secondary_exp_count,primary_exp_time,secondary_exp_time,eventfilter,eventfilter_lower,eventfilter_higher,dropped_chip_count from acisparam where acisid=?});
    $sth->execute($acisid) || die "Unable to query acisparam" . $sth->errstr;
    @acisdata =$sth->fetchrow_array();
    $sth->finish();
# define stuff from acis table
    ($expmode,$i0,$i1,$i2,$i3,$s0,$s1,$s2,$s3,$s4,$s5,$evttmfmt,$onchipsum,$onchiprowcnt,$onchipcolcnt,$frametime,$subarraytype,$startrow,$rowcnt,$dutycycle,$secexpcnt,$tprimary,$tsecondary,$evtfilter,$evtfltlow,$evtflthi,$drop)=@acisdata;
    
#Determine the actual CCDs
    @ccdarray=($i0,$i1,$i2,$i3,$s0,$s1,$s2,$s3,$s4,$s5);
    for($ii=0;$ii<10;$ii++){
	if($ccdarray[$ii] =~/O/){
	    $foo=substr($ccdarray[$ii],1,1);        
	    if ($foo <= $drop){
		$ccdarray[$ii]= "N";
	    } else{
		$ccdarray[$ii]="Y";
	    }
	}
    }
    
    $ccdstr=join("",@ccdarray);
    $ccdPretty= substr($ccdstr,0,4) . " " . substr($ccdstr,4,6);

    
# get stuff from sim table, define, clean up
    $sth=$dbh->prepare(q{select trans_offset from sim where obsid=?});
    $sth->execute($obsid) || die "Unable to query table sim" . $sth->errstr;
    $simz=$sth->fetchrow_array();
    $sth->finish();

# get values from aciswin table
    $sth=$dbh->prepare(q{select start_row,start_column,width,height,lower_threshold,pha_range,sample from aciswin where obsid=?});
    $sth->execute($obsid) || die "Unable to query table aciswin" . $sth->errstr;
    @aciswindata=$sth->fetchrow_array();
    $sth->finish();

# define stuff from aciswin table
    ($winstartrow,$winstartcol,$width,$height,$lowerthres,$pharange,$sample)=@aciswindata;

# print output twice, once to the file and again to the LR
    open(OCATOUT,">$outfile") || die "Unable to open the outfile:$outfile\n";

# Round the Dither numbers to 6 decimal places
if ($y_amp ne "")
{
  $y_amp = sprintf("%.6f", $y_amp);
}

if ($y_freq ne "")
{
  $y_freq = sprintf("%.6f", $y_freq);
}

if ($z_amp ne "")
{ 
  $z_amp = sprintf("%.6f", $z_amp);
}

if ($z_freq ne "")
{ 
  $z_freq = sprintf("%.6f", $z_freq);
}

# Form the  output section for the Observation Paramaters as cound in the OCAT
print OCATOUT <<EOP;
Target Name: $targetname\tSI Mode: $simode
Instrument: $instrument\tGrating: $grating\tType: $type
Exposure Time: $appexptime\tRemaining Exposure time: $remexptime
Offset: Y: $ydetoffset\tZ: $zdetoffset\tZ-sim: $simz
ACIS Exposure Mode: $expmode\tEvent TM Format: $evttmfmt\tFrame Time: $frametime
Chips Turned On: $ccdstr
Subarray Type: $subarraytype\tStart: $startrow\tRows: $rowcnt\tFrame Time: $frametime
Duty Cycle: $dutycycle\tNumber: $secexpcnt\tTprimary: $tprimary\tTsecondary: $tsecondary
Onchip Summing: $onchipsum\tRows: $onchiprowcnt\tColumns: $onchipcolcnt
Event Filter: $evtfilter\tLower: $evtfltlow\tRange: $evtflthi
Window Filter: $spwin\tStart Row: $winstartrow\tStart Column: $winstartcol
Height: $height\tWidth: $width
Lower Energy: $lowerthres\tEnergy Range: $pharange\tSample Rate: $sample
Dither: $dither_flag
\tY Amp: $y_amp deg\tY Freq: $y_freq deg/sec\tY Phase: $y_phase
\tZ Amp: $z_amp deg\tZ Freq: $z_freq deg/sec\tZ Phase: $z_phase
Cycle: $ao_str\tObj_Flag: $obj_flag
EOP
print LR <<EOF;
Target Name: $targetname\tSI Mode: $simode
Instrument: $instrument\tGrating: $grating\tType: $type
Exposure Time: $appexptime\tRemaining Exposure time: $remexptime
Offset: Y: $ydetoffset\tZ: $zdetoffset\tZ-sim: $simz
ACIS Exposure Mode: $expmode\tEvent TM Format: $evttmfmt\tFrame Time: $frametime
Chips Turned On: $ccdPretty
Subarray Type: $subarraytype\tStart: $startrow\tRows: $rowcnt\tFrame Time: $frametime
Duty Cycle: $dutycycle\tNumber: $secexpcnt\tTprimary: $tprimary\tTsecondary: $tsecondary
Onchip Summing: $onchipsum\tRows: $onchiprowcnt\tColumns: $onchipcolcnt
Event Filter: $evtfilter\tLower: $evtfltlow\tRange: $evtflthi
Window Filter: $spwin\tStart Row: $winstartrow\tStart Column: $winstartcol
Height: $height\tWidth: $width
Lower Energy: $lowerthres\tEnergy Range: $pharange\tSample Rate: $sample
Dither: $dither_flag
\tY Amp: $y_amp deg\tY Freq: $y_freq deg/sec\tY Phase: $y_phase
\tZ Amp: $z_amp deg\tZ Freq: $z_freq deg/sec\tZ Phase: $z_phase
Cycle: $ao_str\tObj_Flag: $obj_flag
EOF


    close(OCATOUT);
    return(0);
} # END SUB ACISPARAMS

#--------------------------------------------------------------------
# Instead of winparams
#--------------------------------------------------------------------
sub winparams{
    my($obsid,$outfile)=@_;

#    print "$outfile\n";
    open(OUT,">>$outfile") || warn "cannot open the windows temp file\n";
    #SET UP CCD ARRAY
    %ccds=("I0",0,"I1",1,"I2",2,"I3",3,"S0",4,
	   "S1",5,"S2",6,"S3",7,"S4",8,"S5",9);
    # check for obsid, report error in output file if not in ocat
    my ($sth) = $dbh->prepare(qq{select obsid from target where obsid=?}) || 
	die "The error is " . $sth->errstr;
    $sth->execute($obsid) || die "Unable to access the obsid".$sth->errstr;
    $res = $sth->fetchrow_array();
    $sth->finish();
    if ($res !~ $obsid){
	#call failed
	print LR "No ocat info found for obsid $obsid\n";
	return();
    }
    
    #  get values from aciswin table
    $sth=$dbh->prepare(qq{ select ordr,chip,include_flag,start_row,
			   start_column,width,height,lower_threshold,
			   pha_range,sample from aciswin where obsid=?}) 
	|| die "Unable to prepare" . $sth->errstr;
    $sth->execute($obsid) || 
	die "Unable to query table axafocat..aciswin" . $sth->errstr;
    $arrayref = $sth->fetchall_arrayref();  
    $sth->finish();
#    @aciswindata=$sth->fetchrow_array();
#    $sth->finish();
    
    foreach $aciswindata (@$arrayref){   
	# define stuff from aciswin table
	($winorder,$winccd,$include,$winstartrow,$winstartcol,
	 $width,$height,$lowerthres,$pharange,$sample)=@{$aciswindata};
	print LR <<"MOO";
Window on CCD: $ccds{$winccd}\tStart Row: $winstartrow\tStart Column: $winstartcol
Height: $height\tWidth: $width\tInclude: $include
Lower Energy: $lowerthres\tEnergy Range: $pharange\tSample Rate: $sample
MOO
    if( $include =~ /I/i){
	print LR <<"GOO";
Window on CCD: $ccds{$winccd}\tStart Row: 0\tStart Column: 0
Height: 1024\tWidth: 1024\tInclude: E
Lower Energy: \tEnergy Range: \tSample Rate:0 
GOO
} #end include
	
    print OUT <<"MOO";
Window on CCD: $ccds{$winccd}\tStart Row: $winstartrow\tStart Column: $winstartcol
Height: $height\tWidth: $width\tInclude: $include
Lower Energy: $lowerthres\tEnergy Range: $pharange\tSample Rate: $sample
MOO
    if( $include =~ /I/i){
	print OUT <<"GOO";
Window on CCD: $ccds{$winccd}\tStart Row: 0\tStart Column: 0
Height: 1024\tWidth: 1024\tInclude: E
Lower Energy: \tEnergy Range: \tSample Rate:0 
GOO
    } #end include

    } #end all windows
    #collect other windows.
#    while($winorder != 1){
#	$winorder++;
#	# get values from aciswin table
#	$sth=$dbh->prepare(qq{ select ordr,chip,include_flag,start_row,
#			       start_column,width,height,lower_threshold,
#			       pha_range,sample from aciswin where obsid=? 
#			       and ordr=?}) || 
#			       die "Unable to prepare" . $sth->errstr;
#	$sth->execute($obsid,$winorder) || 
#	die "Unable to query table axafocat..aciswin". $sth->errstr;
#	@aciswindata=$sth->fetchrow_array();
#	($winorder,$winccd,$include,$winstartrow,$winstartcol,
#	 $width,$height,$lowerthres,$pharange,$sample) = @$aciswindata;
#	print LR <<MOO;
#Window on CCD: $ccds{$winccd}\tStart Row: $winstartrow\tStart Column: $winstartcol
#Height: $height\tWidth: $width\tInclude: $include
#Lower Energy: $lowerthres\tEnergy Range: $pharange\tSample Rate: $sample
#MOO
#    if( $include =~ /I/i){
#	print LR <<"GOO";
#Window on CCD: $ccds{$winccd}\tStart Row: 0\tStart Column: 0
#Height: 1024\tWidth: 1024\tInclude: E
#Lower Energy: \tEnergy Range: \tSample Rate:0 
#GOO
#    } #end include
#	print OUT <<MOO;
#Window on CCD: $ccds{$winccd}\tStart Row: $winstartrow\tStart Column: $winstartcol
#Height: $height\tWidth: $width\tInclude: $include
#Lower Energy: $lowerthres\tEnergy Range: $pharange\tSample Rate: $sample
#MOO
#    if( $include =~ /I/i){
#	print OUT <<"GOO";
#Window on CCD: $ccds{$winccd}\tStart Row: 0\tStart Column: 0
#Height: 1024\tWidth: 1024\tInclude: E
#Lower Energy: \tEnergy Range: \tSample Rate:0 
#GOO
#    } #end include 
#    }#end while winorder(extra windows)
    close(OUT);
}  # END SUB WINPARAMS

#--------------------------------------------------------------------
# Read the OCAT for the parameters
#--------------------------------------------------------------------
sub read_ocat{
    my($o_file)=(@_);
#REPEATED WORDS
#    $startflag=0;    # Dead code? (commented out 12/20/2013)
    $rowsflag=0;
    $frameflag=0;
    $energyflag=0;
    %ocats=();
#Parse the OCAT entries into an associated array.
    open(OCAT, $o_file) || warn "ERROR:Failed to read $o_file\n";
#    print "Obsid $obsid :\n";
    while(<OCAT>){
	@ocat_words=split('\t',$_);
	foreach(@ocat_words){
	    @ocat_field=split(':',$_);
	    @ocat_field=trim(@ocat_field);
	    #test for specific duplicates:
	    if($ocat_field[0] =~ "Rows" && $rowsflag == 0){
		$ocat_field[0] = "Subarray Rows";
		$rowsflag = 1;
	    }
	    if ($ocat_field[0] =~ "Frame Time" && $frameflag == 0){
		$ocat_field[0] = "ACIS Frame Time";
		$frameflag = 1;
	    }
	    if($ocatfield[0] =~ "Lower" && $energyflag == 0){
		$ocat_field[0] = "Lower Filter";
#		print "Here setting the name to Lower Filter\n";
#		appears to be dead code, never entered for pblock;
		$energyflag = 1;
	    }
#	    print "ocat_entries($ocat_field[0])=$ocat_field[1]\n";
	    $ocats{$ocat_field[0]}=$ocat_field[1];

	}
    }
    close(OCAT);
    return %ocats;
}
#--------------------------------------------------------------------
# read_pblock
#--------------------------------------------------------------------
sub read_pblock{
    my($p_file)=@_;
#Parse the parameter block into an associated array.
open(PBLOCK, $p_file) || warn "ERROR:Failed to read $p_file\n";
%pblock_e=();
    while(<PBLOCK>){
	@pblock_words=split('=',$_);
	@pblock_words=trim(@pblock_words);

   $pblock_e{$pblock_words[0]}=$pblock_words[1];
    }
    close(PBLOCK);
    return %pblock_e;
}
#--------------------------------------------------------------------
# read_wblock
#--------------------------------------------------------------------
sub read_wblock{
    my($p_file,$window_array)=@_;
#Parse the window block into an associated array.
    open(WBLOCK, $p_file) || warn "ERROR:Failed to read $p_file\n";
    my %wblock_e=(());
    $ccd_flag=0;
    while(<WBLOCK>){
	my %window=(());
	@wblock_words=split('=',$_);
	@wblock_words=trim(@wblock_words);
	$wblock_e{$wblock_words[0]}=$wblock_words[1];
	if($wblock_words[0] =~ /eventAmplitudeRange/){

	    %window=(
		     ccdId=>$wblock_e{"ccdId"},
		     ccdRow =>$wblock_e{"ccdRow"},
		     ccdColumn =>$wblock_e{"ccdColumn"},
		     width => $wblock_e{"width"},
		     height => $wblock_e{"height"},
		     sampleCycle => $wblock_e{"sampleCycle"},
		     lowerEventAmplitude => $wblock_e{"lowerEventAmplitude"},
		     eventAmplitudeRange => $wblock_e{"eventAmplitudeRange"}
		     );
	#push onto the array
	push(@$window_array,\%window);
	}
    }
    #foreach $f (@$window_array){
#	print %$f;
#    }
    close(WBLOCK);
    return %wblock_e;
}
#--------------------------------------------------------------------
sub read_ocat_win{
    my($file)=@_;

    my @ocat_win=(());

#Parse the Window OCAT entries into hashes
    open(WCAT, $file) || warn "ERROR:Failed to read $file\n";
    while(<WCAT>){

	my %window=(());
	@ocat_words=split('\t',$_);
#	print $_;
	foreach(@ocat_words){
	    @ocat_field=split(':',$_);
	    @ocat_field=trim(@ocat_field);
	    $ocats{$ocat_field[0]}=$ocat_field[1];
	    if($ocat_field[0] =~ /Sample/){
		%window=(
			 ccdId=>$ocats{"Window on CCD"},
			 ccdRow =>$ocats{"Start Row"},
			 ccdColumn =>$ocats{"Start Column"},
			 width => $ocats{"Width"},
			 height => $ocats{"Height"},
			 sampleCycle => $ocats{"Sample Rate"},
			 lowerEventAmplitude => $ocats{"Lower Energy"},
			 eventAmplitudeRange => $ocats{"Energy Range"}
		     );
		#push hash onto array
		push(@ocat_win,\%window);
	    }   
	}
    }
    close(OCAT);
    return @ocat_win;
}


#--------------------------------------------------------------------
#compare_pblock-Call when needed to do the comparisions either when 
#               pblock or obsid is loaded..depends on states.
#--------------------------------------------------------------------
sub compare_pblock{
#DON'T DO IF RADMON IS DISABLED...THESE ARE DIAGNOSTIC MEASUREMENTS
    if($$stat{"radmonstatus"} eq "OORMPEN" and   #Radmon enabled
      (! (($$stat{"OBSID"} >= $min_cti_obsid) && ($$stat{"OBSID"} <= $max_special_obsid)) ) and #obsid not 38xxx-6xxxx
       $nil_flag != 1 and                        #not NIL 
       $ocatinfo != 2 ){                         #not HRC in OCAT
	convert_params(\%pblock_entries,$si_prefix);
	$tmp2=compare_params(\%pblock_entries, \%ocat_entries,$si_prefix);
	$chips=$ocat_entries{"Chips Turned On"};
	if ($tmp2 != 2){ # if NOT an event histogram
	    $tmp3=check_ccds($pow_cmd,$chips);
	}
	else{ $tmp2=0;} #reset this to a 0
	
	$chips="";#reset the chips string
	    $flag_params = $flag_params | $tmp2;
	$flag_ccds= $flag_ccds | $tmp3;
	if ($tmp2){
	    push(@param_list,$OBSID);
	    $Test_Passed = 0;
	}
	if ($tmp3){
	    push(@ccd_list,$OBSID);
	    $Test_Passed = 0;
	}
    
    unlink($pblockname);
    }
   
}

#--------------------------------------------------------------------
# Compare_params- does the actual comparisions
#--------------------------------------------------------------------
sub compare_params{
    my($pblock_vals,$ocat_vals,$si_prefix)=@_;
#----------------------------------------
# Sanity Check
    $err_flag = 0;
    my @err_list ="";
    $err_count=0;
    #First, pull out the expected instrument
    $instrument=$$ocat_vals{"Instrument"};
    #format set in the convert step.
    if($format =~ "EvtHst"){
	print LR "===> This is an event histogram. Please confirm that this is the expected test.\n";
	return 2;
    }
    
    foreach my $key ( keys %$pblock_vals ) {
	#CHECK BEP MODE
	if ($key =~ "bepPackingMode"){
	    $a_bep = $$pblock_vals{$key};
	    $a_bep = $si_prefix;
	    foreach my $key ( keys %$ocat_vals ) {
		if ($key =~ "Exposure Mode"){
		    $p_bep=$$ocat_vals{$key};
		}
	    }
	    if($a_bep !~ $p_bep){
		$err_flag = 1;
		$err_list[$err_count]="The READModes do not match: Requested:$p_bep. Actual:$a_bep\n";
		$err_count+=1;
	    }
	}
	#--------------------
	#CHECK FEP MODE
	if ($key =~ "fepMode"){
	    #$a_fep = $$pblock_vals{$key};
	    $a_fep = $format;
	    foreach my $key ( keys %$ocat_vals ) {
		if ($key =~ "Format"){
		    $p_fep=$$ocat_vals{$key};
		}
	    }
	    
	    if($a_fep !~ $p_fep){
		$err_flag = 1;
		$err_list[$err_count]="The DataModes do not match: Requested:$p_fep. Actual:$a_fep\n";
		$err_count+=1;
	    }
	}

	#Subarray
	#--------------------
	#CHECK Subarray Info
	if ($key =~ "subarrayStartRow"){
	    $a_subarray = $$pblock_vals{$key};
	    $a_width = $$pblock_vals{"subarrayRowCount"};
	    
	    $subkey="Subarray Type";
	    $startkey="Start";
	    $rowskey="Subarray Rows";
	    $p_subarray=$$ocat_vals{$subkey};
	    
	    $p_start=$$ocat_vals{$startkey}-1;
	    $p_width=$$ocat_vals{$rowskey}-1;
	    if($p_subarray =~ "NONE"){
		$p_start=0;
		$p_width=1023;
	    }
	    #FOR ACIS-S
	    elsif($p_subarray=~"1/8"){
		$p_width=127;
		if($instrument =~ "ACIS-S"){
		    $p_start=448;#ACIS-S
		    }else{
			$p_start=896;#ACIS-I
			}
	    }
	    elsif($p_subarray =~ "1/4"){
		$p_width=255;
		if($instrument =~ "ACIS-S"){
		    $p_start=384;#ACIS-S
		    }else{
			$p_start=768;#ACIS-I
			}
	    }
	    elsif($p_subarray =~ "1/2"){
		$p_width=511;
		if($instrument =~ "ACIS-S"){
		    $p_start=256;#ACIS-S
		    }else{
			$p_start=512;#ACIS-I
			}
	    }
	    $a_stop=$a_subarray + $a_width;
	    $p_stop=$p_start + $p_width;
	    if(($a_subarray == 0 && $a_width== 1023) &&
	       $p_subarray== "NONE"){
		#print "no subarrays requested\n";
	    }
	    elsif(($a_subarray != $p_start) ||
		  ($a_stop != $p_stop)){
		$err_flag = 1;
		$err_list[$err_count]="Subarrays do not match:Actual= $a_subarray to $a_stop  and Requested= $p_start to $p_stop\n";
		$err_count+=1;
	    }
	    #print "Actual= $a_subarray to $a_stop  and Requested= $p_start to $p_stop\n";
	}
	
	#------------------
	#Check Duty cycle
	if($key =~ "dutyCycle"){
	    $dckey= "Duty Cycle";
	    $dcpkey = "Tprimary";
	    $dcskey= "Tsecondary";
	    $acpkey= "primaryExposure";
	    $acskey= "secondaryExposure"; 
	    $dcnkey= "Number";
	    $a_dc= $$pblock_vals{$key};
	    $a_dcp = $$pblock_vals{$acpkey};
	    $a_dcs = $$pblock_vals{$acskey};
	    $p_dc = $$ocat_vals{$dckey};
	    $p_dcn= $$ocat_vals{$dcnkey};
	    $p_dcp= ($$ocat_vals{$dcpkey})*10.0;
	    $p_dcs= ($$ocat_vals{$dcskey})*10.0;
	    #Ocat gives in seconds, PBLOCK gives in 1/10 seconds
	    $p_expo= ($$ocat_vals{"ACIS Frame Time"})*10.0;
	    if($p_expo == 0.0 && $p_dc =~ "Y"){#sometimes, at 3.2 sec, this is left blank
	       $p_expo = 32;
	    }
	    if($p_dcs == 0.0){#if Tsecondary is blank, it should equal FrameTime
		$p_dcs=$p_expo;
	    }

	    if(($p_dc =~ "N") ) { #No duty cycle requested
		if(($p_expo != $a_dcp) &&
		   $p_expo != ""){
		    $err_flag = 1;
		    $err_list[$err_count]="Exposure times do not match. Actual=$a_dcp Requested=$p_expo\n";
		    $err_count+=1;
		}
		#print "The exposure time is $a_dcp sec\n";
	    }else{
		if(($a_dc != $p_dcn) || #number of cycles
		   ($a_dcp != $p_dcp) || #primary times
		   ($a_dcs != $p_dcs)){ #secondary times
		    $err_flag = 1;
		    $err_list[$err_count]="Duty Cycles do not match. Please compare these parameters\n   The actual dutycycle is : $a_dc with $a_dcp (sec/10) and $a_dcs (sec/10)\n   The requested is : $p_dcn with $p_dcp (sec/10) and $p_dcs (sec/10)\n";
		    $err_count+=1;
		    
		}
	    }
	}
    }#end foreach $key
      #Add a report if this is a moving target or Solar System Object
	if($$ocat_vals{"Obj_Flag"} =~ /MT/i ||
	   $$ocat_vals{"Obj_Flag"} =~ /SS/i ){
	    $err_list[$err_count]="There is a Moving Target or Solar System Object. Please check the start science times are properly set.\n";
	    $err_count+=1;
	    print LR "\nWARNING: This is a Moving Target or Solar System Object.\nPlease check the start science times are properly set.\n";
	   
    }
    
#end loop here.. Now check energy filters
    
    #--------------------
    #Check energy filters
    #--------------------
    #      Cycles  1-> 10 use 15.0  
    #      Cycles 11-> NOW use 13.0
    # Set the defaults in case $$ocat_vals{"Cycle"} eq ""
    $p_leng=0.08;
    $p_reng=13.0;
        unless($$ocat_vals{"Cycle"} eq "")
          {
	    if($$ocat_vals{"Cycle"} <= 10)
              {
		$p_reng=15.0;
	      }
	    else
              {
		$p_reng=13.0;
	      }	   
	  } # END UNLESS

	$a_leng = $$pblock_vals{"lowerEventAmplitude"};
	$a_reng = $$pblock_vals{"eventAmplitudeRange"};
	foreach my $key ( keys %$ocat_vals ) {
	  if ($key =~ "Lower"){
	    unless($$ocat_vals{$key} eq ""){
	      $p_leng=$$ocat_vals{$key};
	    }
	  }
	  if ($key =~ "Range"){
	    unless($$ocat_vals{$key} eq ""){
	      $p_reng=$$ocat_vals{$key};
	    }
	  }
	} #end foreach ocat
	#convert and compare
	#conversion is 250
    $p_leng_adu=20;
    $p_range_adu=3750;
   
    $result=convert_event_filter($instrument,$p_leng,$p_reng,\$p_leng_adu,\$p_range_adu);

    
   # print LR "The requested is $p_leng and $p_reng\n";
   # print LR "The predicted is $p_leng_adu and $p_range_adu the actual is $a_leng and $a_reng\n";
    if($a_leng != $p_leng_adu ||
       $a_reng != $p_range_adu){
	$err_flag=1;    
	$err_list[$err_count]="Energy Filters Do Not Match. Please compare these parameters\n   The actual energy filter in PHA is : lower:$a_leng range: $a_reng\n   The requested is : lower:$p_leng_adu range:$p_range_adu\n";
	$err_count+=1;
	
	}   
    
    
    if($err_flag == 1){
	#errors encountered
      print LR ">>>ERROR: Parameter block and OCAT do not match\n";
      print LR "   Please check the following errors\n";
      foreach $err (@err_list){
	  print LR " - $err\n";
      }
  }
    else{
	print LR "  ==> Parameter Block and OCAT are consistent for this observation\n\n";
    }
    
    return $err_flag;
} # END SUB COMPARE_PARAMS

#--------------------------------------------------------------------
# Compare_windows-checks window parameters vs ocat
#                 Note: this will only do the first specified window
#--------------------------------------------------------------------
sub compare_windows{
    my($winblock_vals,$ocat_vals,$si_inst)=@_;

    #----------------------------------------
    # Sanity Check
    #----------------------------------------
    my $err_flag = 0;
    my @err_list;
    my $err_count=0;
    #NOTE @winblock_vals is an array of HASHES
    #@ocat_vals is an array of HASHES

    #set up defaults.
    #p=predicted a=actual
    $p_row=1;
    $p_col=1;
    $p_wd=1024;
    $p_ht=1024;
    $p_sc=1;
   
    #found match
    my $match=0;


   
#The actual window block can have more windows than the ocat specifies.
#look for the CCD first.
#loop through each window in the OCAT.
    foreach $val (@$ocat_vals){
	$a_ccdId=$$val{ccdId};
	#loop through the window block to find the matching CCD
	foreach $win (@$winblock_vals){
	    if( $$win{ccdId} == $a_ccdId){
		$a_row = $$win{ccdRow};
		$a_col = $$win{ccdColumn};
		$a_wd  = $$win{width};
		$a_ht  = $$win{height};
		$a_sc  = $$win{sampleCycle};
		$a_leng= $$win{lowerEventAmplitude};
		$a_reng= $$win{eventAmplitudeRange};		
	       
		unless($$val{ccdColumn} eq ""){
		    $p_col=$$val{ccdColumn};
		}
		unless($$val{width} eq ""){
		    $p_wd=$$val{width};
		}
		
		#Special case, CC mode, there is no row or height
		#in the Window block, then this is CC mode. Set a flag. 
		if( $$win{ccdRow} eq "" &&
		    $$win{height} eq ""){
		    $cc_flag=1;
		}
		else{
		     $cc_flag=0;
		    unless($$val{ccdRow} eq ""){
			$p_row=$$val{ccdRow};
		    }     
		    unless($$val{height} eq ""){
			$p_ht=$$val{height};
		    }
		}
		unless($$val{sampleCycle} eq ""){
		    $p_sc=$$val{sampleCycle};
		}
		
		#remove 1 to match the OCAT and Wblocks
		#COLUMN CHECK
		$pred=$p_col-1;
		unless($a_col == $pred){
		    $err_flag=1;
		    $err_list[$err_count]="Window Start Columns do not match for CCD $a_ccdId.\n   The actual start column is $a_col and the requested is $pred\n";
		    $err_count+=1;
		}
		#WIDTH CHECK
		$pred=$p_wd-1;
		unless($a_wd == $pred){
		    $err_flag=1;
		    $err_list[$err_count]="Window Widths do not match for CCD $a_ccdId.\n   The actual width is $a_wd and the requested is $pred\n";
		    $err_count+=1;	
		}
		
		#IF NOT AN ONE DIMENSIONAL WINDOW
		if($cc_flag == 0){
		    #ROW CHECK
		    $pred=$p_row-1; 
		    unless($a_row == $pred){
			$err_flag=1;
			$err_list[$err_count]="Window Start Rows do not match for CCD $a_ccdId.\n   The actual start row is $a_row and the requested is $pred\n";
			$err_count+=1;
		    }     
		    #HEIGHT CHECK
		    $pred=$p_ht-1;
		    unless($a_ht == $pred){
			$err_flag=1;
			$err_list[$err_count]="Window Heights do not match for CCD $a_ccdId.\n   The actual height is $a_ht and the requested is $pred\n";
			$err_count+=1;
		    }
		} #end 1-D windows
		#Sample Cyle check
		unless($a_sc == $p_sc){
		    $err_flag=1;
		    $err_list[$err_count]="Window Sample Rates do not match for CCD $a_ccdId.\n   The actual sample rate is $a_sc and the requested is $p_sc\n";
		    $err_count+=1;
		}
		
		
		
		#--------------------
		#Check energy filters
		#--------------------
		#defaults
		$p_lengw=0.08;
		$p_rengw=15.0;
		$p_leng_adu=20;
		$p_range_adu=3750;	
		
		unless($$val{lowerEventAmplitude} eq ""){
		    $p_lengw=$$val{lowerEventAmplitude};
		}
		unless($$val{eventAmplitudeRange} eq ""){
		    $p_rengw=$$val{eventAmplitudeRange};
		}
	       	#if there's an event filter in the pblock
		#find out which ranges to use for the window.
		if($pblock_ef =~ /Y/i){	
		    $p_leng = (($pblock_lea>$p_lengw) ? $pblock_lea:$p_lengw);
		    $p_reng = (($pblock_ear<$p_rengw)? $pblock_ear:$p_rengw);
		}
		


		    
		$result=convert_event_filter($instrument,$p_leng,$p_reng,\$p_leng_adu,\$p_range_adu);
		#print LR "The energy filter in ADU is: requested ($p_leng_adu,$p_range_adu) commanded ($a_leng, $a_reng)\n";
		if($a_leng != $p_leng_adu ||
		   $a_reng != $p_range_adu){
		    $err_flag=1;    
		    $err_list[$err_count]="Energy Filters Do Not Match for CCD $a_ccdId.\n Please compare these parameters\n   The actual energy filter in PHA is : lower:$a_leng range: $a_reng\n   The requested is : lower:$p_leng_adu range:$p_range_adu\n";
		    $err_count+=1;
		    
		} 
		
		
		#Set up a match check incase there are 
		#more than windows to check against in the wblock
		if(!$err_flag){
		    $match=1;
		    last; #stop checking, we found our match
		}
		else{
		    #reset the error flag to continue on the 
		    #list of window blocks
		    $err_flag=0;
		}
	    } #end wblock and OCAT have same CCD
	} #end Ocat check
		
	
		
	#Window and OCAT match
	if(!$match){
	    #errors encountered
	    print LR  ">>>ERROR: Window Block and OCAT do not match\n";
	    print LR  "   Please check the following errors\n";
	    foreach $err (@err_list){
		print  LR " - $err\n";
	    }
	    $flag_windows=1;
	    $obsid=$chandra_status{"OBSID"};
	    push(@window_list,$obsid);
	    $Test_Passed=0;
	}
	else{
	    print LR "  ==> The Window Block and Window OCAT agree for this observation\n";
	}
	
	return $match;
	
    }
} # END SUB COMPARE_WINDOWS
    
#--------------------------------------------------------------------
#find_simode
#--------------------------------------------------------------------
sub find_simode{
    my($block)=@_;
    my ($si)="";
    $prev="";
    
    
    unless( -f "/tmp/temp.tln"){
	system(" egrep '!|W[T|C]' $tln_file > /tmp/temp.tln");
    }
    open (TLN, "/tmp/temp.tln") || die "Can't open the /tmp/temp.tln file\n";
    while (<TLN>){
	if ($_ =~ /^$block/){
	    chop($prev);
	    #print $_;
	    #print $prev;
	    $si=substr($prev,1,99); # remove the !
	}
	
	$prev=$_;
    }
    close(TLN);

    
    return $si;
}
#-----------------------------------------------------------------------------
#
# Subroutine check_simode($ocat_simode,$last_simode)
#-----------------------------------------------------------------------------
sub check_simode{
    my($si,$prev_si)=@_;
    $test="none";
    $check_pblock=$WTval;

    # Initialize sibias to the with-bias version of the SI mode
    $sibias="${si}B";
    @pblock=();
    my $cti_flag=0;
    #the OFLS doesn't pay attention to these things....
    #Items that are CTI are always with bias
    foreach $key (keys %si_mode_list)
    {	
	if($si_mode_list{$key} =~ $si)
	  {
	    $cti_flag=1;
  	  }
      }
    # If this is not a CTI measurement, then 
    unless($cti_flag == 1)
      {
	if($si =~ /$prev_si/)
 	  {
	    $sibias=$si;
	  }
      } # END UNLESS

    # Ok tin_file is /data/acis/LoadReviews/script/ACIS_current.tln
    # foo = the No-bias entry for the SI mode
    $foo=`grep -n ${sibias} $tln_file | cut -f1 -d: | head -1`;
    chop($foo);

    # goo is 10 places later than foo. Which strangely enough puts it inside
    # the set of commands for the with-bias version.

    $goo=$foo+10;

    # This extracts the name of the SI mode
    $pblock=`sed -n ${foo},${goo}P $tln_file | grep 'W[T|C]' | head -1| cut -f1 -d:`;
    chop($pblock);

    
#ok-check that this is the stored window;
    if ($si =~ /^CC/){
	$check_pblock=$WCval;
    }
    
    unless($check_pblock =~ $pblock){
	print LR ">>>ERROR: Parameter block stored does not match SI_MODE:$sibias in OCAT.\n";
	print LR "          Stored parameter block is $check_pblock. Requested is $pblock\n";
	add_error("o. The parameter block stored does not match the SI_mode.\n\n");
	$obsid=$chandra_status{"OBSID"};
	push(@pblock_list,$obsid);
	$flag_pblock=1;
	}else{
	    print LR "\n  ==> Parameter Block for SI mode $sibias is $pblock and is stored.\n\n";
	}

   
return;
} # END SUB CHECK_SIMODE

#--------------------------------------------------------------------
#check_windows: confirm that there are windows to compare.
#--------------------------------------------------------------------
sub check_windows{
    my($si)=@_;
   
    if ($si =~ /^[A-Z]/) #had been bug
    {
	$window="none";
	$check_win=$W2val; #assume most are 2D windows 

	$foo=`grep -n ${si} $tln_file | cut -f1 -d: | head -1`;
	chop($foo);
	$goo=$foo+10;
	$moo=`sed -n ${foo},${goo}P $tln_file > /tmp/mytl.tln`;

	open (TLN, "/tmp/mytl.tln") || die "Can't open the mytl.tln file\n";
	while (<TLN>){
	    if ($_ =~ /^!/ &&
		$_ !~ /$si/){
		last;
	    }
	    else{
		if ($_ =~ /^W20/ ||
		    $_ =~ /^W10/ ){
		    chop($_);
		    @foo=split(/:/);
		    $window=$foo[0];
		}
	    }
	}
    }
    close(TLN);
    unlink("/tmp/mytl.tln");
    
#ok-check that this is the stored window;
    if ($si =~ /^C/){
	$check_win=$W1val;
    }
    if($window =~ /^W[12]/){
	unless($check_win =~ $window){
	    print LR ">>>ERROR: Window for SI Mode:$si is not stored.\n";
	    print LR "          Stored window is $check_win. Requested is $window\n";
	}else{
	    print LR "\n  ==> Window for SI mode $si is $window and is stored.\n";
	}
}    
return $window;
}


#------------------------------------------------------------
# subroutine to convert numbers back to words
#------------------------------------------------------------
sub convert_params{
my($pblock_vals,$si_prefix)=@_;
#collect bepPackingMode and fepMode
$bepMode=$$pblock_vals{"bepPackingMode"};
$fepMode=$$pblock_vals{"fepMode"};
$expMode="";
$format="";


if($si_prefix =~ "TE"){
  if ($fepMode == 0) {
	$format = "Raw";
    } elsif ($fepMode == 1) {   # TE histogram ?
	$format = "Hist";
    } elsif ($fepMode == 2) {  # TE 3x3 ?
	if ($bepMode == 0) {
	    $format = "F";
	} elsif ($bepMode == 1) {
	    $format = "F+B";
	} elsif ($bepMode == 2) {
	    $format = "G";
	} elsif ($bepMode == 3) {
	    $format = "EvtHst";
	}
    } elsif ($fepMode == 3) {  # TE 5x5 ?
	if ($bepMode == 0) {
	    $format = "VF";
	}
    }
}
else{
  #---CC section
   $format = "";
    if ($fepMode == 0) {
	$format = "Raw";
    } elsif ($fepMode == 1) {   # CC 1x3 ?
	if ($bepMode == 0) {
	    $format = "F1";
	} elsif ($bepMode == 1) {
	    $format = "G1";
	}
    } elsif ($fepMode == 2) {  # CC 3x3 ?
	if ($bepMode == 0) {
	    $format = "F";
	} elsif ($bepMode == 1) {
	    $format = "G";
	}
    } 
 }

 return $format;
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
# subroutine: call_wspow: Takes in the WSPOW command and returns a FEP
# array of characters (0 for down, 1 for up) and a CCD array of characters
# (N for down, Y for up)
#--------------------------------------------------------------------
sub call_wspow{
$wspow_cmd=$_[0];
$hexstr = "0x" . substr($wspow_cmd, 5, 5);
@feps;
$fep = oct($hexstr) & 63;
    for ($bit = 0; $bit < 6; $bit++) {
      $feps[$bit]='0';
	if ($fep & (1 << $bit)) {
	  $feps[$bit]='1';
	} 
    }

$vids = oct($hexstr) >> 8;
@ccds;
  for ($bit = 0; $bit < 10; $bit++) {
    $ccds[$bit]='N';
    if ($vids & (1 << $bit)) {
	if ($bit < 4) {
	  $ccds[$bit]='Y'; 
	} else {
	  $ccds[$bit]='Y';
	}
      }
  }
 return @ccds;
}
#------------------------------------------------------------
#compares a string of Y and N to the ccds selected via the WSPOW
#------------------------------------------------------------
sub check_ccds{
    $mnem = $_[0];
    $string = $_[1];
    $err_flag = 0;
    
    @ccdstr=call_wspow($mnem);
    
    $new_str="$ccdstr[0]$ccdstr[1]$ccdstr[2]$ccdstr[3]$ccdstr[4]$ccdstr[5]$ccdstr[6]$ccdstr[7]$ccdstr[8]$ccdstr[9]";
    
    if ($string ne $new_str){
	print LR ">>>ERROR: Not the correct CCDS\n   Requested=$string Actual=$new_str\n\n";
	$err_flag=1;
    }

    return $err_flag;
}
#--------------------------------------------------------------------
# Compare_states- Compares HETG,LETG, FP inst and SIM-Z offset
#--------------------------------------------------------------------
sub compare_states{
    my($ocat_vals,$HETG,$LETG,$instrument,$sim_z)=@_;

    if ($format =~ "EvtHst"){#don't do this if this is event histogram
	return 0;
    }
    $err_flag = 0;
    my @err_list ="";
    $err_count=0;
    $grt_err=0;
    #Compare the INSTRUMENT, GRATING and SIM-Z positions
    $oinst=$$ocat_vals{"Instrument"};
    $ograt=$$ocat_vals{"Grating"};
    $osim=$$ocat_vals{"Z-sim"};
    my $cur_grating="NONE"; #current grating in place
    


    if($oinst ne $instrument){
	$err_flag = 1;
	$err_list[$err_count]="Requested Instrument is NOT in focal plane.\n   Requested:$oinst Actual:$instrument\n";
	$err_count+=1;
    }

    #------------------------------
    #Determine current grating
    #------------------------------
    if($LETG =~ /OUT/ &&
       $HETG =~ /OUT/ ){
	$cur_grating="NONE";
    }
    
    if($LETG =~ /IN/ &&
       $HETG =~ /OUT/){
	$cur_grating="LETG";
    }

    if($HETG =~ /IN/ &&
       $LETG =~ /OUT/){
	$cur_grating="HETG";
    }
    
    if($LETG =~ /IN/ &&
       $HETG =~ /IN/){
	$cur_grating="FAULT";
    }


    #TEST AGAINST OCAT

    if($ograt eq "LETG"){
	if ($LETG ne "LETG-IN" ||
	    $HETG ne "HETG-OUT"){
	    $grt_err=1;
	}
    }elsif($ograt eq "HETG"){
	if ($LETG ne "LETG-OUT" ||
	    $HETG ne "HETG-IN"){
	    $grt_err=1; 
	}
    }elsif($ograt eq "NONE" ||
	   $ograt eq ""){
	if ($LETG ne "LETG-OUT" ||
	    $HETG ne "HETG-OUT"){
	    $grt_err=1;
	}
    }
    if($grt_err == 1){
	$err_flag = 1;
	$err_list[$err_count]="Requested Grating is NOT inserted.\n   Requested:$ograt Actual:$cur_grating\n";
	$err_count+=1;
    }


    if ($osim eq ""){
	$osim = 0;
    }
    $temp1=(abs($osim)-0.02); $temp2=(abs($osim)+0.02);
    if(abs($sim_z) lt $temp1 ||
       abs($sim_z) gt $temp2){
	$err_flag = 1;
	$err_list[$err_count]="Requested Z-SIM offset incorrect.\n   Requested:$osim Actual:$sim_z\n";
	$err_count+=1;
    }

    #print LR "***DEBUG*** $HETG\t$LETG\t$instrument\t$sim_z\t\n";
    if($err_flag == 1){
	#errors encountered
	print LR ">>>ERROR: Problem with Instrument configuration\n";
	print LR "   Please check the following errors\n";
	foreach $err (@err_list){
	    print LR " - $err\n";
	}
    }
    else{
	print LR "  ==> FP instrument, Grating and SIM-Z offsets OK.\n\n";
    }

    return $err_flag;
} # END SUB COMPARE_STATES

#------------------------------------------------------------
# Read the manuever file and create two arrays of start and stop
# times
#------------------------------------------------------------
sub read_manuever{
    my($file,$start_arr,$stop_arr)=@_;
    open(MANFILE,$file);
    while(<MANFILE>){
	chop($_);
	if($_ =~ 'START TIME'){
	    $start_time=split_times($_);
	    push(@$start_arr,$start_time);
            #advance to check the saa	  
	    do{
		$_=<MANFILE>;
		chop($_);
		@row = split (/\s+/, $_);
	    } until ($_ =~ /Sun Angle/);
	    $saa=$row[4]; 
	}
	if($_ =~ 'STOP TIME'){
	    $stop_time=split_times($_);
	    push(@$stop_arr,$stop_time);
	    #advance to check the saa	  
	    do{
		$_=<MANFILE>;
		chop($_);
		@row = split (/\s+/, $_);
	    } until ($_ =~ /Sun Angle/);
	    $saa=$row[4]; 
	}
    }
    close(MANFILE);
    
    return;
}
#------------------------------------------------------------
# Read the manuever file and create a hash of information
# 
#------------------------------------------------------------
sub read_maneuver_hash{
    my($file,$man_array)=@_;
    open(MANFILE,$file);
    $count=0;
    
    while(<MANFILE>){	
	chop($_);
	if($_ =~ 'START TIME'){
	    my %man_item=(());	# create a new maneuver item
	     @row = split (/\s+/, $_);
	    $start_time=parse_time($row[4]);	    
	    $start_time_gmt=$row[4];
            #advance to check the saa	  
	    do{
		$_=<MANFILE>;
		chop($_);
		@row = split (/\s+/, $_);
	    } until ($_ =~ /Sun Angle/);
	    $saa_start=$row[4]; 
	    #advance to stop maneuver
	    do{
		$_=<MANFILE>;
		chop($_);
		@row = split (/\s+/, $_);
	    } until ($_ =~ /STOP TIME/);
	    $stop_time=parse_time($row[4]);
	    $stop_time_gmt=$row[4];
	    #advance to check the saa	  
	    do{
		$_=<MANFILE>;
		chop($_);
		@row = split (/\s+/, $_);
	    } until ($_ =~ /Sun Angle/);
	    $saa_stop=$row[4]; 
	    #Found the stop of the maneuver, now we can go ahead and 
	    #add this maneuver to the array
	    %man_item=(start_man=>$start_time,
		       start_gmt=>$start_time_gmt,
		       saa_start=>$saa_start,
		       stop_man=>$stop_time,
		       stop_gmt=>$stop_time_gmt,
		       saa_stop=>$saa_stop,
		       );
	    push(@$man_array,\%man_item);	   
	}
    }
    #end while    
    
    close(MANFILE);
    return;
}

#------------------------------------------------------------
# Change a colon separated time to a day decimal
#------------------------------------------------------------
sub split_times{
    my($timeline)=@_;
    @times=split /:/, $timeline;
    @secs=split /\./, $times[5];
    #                  DOY          + #hours/24hrs/day + #min/#min/day + #secs/#secs/day
    $dec_day = $times[2] + $times[3]/24.0 + $times[4]/1440.0 + $times[5]/86400.0;
    return $dec_day;
}

#------------------------------------------------------------
# determine if there is a new start time based on the manuever
#------------------------------------------------------------
sub manuever_time{
    my($start,$stop,$start_arr,$stop_arr)=@_;
    $new_start=$start;

    foreach $i (@$stop_arr){
	if ($i <= $stop){
	    if($i >= $start){
		$new_start=$i;
		last;
	    }
	}
    }
    return $new_start;
}

#====================================================================
#compare_event_filter: compares the actual to predicted event
#                      filters in ADU
#====================================================================
sub convert_event_filter{
    my($instrument,$p_leng,$p_range,$p_leng_adu,$p_range_adu)=@_;
   
#Pass back the ADU ranges....

    $slope_low_i3 = 120;
    $intcpt_low_i3 = -22.84;
    $slope_low_s3 = 199;
    $intcpt_low_s3 = -28.09;
    $slope_hi_i3 = 227;
    $intcpt_hi_i3 = -151.81;
    $slope_hi_s3 = 211;
    $intcpt_hi_s3 = -42.28;
    $hi_low_point = 1.2; # kev split point for using hi or low
    $slope_range = 250;
    $intcpt_range = 0.0;

    #above 0.5 kev?
    if($p_leng > 0.5){
	$$p_leng_adu = 20;
	$$p_range_adu = 6250;
	$eng=0.08;
	$ran=15.0;
	# There are windows. A message should probably be produced here...
   }
    else{
	if($p_leng > $hi_low_point){
	    if($instrument =~ /ACIS-I/){
		$slope=$slope_hi_i3;
		$intcpt=$intcpt_hi_i3;
	    }
	    else{
		$slope=$slope_hi_s3;
		$intcpt=$intcpt_hi_s3;
	    }
	}
	else{
	     if($instrument =~ /ACIS-I/){
		$slope=$slope_low_i3;
		$intcpt=$intcpt_low_i3;
	    }
	    else{
		$slope=$slope_low_s3;
		$intcpt=$intcpt_low_s3;
	    }
	}
	#do I need to FLOOR these?#yes
	$$p_leng_adu=($slope *$p_leng)+$intcpt;
	#reduce to the lowest adu
	$$p_leng_adu= floor($$p_leng_adu);




	if($$p_leng_adu < 20){
	    $$p_leng_adu = 20;
	}
	
	$$p_range_adu=floor(($slope_range * $p_range)+$intcpt_range);
    }
    
    

$flag=0;

return $flag;
} # END SUB CONVER_EVENT_FILTER

#--------------------------------------------------------------------
#Perigee angle check
#--------------------------------------------------------------------
sub perigee_angle_check{
    my($disb_dec,$enab_dec,@man_array)=@_;
    
    my $td_ks=0;
    my $total_time=0;
    my $return_time=0;
    my $man_start=0;
    my $man_stop=0;
     
    my $last_man_start=0;
    my $last_man_stop=0;
    #----------------------------------------
    # ITEMS MAY CHANGE
    #----------------------------------------
    $min_pitch=140.0;
    
    #print LR "THE Radmon times are $disb_dec, $enab_dec\n";
    foreach $man (@man_array){  
	$man_start=$$man{start_gmt};
	$man_stop=$$man{stop_gmt};
	$final_saa=$$man{saa_stop};
	$start_saa=$$man{saa_start};
	$start_dec_day=$$man{start_man};
	$stop_dec_day=$$man{stop_man};
	
	#First calculate the HOLD from the last maneuver:
	if($last_man_stop != 0){
	    if($start_saa >= $min_pitch &&
	       $last_man_stop > $disb_dec &&
	       $start_dec_day < $enab_dec){
#DEBUG
#   print "The manuver is $man_start,$start_saa, $man_stop,$final_saa\n";
#DEBUG
		#CALC HOLD TIME
	    $time_delta = $start_dec_day - $last_man_stop;
	    $ks_td= ($time_delta *86.4); #time delta in ks
	    $total_time+=$ks_td;
	    if($ks_td > 0){
		
	#	printf "%10s\t%10s\t%5.2f\t\t%5.2f HOLD\n", $last_man_stop, $man_start, $final_saa, $ks_td;
	    }
	}
	    
	}
	
	#Calculate Maneuver time
	if($start_saa >= $min_pitch &&
	   $final_saa >= $min_pitch &&
	   $stop_dec_day > $disb_dec &&
	   $start_dec_day < $enab_dec){
	    
	    
	    #CALC MAN TIME
	    $time_delta = $stop_dec_day - $start_dec_day;
	    $ks_td= ($time_delta *86.4); #time delta in ks
	    $total_time+=$ks_td;
	    #DEBUG STATEMENT
	 #   printf "%10s\t%10s\t%5.2f\t\t%5.2f MAN\n", $man_start, $man_stop, $final_saa, $ks_td;		    
	    
	} #end if maneuver
	#Do the boundaries
	#boundary condition, enable happens
	elsif($stop_dec_day > $disb_dec &&
	      $start_dec_day >= $enab_dec){
	    #use the enable time as the stop of this hold
	    #CALC HOLD TIME
	    $time_delta = $enab_dec - $last_man_stop;
	    if($time_delta < 0){
		next;
	    }
	    $ks_td= ($time_delta *86.4); #time delta in ks
	    $total_time+=$ks_td;
	  #  printf "%10s\t%10s\t%5.2f\t\t%5.2f HOLD\n", $last_man_stop, $enab_dec, $start_saa, $ks_td;
	    
	    if($total_time > 0){
		#print "In Boundary Total time for this crossing above 140 is $total_time\n";
		#$total_time= 0;
		last;
	    }
	} #end else
	#deal with boundary condition.. 
	#radmon disable happens during a hold
	elsif($stop_dec_day < $disb_dec &&
	      $start_dec_day >=$enab_dec){
	    #use the DISABLE as the START of this hold
	    $time_delta=$start_dec_day - $disb_dec;
	    if($time_delta < 0){
		next;
	    }
	    $ks_td= ($time_delta *86.4); #time delta in ks
	    $total_time+=$ks_td;
	   # printf "%10s\t%10s\t%5.2f\t\t%5.2f HOLD\n", $man_stop, $man_start, $start_saa, $ks_td;	    
	}
	
	elsif($stop_dec_day > $enab_dec){
	    #Past the perigee crossing
	    if($total_time > 0){			
		#print "In Perigee End Total time for this crossing above 140 is $total_time\n";
		
		#$total_time=0;
	    }
	    last; # stop the looping
	}
	$last_man_start=$start_dec_day;
	$last_man_stop=$stop_dec_day;
    } #end loop over all
    
    
    return $total_time;
} # END SUB PERIGEE_ANGLE_CHECK

#---------------------------------------------------------------------
# add_error: error list is a global
#--------------------------------------------------------------------
sub add_error{
    my($str)=@_;
#    print "****DEBUG****I've been asked to add \n $str\n to the error list\n";
    $Test_Passed=0;
    foreach $item (@error_list){
	if ($item =~ $str){
	    #already in array
	    return;
	}
    }
    push(@error_list,$str);
}

#--------------------------------------------------------------------
#parse_time():return dec day
#--------------------------------------------------------------------
sub parse_time(){
    my($time_str)=(@_);

    # Parse Time
    @times = split(/\:/, $time_str); 
    @secs = split(/\./,$times[4]); 

    $dec = $times[1] + $times[2]/24 + $times[3]/1440 + $times[4]/86400;
    return $dec;
}
#--------------------------------------------------------------------
#parse_time2():return year+dec day
#--------------------------------------------------------------------
sub parse_time2(){
    my($time_str)=(@_);

#    print "In Parse_string: $time_str\n";
    # Parse Time
    @times = split(/\:/, $time_str); 
    @secs = split(/\./,$times[4]); 
    $DIY=366;
    
    $dec = $times[1] + $times[2]/24 + $times[3]/1440 + $times[4]/3600;
    $dec_year=$times[0]+ $dec/$DIY;
 #   print "The return is $dec\n";
	      

    return $dec;
}
#============================================================
# USES GLOBALS USES GLOBALS
# Parse the next backstop record into fields that we use
#============================================================
sub Process_Next_Record {
  my $rec = $_[0];
  my $fields;
  my @times;
  my @secs;
  my @pairs;

  @fields = split /\|/ ;

  # Parse Time
  @times = split /:/, $fields[0];
  @secs = split /\./,$times[4]; 
  $Rec_Time = $times[0].$times[1].".".$times[2].$times[3].$secs[0].$secs[1];
  $dec_day = $times[1] + $times[2]/24 + $times[3]/1440 + $times[4]/86400; 

  #Parse VCDU
  ( $Rec_VCDU, $Rec_MC ) = ( $fields[1] =~ /\s*(\S+)\s+(\S+)\s*/ );

  #Parse Event
  ( $Rec_Event ) = ( $fields[2] =~ /\s*(\S+)\s*/ );

  #Parse Event data
  @pairs = split /,/, $fields[3];
  undef %Rec_Eventdata;
  foreach ( @pairs )
    {
      my $key;
      my $value;
      ( $key, $value ) = ( $_ =~ /(\S+)=\s*(\S+)\s*/ );
      $Rec_Eventdata{$key} = $value; 
    }
}
#--------------------------------------------------------------------
sub print_window_items{
                
    print "The OCAT has\n";
    foreach $win (@window_ocat_array){
	print "CCD=$$win{ccdId}
	       ROW=$$win{ccdRow}
	       COL=$$win{ccdColumn}
	       WID= $$win{width}
	       HT = $$win{height}
	       SC = $$win{sampleCycle}
	       LEA= $$win{lowerEventAmplitude}
	       EAR= $$win{eventAmplitudeRange}\n";
    }
    print "The window block has\n";
    foreach $win (@window_wblock_array){
	print "CCD=$$win{ccdId}
	       ROW=$$win{ccdRow}
	       COL=$$win{ccdColumn}
	       WID= $$win{width}
	       HT = $$win{height}
	       SC = $$win{sampleCycle}
	       LEA= $$win{lowerEventAmplitude}
	       EAR= $$win{eventAmplitudeRange}\n";
    }
}
#--------------------------------------------------------------------
#check_scs
#--------------------------------------------------------------------
sub check_scs{
    my($scs) = (@_);

    @forbidden= ("^XT*",#items that are FORBIDDEN in the vehicle load
		 "^XC*",
		 "^X1*", #bias runs
		 "^X2*", #bias runs
		 "^SIM*", #sim translation or focus
		 "OORMP"); #radmon commands
    
    @warn=("^XB");	     #warn if we see this
    
    $bad_command=0;
    
    if($scs == 128 ||
       $scs == 129 ||
       $scs == 130){
	foreach $f (@forbidden){
	    if($Rec_Eventdata{TLMSID} =~ /$f/ ||
	       $Rec_Event =~ /$f/ ){
		if($f !~ /SIM/){
		    $pr_item = $Rec_Eventdata{TLMSID};
		}
		else{
		    $pr_item= $Rec_Event;
		}
		print LR ">>>ERROR:  $pr_item is NOT ALLOWED in the Vehicle SCS slots\n";

		add_error("o. A $pr_item is in the vehicle SCS slots\n\n");
		$bad_command=1;
		last;
	    }
	}
	
	foreach $w (@warn){
	    if($Rec_Eventdata{TLMSID} =~ /$w/){
		print LR ">>>WARNING :$Rec_Eventdata{TLMSID} SHOULD NOT be in a vehicle SCS slot\n\n"; 
		$bad_command=1;
	    }
	}
	#SPECIAL CASE WSPOW
	if($Rec_Eventdata{TLMSID} =~ /WSPOW*/ &&
	   $Rec_Eventdata{TLMSID} !~ /WSPOW00000/){
	    print LR "WARNING: $Rec_Eventdata{TLMSID} is NOT ALLOWED in a Vehicle SCS Slot\n";
	    add_error("o. A $Rec_Eventdata{TLMSID} is in the vehicle SCS slots\n\n");
	    $bad_command=1;
	}
	
	if($bad_command == 0){
	    #command passed all tests
	    #check if this command is a SAR command
	    check_SAR();
	}
    }       
}

#--------------------------------------------------------------------
# check SAR: report if we need to manually check the SAR
#--------------------------------------------------------------------
sub check_SAR(){
    #passed in only if in 128,129,130

    #if an acispkt or an ACIS hw command,.
    if ($Rec_Event eq "ACISPKT" ){
	print LR ">>>WARNING: An ACIS COMMAND is in the vehicle load. Check for SAR.\n";
	add_error("o. An ACIS command is in the vehicle load. Check for SAR.\n\n");
    }
    if ($Rec_Eventdata{TLMSID} =~ /\A1/){
	print LR ">>>WARNING: An ACIS Hardware command is in the vehicle load. Check for SAR.\n";	
	add_error("o. An ACIS Hardware command is in the vehicle load. Check for SAR.\n\n");
    }
}
		
	
