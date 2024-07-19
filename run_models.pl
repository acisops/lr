#!/usr/bin/env perl
#--------------------------------------------------------------------
# run_models: 
# 
# This is a wrapper script that calls the ska thermal models
# In the case of the machine executing this script is NOT Linux, there
# is an ssh call to a Linux machine. (acis.harvard.edu, can use the -h host option 
# to override)
#
# This code should fail any particular script and continue on if there 
# is an issue. 
#
# This is version 1.10, which replaces version 1.9
#
# Update: March 8, 2018
#         Gregg Germain
#         Included nlet_file switch to allow users to specify an
#         alternate nlet file
#            - Default is /data/acis/LoadReviews/NonLoadTrackedEvents.txt
#
#
# Update: November 22, 2019
#         Gregg Germain
#         HTTP -> HTTPS; Remove -dmz from web server path
#         V1.14
#
#
# Update: April 24, 2020
#         John ZuHone
#         Make BEP and FEP models run from $SKA
#         V1.15
#
# Update: June 15, 2022
#         Gregg Germain
#         V1.16
#         - Remove the no longer needed call to make_dhheater_history.csh
#            - Broken under RH8/DS10.11
#         - Print a line indicating what thermal model is about to be run
#
# Update: June 3, 2024
#              Gregg Germain
#              V1.17
#              - Add the necessary code to run the new 1DPAMYT thermal model
#
#--------------------------------------------------------------------
use POSIX qw(uname);
use Cwd;
use File::Copy;
use File::Path;
use Archive::Tar;
use Getopt::Std;
use Getopt::Long;

#use Net::SSH;
#Check we are on linux
# add a switch to linux machine to use
#Check for options: will remove options from argv
#------------------------------
$myhost='acis.cfa.harvard.edu';
$break = 0;
$nlet_file = <\\"/data/acis/LoadReviews/NonLoadTrackedEvents.txt\\">;

GetOptions('h=s' => \$myhost, #host to run on.
	   'p=s' => \$path, # optional path 
           'break' => \$break,
           'nlet_file=s' => \$nlet_file);
#note: add a help option
my ($OS ,$machine, $rev,$ver, $processor)  = (POSIX::uname());

#------------------------------
# Collect arguments
#------------------------------
$argc = @ARGV;
$argc >= 1  or die "ERROR, incorrect arguments: Usage: run_model.pl LoadName(with version) [-p directory not the default] [-h host to run if not solaris]\n\n";
$load = @ARGV[0];


$ver=chop($load);
$ver=~ tr/A-Z/a-z/;

#------------------------------
#set the directories to use
#------------------------------
$year=substr($load,5,2);
$appx = `lr_suffix.pl`;  # Null string or "-bak"

#directory definitions
if(-d $path){    
    $lr_dir=$path;
}
else{
    $lr_dir = </data/acis${appx}/LoadReviews/20${year}/$load/ofls>;
}
if ($appx) {  # On backup machine?
    $webroot = "/data/anc/apache/htdocs/acis";
} else {
    $webroot = "/proj/web-cxc/htdocs/acis";
}
#------------------------------
# Set the out directories for the webpages
#------------------------------
$outdir=<${webroot}/PSMC_thermPredic/$load/ofls${ver}/>;
$dpadir=<${webroot}/DPA_thermPredic/$load/ofls${ver}/>;

# New web directory for the 1DPAMYT thermal model
$dpamytdir=<${webroot}/DPAMYT_thermPredic/$load/ofls${ver}/>;

$deadir=<${webroot}/DEA_thermPredic/$load/ofls${ver}/>;
$fpdir=<${webroot}/FP_thermPredic/$load/ofls${ver}/>;
$fep1acteldir=<${webroot}/FEP1_ACTEL_thermPredic/$load/ofls${ver}/>;
$fep1mongdir=<${webroot}/FEP1_MONG_thermPredic/$load/ofls${ver}/>;
$beppcbdir=<${webroot}/BEP_PCB_thermPredic/$load/ofls${ver}/>;

#----------------------------------
# Untar the backstop file if needed.
#---------------------------------
$current=cwd();
chdir $lr_dir;
$backstop=`ls $lr_dir/C*.backstop`;
chop($backstop);
# If the backstop file exists, then use it. Otherwise, pull it out of the tar
# file.
unless (-f $backstop){
    print "\tHave to extract backstop file out of the tar file\n$backstop";
    $tarfile=`ls $lr_dir/*backstop.tar.gz`;
    chop($tarfile);
    unless (-f $tarfile){ #check for the unzipped version
	$tarfile=`ls $lr_dir/*backstop.tar`;
	chop($tarfile);
	unless (-f $tarfile){
               die "Can not find a backstop.tar.gz or backstop.tar file in the directory $lr_dir\n";
        }
    }
    my $tar = Archive::Tar->new;
    $tar->read($tarfile);
    @mylist=$tar->list_files();
    foreach $ml (@mylist){	
	if ($ml =~ '.backstop'){
            $back=$ml;
            break;
        }
    }
    unless("${back}" =~ /backstop/){
	die "No backstop file found in $tarfile. $back\n";
    }
    $tar->extract($back);
} #backstop


# If an interrupt, we need to supply a flag to the models
# (except the focal plane model)

