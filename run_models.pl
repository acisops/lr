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

GetOptions('h=s' => \$myhost, #host to run on.
	   'p=s' => \$path, # optional path 
           'break' => \$break);
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
    $webroot = "/proj/web-cxc-dmz/htdocs/acis";
}
#------------------------------
# Set the out directories for the webpages
#------------------------------
$outdir=<${webroot}/PSMC_thermPredic/$load/ofls${ver}/>;
$dpadir=<${webroot}/DPA_thermPredic/$load/ofls${ver}/>;
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
$ska=</proj/sot/ska/bin>;
#Commands to execute: (BUT NOT EXECUTED YET)
# make detector housing heater history file
$dhhtr_history_str="/data/acis${appx}/LoadReviews/script/make_dhheater_history.csh";
$psmc_ska_str = "${ska}/psmc_check --oflsdir=${lr_dir} --out ${lr_dir}/out_psmc --verbose=0 $break_str";
$dpa_ska_str = "${ska}/dpa_check --oflsdir=${lr_dir} --out ${lr_dir}/out_dpa --verbose=0 $break_str";
$dea_ska_str = "${ska}/dea_check --oflsdir=${lr_dir} --out ${lr_dir}/out_dea --verbose=0 $break_str";
$fp_ska_str = "${ska}/acisfp_check --oflsdir=${lr_dir} --outdir=${lr_dir}/out_fptemp --verbose=0 $break_str";

$fep1mong_ska_str = $ENV{"HOME"} . "/.local/bin/fep1_mong_check --oflsdir=${lr_dir} --out ${lr_dir}/out_fep1_mong --verbose=0 $break_str";
$fep1actel_ska_str = $ENV{"HOME"} . "/.local/bin/fep1_actel_check --oflsdir=${lr_dir} --out ${lr_dir}/out_fep1_actel --verbose=0 $break_str";
$beppcb_ska_str = $ENV{"HOME"} . "/.local/bin/bep_pcb_check --oflsdir=${lr_dir} --out ${lr_dir}/out_bep_pcb --verbose=0 $break_str";

#------------------------------
# items to run
#------------------------------
@executables=($dhhtr_history_str,
	      $psmc_ska_str,
	      $dpa_ska_str,
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
    foreach $item (@executables){
	my $pid = fork();
	if (not defined $pid) {
	    print "ERROR>>>resources not avilable. $0 canot execute model runs.\n";
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
    foreach $item (@executables){
	
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
    system("cp -p ${lr_dir}/out_dea/*.* ${deadir}");
    system("cp -p ${lr_dir}/out_fptemp/*.* ${fpdir}");
    system("cp -p ${lr_dir}/out_fep1_mong/*.* ${fep1mongdir}");
    system("cp -p ${lr_dir}/out_fep1_actel/*.* ${fep1acteldir}");
    system("cp -p ${lr_dir}/out_bep_pcb/*.* ${beppcbdir}");

}
chdir $current;

exit;
