#! /usr/bin/env perl
use Sys::Hostname;

########################################################################
#MachinPath.pm:
#
# Current routines: GetPathandNode([host])
#                   GetFluMon([host])
#                   GetRTpath([host])
#                   GetPMONpath([host])
#                   GetWebPath([host])
#
#------------------------------------------------------------
#   Subroutine GetPathandNode - Determines the name of the machine this code
#                        is executing on, and sets the variable $root
#                        to the appropriate "root" path for that machine.
#
#                        In addition, it returns the name of the machine.
#
#               inputs - Can use none OR take a hostname.
#
#              outputs - $root, $nodename
#
#---------------------------------------------------------------
#   Subroutine GetFluMon - returns the top of the fluence monitor 
#                          directory path based on the host.
#
#               inputs - Can use none OR take a hostname.
#
#              outputs - $root
#--------------------------------------------------------------------
#   Subroutine GetRTpath - returns the top of the real-time 
#                          (before acis/bin) directory path based 
#                          on the host
#
#               inputs - Can use none OR take a hostname.
#
#              outputs - $root
#---------------------------------------------------------------
#   Subroutine GetPMONpath - returns the top of the PMON
#                          directory path based on the host.
#
#               inputs - Can use none OR take a hostname.
#
#              outputs - $root or "" if PMON is not hosted on that machine
#--------------------------------------------------------------------
#   Subroutine GetRTpath - returns the top of the web page 
#                          directory path based on the host
#
#               inputs - Can use none OR take a hostname.
#
#              outputs - $root
#
#       Update: March 10, 2016
#          Gregg Germain
#          Fixed numerous typos such as:
#                       "aciscdp-v-v" "acisocc-c"
#              	        "acisocc-v-v","/export/acis-flight/"
#                       "acis60-c","/export/acis-flight/",    
#                       "aciscdp-c","/export/acis-flight/");
#                       "aciscdp","/proj/web-cxc-dmz/htdocs/acis");
#
#######################################################################

#-------------------------------
# global variables:
# All directory and machine pairs
# are stored in hashes with the 
# exception of the FLU-MON location 
# on the HEAD-LAN.
#
# All changes should only be made here 
# and this file should allow
# the different machines to 
# access the same scripts.
#
#
#--------------------------------
#MAIN TOP LEVELS
#--------------------------------
%hash_top=("han-v","/export/acis-flight/",
	   "luke-v","/export/acis-flight/",
	   "colossus-v","/export/acis-flight/",
	   "acisocc-v","/export/acis-flight/",
	   "acis60-v","/export/acis-flight/",
	   "aciscdp-v","/export/acis-flight/",
	   "acis","/proj/sot/acis/FLU-MON/",
);

#--------------------------------------------------
#FLU-MON: SPECIAL CASE : historical location
#--------------------------------------------------
$HEAD_flu="/proj/sot/acis/FLU-MON/";

#--------------------
#ENG BIN
#--------------------
%hash_eng=("han-v","/export/acis-flight/",
           "luke-v","/export/acis-flight/",
           "colossus-v","/export/acis-flight/",
           "acisocc-v","/export/acis-flight/",    
           "acis60-v","/export/acis-flight/",    
           "aciscdp-v","/export/acis-flight/");
#--------------------
#PMON BIN
#--------------------
%hash_pmon=( "han-v", "/export/acis-flight/acis/PMON/",
	    "colossus-v", "/export/acis-flight/acis/PMON/",
	    "luke-v", "/export/acis-flight/acis/PMON/",
	    "acisocc-v","/export/acis-flight/acis/PMON",    
	    "acis60-v","/export/acis-flight/acis/PMON",    
	    "aciscdp-v","/export/acis-flight/acis/PMON");

