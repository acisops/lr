#!/usr/bin/env perl

# SYNTAX: ACE-update.pl [-b]
# Use the -b switch when running from /data/acis-bak.

# $Log$
# Update History:
# 16/10/02 - Added error trap for no arguments with usage example - JD
# 25/03/03 - Some revisions to code - script no longer requires an argument
#   path to load is obtained from /data/acis0/LoadReviews/current_load.txt
# 07/05/03 - Change call from scp2 to scp.
# 08/05/03 - Remove "-p" option in scp commands.
# 10/29/03 - Added nadams to mailing
# 02/18/04 - Added extra info to mailing and redirected mailing to acisdude
# 03/23/04 - changed location of script "ephin_orbevents.pl"
# 04/02/04 - added call to /data/acis0/LoadReviews/script/crm_saved_time.pl
# 05/05/04 - updates for sw move to /data/acis & /data/acis-bak
# 07/27/04 - updated location of ephin_orbevents.pl
# 11/10/04 - converted to perl--NRAW
# 12/09/09 - Actually crm_saved_time.pl is identical to the one in /data/acis/...... not acis0
# 03/15/11 - Added a time check to make sure we don't set time backwards.
# 06/23/15 - Copy ephin_orbevents file to acisweb machines.
#
# Update: October 5, 2018
#         Gregg Germain
#         - Add the copy of the orbevents file to acisway
#
# Update: February 14, 2019
#         Gregg Germain
#         - acisocc-w changed to acisway
#
# Update: June 20, 2019
#              Gregg Germain
#                - acisocc-v eliminated
#
# Update: April 4, 2022
#              Gregg Germain
#                - Added SCS-155 Deadman history files: SCS155-HIST.dat
#                  and ACIS-SCS155-HIST.dat
#
# Update: August 24, 2022
#              Gregg Germain
#              - Removed file copies to luke-v and han-v
#
#--------------------------------------------------------------------
#modules used
#--------------------------------------------------------------------
use Fcntl qw(:DEFAULT :flock);
use File::Copy;
use Mail::Mailer;
use Getopt::Std;
use Getopt::Long;
use MachinePath(); #code to find the right directory


#-----------------------------------
#Check to be sure user is acisdude
#------------------------------------
$acisdude_uid=getpwnam acisdude;
$acisdude_uid == $< or die "Error: Must be logged in as acisdude\n";

#----------------------------------------
#set variables
#----------------------------------------
$test=0;
$test_dir="";
# Recipient of email when ACS-update is run for score
$recipient="acisdude\@head.cfa.harvard.edu";

# Email recipient when ACS-update is run in test mode
$test_email_recipient = "ggermain\@cfa.harvard.edu";

$appx =`lr_suffix.pl`; # Null or "-bak"
#$appx = "";

if($appx) {
    $isBackup = 1;
}
else{
    $isBackup = 0;
}
$base_dir = </data/acis${appx}>;

# FLU-MON directory definitions

$han_flu=GetFluMon('han-v');
$acis60v_flu = GetFluMon('acis60-v');
#$acisoccv_flu = GetFluMon('acisocc-v');
$acisway_flu = GetFluMon('acisway');
$ishmael_flu = GetFluMon('ishmael');
$colossusv_flu = GetFluMon('colossus-v');
$aciscdpv_flu = GetFluMon('aciscdp-v');

$xcanuck_flu=GetFluMon('xcanuck'); # Dir for main global history files

# Usuall, $dir ends up being /proj/sot/acis/FLU-MON/
if($isBackup) {
    $dir=GetFluMon("colossus-v");
}
else{
    $dir=${xcanuck_flu}
}
$old_umask=umask(002);
$umask=002;

#Key is the mission history file, value is the load history file
%history_files=("FPHIST-2001","ACIS-FPHIST",
		"GRATHIST-2001","ACIS-GRATHIST",
		"OBSHIST","ACIS-OBSHIST",
		"TLMHIST","ACIS-TLMHIST",
		"TSCHIST","ACIS-TSCHIST",
		"DITHHIST","ACIS-DITHHIST",
                "SCS155HIST", "ACIS-SCS155HIST");


   
#
#----------------------------------------
#Getoptions: looking for test directory
#----------------------------------------
GetOptions('test=s',\$test_dir);
if($test_dir)
  {
    print "\n\nACE-update - Running ACE-update in TEST MODE.\n\n";
    $test=1;
    $dir=$test_dir;
    $load_file = "$dir/current_load.txt";
  } 