if ($break == 1) {
    $break_str = "--interrupt";
} else {
    $break_str = "";
}

#---------------------------------------------
#Set up the ska environment to run
#---------------------------------------------

$ska = '/proj/sot/ska3/flight';
$ENV{'SKA'} = $ska;

#Commands to execute: (BUT NOT EXECUTED YET)

# NLET-PSMC
$psmc_ska_str = "${ska}/bin/psmc_check --oflsdir=${lr_dir} --out ${lr_dir}/out_psmc --nlet_file ${nlet_file} --verbose=0 $break_str";

# NLET-DPA
$dpa_ska_str = "${ska}/bin/dpa_check --oflsdir=${lr_dir} --out ${lr_dir}/out_dpa --nlet_file ${nlet_file}  --verbose=0 $break_str";

# NLET-DPAMYT
$dpamyt_ska_str = "${ska}/bin/dpamyt_check --oflsdir=${lr_dir} --out ${lr_dir}/out_dpamyt --nlet_file ${nlet_file}  --verbose=0 $break_str";

# NLET-DEA
$dea_ska_str = "${ska}/bin/dea_check --oflsdir=${lr_dir} --out ${lr_dir}/out_dea --nlet_file ${nlet_file}  --verbose=0 $break_str";

# NLET-FPTEMP
$fp_ska_str = "${ska}/bin/acisfp_check --oflsdir=${lr_dir} --outdir=${lr_dir}/out_fptemp --nlet_file ${nlet_file}  --verbose=0 $break_str";

$fep1mong_ska_str = "${ska}/bin/fep1_mong_check --oflsdir=${lr_dir} --out ${lr_dir}/out_fep1_mong --nlet_file ${nlet_file}  --verbose=0 $break_str";
$fep1actel_ska_str = "${ska}/bin/fep1_actel_check --oflsdir=${lr_dir} --out ${lr_dir}/out_fep1_actel --nlet_file ${nlet_file}  --verbose=0 $break_str";
$beppcb_ska_str = "${ska}/bin/bep_pcb_check --oflsdir=${lr_dir} --out ${lr_dir}/out_bep_pcb --nlet_file ${nlet_file}  --verbose=0 $break_str";

#------------------------------
# items to run
#------------------------------
@executables=( $psmc_ska_str,
                            $dpa_ska_str,
	                    $dpamyt_ska_str,
                            $dea_ska_str,
                            $fp_ska_str,
	                    $fep1mong_ska_str,
	                    $fep1actel_ska_str,
	                    $beppcb_ska_str);

# IF we can't execute this on this machine, then run it on acis
if ($OS !~ /Linux/i ||
    $processor !~ /x86_64/){
    print "\tThis host, ${machine} ${processor}, cannot run the psmc_check.\n\tUsing SSH to connect to ${myhost} to run psmc_check.\n";
    #fork a process to acis to run the PSMC code
    foreach $item (@executables)
     {
	my $pid = fork();
	if (not defined $pid) {
	    print "ERROR>>>resources not avilable. $0 cannot execute model runs.\n";
	} 
	elsif ($pid == 0) { 
	    exec("ssh $myhost $item");
	    exit(0);
	}
	else {
	    waitpid($pid,0);
	}
    } #end foreach loop
}
else{
    foreach $item (@executables)
    {
	# Get the position of the first space in the model execution string
	$first_space_pos = index($item, " ");
	# Extract the substring from the start of the command to the first space
	$model_to_be_run = substr($item, 0, $first_space_pos);
	
	print "\nExecuting model: $model_to_be_run\n";
	
	$ret=system($item);
	if ($ret != 0){
	    print "$item failed to execute properly\n. $!\n";
	}
      } #end foreach loop
}

#Only copy to webpage area IF WE DIDN'T GIVE ALTERNATE PATH
unless ($path){
    print "copy for webpages\n";
    #Copy files to the webarea
    unless ( -d $outdir){
	mkpath($outdir,0777);
    }
    unless (-d $dpadir){
	mkpath($dpadir,0777);
    }

    unless (-d $dpamytdir)
      {
	mkpath($dpamytdir,0777);
      }
    
    unless (-d $deadir){
        mkpath($deadir,0777);
    }
    unless (-d $fpdir){
        mkpath($fpdir,0777);
    }
    unless (-d $fep1mongdir){
        mkpath($fep1mongdir,0777);
    }
    unless (-d $fep1acteldir){
        mkpath($fep1acteldir,0777);
    }
    unless (-d $beppcbdir){
        mkpath($beppcbdir,0777);
    }
    system("cp -p ${lr_dir}/out_psmc/*.* ${outdir}");   
    system("cp -p ${lr_dir}/out_dpa/*.* ${dpadir}");
	
    system("cp -p ${lr_dir}/out_dpamyt/*.* ${dpamytdir}");
	
    system("cp -p ${lr_dir}/out_dea/*.* ${deadir}");
    system("cp -p ${lr_dir}/out_fptemp/*.* ${fpdir}");
    system("cp -p ${lr_dir}/out_fep1_mong/*.* ${fep1mongdir}");
    system("cp -p ${lr_dir}/out_fep1_actel/*.* ${fep1acteldir}");
    system("cp -p ${lr_dir}/out_bep_pcb/*.* ${beppcbdir}");

}
chdir $current;

exit;