#--------------------
#WEB AREA
#--------------------
%hash_web=("han-v", "/proj/web-cxc-dmz/htdocs/acis/RTHANV/",
	   "luke-v", "/proj/web-cxc-dmz/htdocs/acis/RTLUKEV/",
	   "colossus-v", "/data/asc1/htdocs/acis/RTCOLOSSUSV",
	   "acisocc-v", "/data/anc/apache/htdocs/acis",
	   "acis60-v", "/data/wdocs/acisweb/htdocs/acis",
	   "aciscdp-v","/proj/web-cxc-dmz/htdocs/acis");

#--------------------------------------------------------------------
#INTERNAL TO THE LIBRARY CODE
#--------------------------------------------------------------------
sub GetPathandNode 
{
    #check if there is a host name passed to function
    my $host = $_[0];
    my $mod = $_[1];
    $root="x";
    #
    # Accept host as a variable input. If no host is specified, 
    # the use the hostname function.
    #

    if ($host !~ /^[a-z]/){
	$host = hostname();
    }

    $root=$hash_top{$host};

    if($root =~ /^x/){
	print STDOUT "The host $host is assumed to be on the HEAD LAN\n";
	$root=$hash_top{"han-v"};
	$host = "han-v";
    }
        return ($root, $host);
 
} # End SUB GETPATH


#--------------------------------------------------------------------
# GetFluMon: return the directory for FLU-MON code and files
#--------------------------------------------------------------------
sub GetFluMon
{
    #check if there is a host name passed to function
    my $host = $_[0];
    
    #
    # Accept host as a variable input. If no host is specified, 
    # the use the hostname function.
    #

    if ($host !~ /^[a-z]/){
	$host = hostname();
    }

    ($top,$hostname)=GetPathandNode($_[0]);
    # ACE-update.pl and history-files.pl key on 'xcanuck' to
    # get the global history file directory.
    # Realtime fluence scripts *may* key on 'acis' similarly.
    unless ($hostname =~ /xcanuck/i )
      {
	$root="${top}FLU-MON/";
      }
    else
      {
	$root=$HEAD_flu;
      }
    return($root);
    
    
} # End SUB GetFluMon

#--------------------------------------------------------------------
# GetRTpath: return the directory path for the eng-bin area
#--------------------------------------------------------------------
sub GetRTpath
{
    #check if there is a host name passed to function
    my $host = $_[0];
    
    #
    # Accept host as a variable input. If no host is specified, 
    # the use the hostname function.
    #
    
    if ($host !~ /^[a-z]/){
	$host = hostname();
    }
     $root=$hash_eng{$host};   

    if($root =~ ""){
	print STDOUT "The host $host is assumed to be on the HEAD LAN\n";
	$root=$hash_eng{"han-v"};
	$host = "han-v";
    }

    return($root);
} # End SUB GetRTpath


#--------------------------------------------------------------------
# GetPMONpath: return the directory path for the PMON binary area
#--------------------------------------------------------------------
sub GetPMONpath
{
    #check if there is a host name passed to function
    my $host = $_[0];

    #
    # Accept host as a variable input. If no host is specified, 
    # the use the hostname function.
    #

    if ($host !~ /^[a-z]/){
	$host = hostname();
    }
    
    $root=$hash_pmon{$host};   
 
    if(! $root){
	print STDERR "Host $host does not host a PMON session.\n";
	$root="";
    }
    return($root);    
} # End SUB GetPMONpath

#--------------------------------------------------------------------
# GetWebPath: return the directory path for the Web location
#--------------------------------------------------------------------
sub GetWebPath
{
#check if there is a host name passed to function
    my $host = $_[0];
    
    #
    # Accept host as a variable input. If no host is specified, 
    # the use the hostname function.
    #

    if ($host !~ /^[a-z]/){
	$host = hostname();
    }
    $root=$hash_web{$host}; 
    
    if($root =~ ""){
	print STDOUT "The host $host is assumed to be on the HEAD LAN\n";
	$root=$hash_web{"han-v"};
	$host = "han-v";
    }
      
    return($root);    
} # End SUB GetWebPath