else
  {
    $load_file = "$base_dir/LoadReviews/current_load.txt";
    $test = 0;
  }

#Collect the week and year information
open(LOAD, $load_file) || die 
    "Could not open $load_file for input\n";
while(<LOAD>)
{
    chop;
    @info=split /\//;
    $load=$_;
}
$week=@info[5];
$year=@info[4];

#Set up a read loop to get the right path
  $ans='N';# default for loop 
    
    while($ans !~ /[Yy]/)
{
    print "$load\n";
    print STDOUT "Is this the right path to approved load? (y or n) ";
    chop($ans=<STDIN>); 
    
    if ($ans !~ /[Yy]/)
    {
	print STDOUT "Please provide path:";
	chop($load=<STDIN>);
	@info=split(/\//,$load);
	$week=@info[5];
	$year=@info[4];
     }
} #end while loop

#Need to set the remainder of the file paths here to capture the year.

$load_dir=$load;
    $dir2="$base_dir/LoadReviews/$year";
$dir3="/data/acis33/LoadReviews/$year";

&confirm_cat(%history_files);
#------------------------------------------------
# Loop through each history file.
#------------------------------------------------
while (($key, $value) = each(%history_files)){
    print "...Updating history file $key.dat...\n";
    print "Copying $dir/$key.dat to $dir/$key-temp.dat\n"; 
    copy("$dir/$key.dat","$dir/$key-temp.dat");
    #print "Read for internal Cat\n";
    #----------------------------------------
    #combine the files
    #----------------------------------------
    &internal_cat("$dir/$key-temp.dat","$load_dir/$value.dat",
		  "$dir/$key.dat"); 
}

#--------------------------------------------------
# Now that files are all updated, then put the copy
# in a separate loop
#--------------------------------------------------
$hist_fls_str = "";

while (($key, $value) = each(%history_files)){
    $hist_fls_str .= "$dir/${key}.dat ";
   #----------------------------------------
    #Change the group to acisops
    #----------------------------------------
    &chgrp_by_name("acisops","$dir/$key.dat");
}

$HEAD_flu = "han-v:$xcanuck_flu"; # Global history file directory
if ($test == 0) {
    print "\nCopying history files to COLOSSUS-V.";
} else {
    print "\n\nACE-update - In testing mode, no copy occurs to COLOSSUS-V.";
    print "\n\nACE-update - Copy commands that would have executed:\n\n";
}
#--------------------------------------------------
# secure copy to colossus-v
# NEED LIBRARY for locations
#--------------------------------------------------
@targ_dirs = ( "colossus-v:$colossusv_flu",
	               $HEAD_flu);
foreach $destin (@targ_dirs) {
    if (($destin eq $HEAD_flu) && ! $isBackup) {
	#Files already on han-v global directory, don't have to copy
	next;
    } elsif (($destin =~ "colossus-v") && $isBackup) {
	#Files already on backup machine, don't have to copy
	next;
    }
    if($test == 0)
      {
	  print "\nA-u.pl: SCP'ing $hist_fls_str to $destin\n";
	system("scp $hist_fls_str $destin");
      }
    else 
      {
	print ("scp $hist_fls_str $destin\n");
      }
}

if ($test == 0) {
    print "Copying history files to ACIS60-V, ACISCDP-V, ACISWAY and ISHMAEL...\n";
} else {
    print "\nIn testing mode, no copy occurs to " .
	"ACIS60-V or ACISCDP-V, ACISWAY or ISHMAEL.\n";
    print "ACE-update TEST MODE - Would have executed:\n";
}
#--------------------------------------------------
# secure copy to acis60-v, aciscdp-v
# NEED LIBRARY for locations
#--------------------------------------------------
@targ_dirs = ( "acisweb\@acis60-v:$acis60v_flu",
	       "acisweb\@acisway:$acisway_flu",
	       "acisweb\@ishmael:$ishmael_flu",
	       "acisweb\@aciscdp-v:$aciscdpv_flu");
foreach $destin (@targ_dirs) {
    if($test == 0) {
        print "\n ACE-u.pl: SCP'ing History Files to $destin\m";
	system("scp $hist_fls_str $destin");
    }
    else {
	print ("\nscp $hist_fls_str $destin\n");
    }
}

#---------------------------------------
#create a backup in /data/acis33
#----------------------------------------
print "\nExecuting ephin and CRM codes\n";
if($test == 0){
#Confirm the year directory is there, else create it.
    #Note use the system call to allow a wildcard.
    unless (-d $dir3) {mkdir( $dir3,0775);}
    mkdir("${dir3}/${week}",0775);
    system("cp -r  ${dir2}/${week}/* ${dir3}/${week}/");
    #Execute the ephin and CRM codes
   
    $retCode = system("${base_dir}/LoadReviews/script/crm_saved_time.pl $load_dir");
    if ($retCode < 0) {
	print STDERR "ERROR: crm_saved_time.pl call failed\n";
    }
    if ($isBackup) {
	print "Remember to copy /data/acis-bak/LoadReviews/crm_saved_time_bak.dat to /data/acis\n";
    } else {
	copy("/data/acis/LoadReviews/crm_saved_time.dat","/data/acis-bak/LoadReviews/crm_saved_time_bak.dat");
    }

    $retCode = system("/home/acisdude/perl5/perls/acis_perl_5.16.3-thread-multi/bin/perl ${base_dir}/ephin_plots/code/ephin_orbevents.pl $load_dir");
    if ($retCode < 0) {
	print STDERR "ERROR: ephin_orbevents.pl call failed\n";
	if (! ${isBackup}) {
	    exit(-1);
	}
    }

# Copy to acisweb machines here, since password prompt wasn't passed
# back up to stdout by ephin_orbevents.pl
    $dir = </data/acis/ephin_plots/>;
    print "\n Copying orbevents_2009.rdb to ACIS60-v, acisway, and ACISCDP-V";

    print "\nIf asked, use the acisweb password.\n";
    system("scp $dir/orbevents_2009.rdb acisweb\@aciscdp-v:/export/acis-flight/UTILITIES/orbevents.rdb");
    system("scp $dir/orbevents_2009.rdb acisweb\@acis60-v:/export/acis-flight/UTILITIES/orbevents.rdb");
#
    system("scp $dir/orbevents_2009.rdb acisweb\@acisway:/export/acis-flight/UTILITIES/orbevents.rdb");
#
    system("scp $dir/orbevents_2009.rdb acisweb\@ishmael:/export/acis-flight/UTILITIES/orbevents.rdb");


#----------------------------------------
#report done and check on /data/acis-bak
#----------------------------------------
    if (! $isBackup) {
	print "\nAll copying completed, if script hangs during directory comparison between /data/acis and /data/acis-bak, use CTRL-C.\n";
	
	system("/data/acis/LoadReviews/script/sync_test.pl");
    }
    print "All Done!\n";
    
}#end if test
else{
    print "In testing mode, no copy occurs to backup area\n";
    print "The directories are : $dir\n$dir2\n$dir3\n$load_dir\n";
}

#----------------------------------------
#Mail to acisdude
#----------------------------------------
if($test){
    $recipient=$test_email_recipient;
}

$mailer = Mail::Mailer->new("sendmail");
$mailer->open({ From    => "acisdude\@head.cfa.harvard.edu",
		To      => "${recipient}",
		Subject => "ACE-update.pl has been run",
	    })
    or die "Can't open: $!\n";
$body="ACE-update.pl has just been run. Load used was $load_dir\n";
print $mailer $body;
$mailer->close();
umask($old_umask);


exit();
#end



#--------------------------------------------------------------------
#SUBROUTINES SUBROUTINES SUBROUTINES SUBROUTINES
#--------------------------------------------------------------------


#------------------------------------------------------------
#Function to perform a cat via PERL with file locking
#------------------------------------------------------------
sub internal_cat{
 my($file1,$file2,$outfile)=@_;
 $check_time=0;
 $dec_load=-9999;
 #print "$file1\n";
 $mission=get_last_time("$file1");
 open(FILE1,"< $file1") || die "Error: Cannot read $file1\n";
 flock(FILE1,LOCK_SH) || die "Error: Cannot get a shared lock on $file1\n";
 open(FILE2,"< $file2") || die "Error: Cannot read $file2\n";
 flock(FILE1,LOCK_SH) || die "Error: Cannot get a shared lock on $file2\n";

 open(OUT, "> $outfile")|| die "Error: Cannot write to $outfile\n";;
 flock(OUT, LOCK_EX)|| die "Error: Cannot get an exlusive lock on $outfile\n";
 
 #time check first
 #$mission=<FILE1>; #grab first line to find line length in bytes.
 #seek FILE1,-length($mission),2; #set pointer to last line
 seek FILE2,0,0; #set pointer to first record
 seek FILE1,0,0;

 #$mission=get_last_line(*FILE1);
 #$mission=<FILE1>;
 $load=<FILE2>;
 $dec_mission=parse_time($mission);
 $dec_load=parse_time($load);
 # print "TESTING\n";
 #    print "$mission and $load\n";
 #Check if the mission history ends AFTER Load History
 if($dec_mission > $dec_load){
     $check_time=1; 
 } #end time check


#Reset the file handle pointers to the beginning of the file
 seek FILE1,0,0;
 seek FILE2,0,0;
 #cat the files
 while(<FILE1>){
     if(! $check_time){
	 print OUT $_;
     }
     else{
	 #only print if it is less or equal to first time in the load.
	 $dec_current=parse_time($_);
	 if($dec_current < $dec_load){
	     print OUT $_;
	 }
	 #else{
	 #    print "Did not append $_\n";
	 #}
     }
 }

 while(<FILE2>){
     print OUT $_;
 }
 close(FILE1); #releases the lock
 close(FILE2); #releases the lock
 close(OUT); #releases the lock
 
}
#--------------------------------------------------------------------
#Locks: in English, not binary
#--------------------------------------------------------------------

sub LOCK_SH()  { 1 }     #  Shared lock (for reading)
sub LOCK_EX()  { 2 }     #  Exclusive lock (for writing)
sub LOCK_NB()  { 4 }     #  Non-blocking request (don't stall)
sub LOCK_UN()  { 8 }     #  Free the lock (careful!)


#--------------------------------------------------------------------
#chgrp_by_name
#--------------------------------------------------------------------
sub chgrp_by_name {
    local($group,$pattern) = @_;
    $result=chown($<,(getgrnam($group))[2],$pattern);
    return $result;
}
#--------------------------------------------------------------------
#parse_times
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


#--------------------------------------------------------------------
#confirm_cat: check the files and report time times to append    
#--------------------------------------------------------------------
sub confirm_cat{
     my(%file_hash)=(@_);
     
     print "Checking mission file history times...\nIn dir: $dir\n";
     $check_time=0;
     while (($key, $value) = each(%history_files)) {
	 #$check_time=0;
	 $dec_load=-9999;
	    
	 $file1="$dir/$key.dat";
	 $file2="$load_dir/$value.dat";
	 $mission=get_last_time($file1);
	 #print "The last time returned:\n $mission\n";
	 open(FILE1,"< $file1") || die "Error: Cannot read $file1\n";
	 flock(FILE1,LOCK_SH) || 
	     die "Error: Cannot get a shared lock on $file1\n";
	 open(FILE2,"< $file2") || 
	     die "Error: Cannot read $file2\n";
	 flock(FILE1,LOCK_SH) || 
	     die "Error: Cannot get a shared lock on $file2\n";
	 
	 #time check first
	 
	 seek FILE1,0,0; 
	 seek FILE2,0,0; #set pointer to first record
	 
	 $load=<FILE2>;
         $dec_mission=parse_time($mission);
	 $dec_load=parse_time($load);
	 @time=split(/\s+/,$mission);
	 $mission_time=$time[0];
	 @time2=split(/\s+/,$load);
	 $load_time=$time2[0];
	
	 #Check if the mission history ends AFTER Load History
	 if($dec_mission > $dec_load){
	     print STDOUT "$key.dat: $mission_time to be replaced by $load_time\n";
	     $check_time=$check_time|1;
	 }
	 close(FILE1);
	 close(FILE2);
	 
     }#end all keys
	 
     


	 if($check_time == 1){
	     print STDOUT "\n\nDo you wish to replace the mission history starting at:$load_time?\n[Y/N] ";
	     chop($ans2=<STDIN>); 
	     if ($ans2 !~ /Y/i){ #either upper or lower case
		 print STDERR "You have chosen not to append the history. Please check times in the files and try again.\n";
		 exit;
	     }
	     
	 } #end time check
 }

#--------------------------------------------------------------------
#get_last_line
#--------------------------------------------------------------------
sub get_last_line(){
    local (*FH)=(@_);
    my $pos=-1;
    my $char;
    my $already_nonblank = 0;
    
    while (seek (FH,$pos--,2))
    {
	read FH,$char,1;
	last if ($char eq "\n" and $already_nonblank == 1);
	$already_nonblank = 1 if ($char ne "\n");
    }
    
return  <FH>;
}

#--------------------------------------------------------------------
#get_last_time(){
#--------------------------------------------------------------------
sub get_last_time(){
    my($filename)=(@_);
    @list=`tail -2 $filename`;
    if($list[1] =~ /9999:999/){
	return $list[0];
    }
    else{return $list[1]};
}
