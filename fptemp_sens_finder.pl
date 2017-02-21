#!/usr/bin/env perl
#--------------------------------------------------------------------
#fptemp_sens_finder.pl: combs the archive for items that fit the 
#                       criteria for being focal plane 
#                       temperature sensitive.
#
# UPDATE - December 22, 2016
#          Gregg Germain
#          V1.4
#          Changed from "Browser" username to "acisops" for access
#          to the OCAT
#--------------------------------------------------------------------
use DBI;
use Text::ParseWords;
use IO::File;
use File::Basename;
use Getopt::Std;
use Getopt::Long;


#------------------------------
#local variables
#------------------------------
@targetlist=();
@fivecnts_6ccd=();
@fivecnts_5ccd=();
@tencnts_6ccd=();
@tencnts_5ccd=();
$opt_count=0;
$ccd_count=0;
$optional='N';

#------------------------------
#collect optional arguments
#and set defaults
#------------------------------
 GetOptions( 's=s' => \$server,
	     'c=s' => \$ao,           #Can be comma delimited list
	     'o=s' => \$outfile,
	     'help|h',\$help);

if($help){&print_help();exit();}

if(!$server){
    $server="ocatsqlsrv";
}
if(!$ao){
    $ao=13;
}
if(!$outfile){
    $outfile="thermal_sensitive.txt";
}

#--------------------------------------------------
#Parse the ao information and build the proper search string
#--------------------------------------------------
@tmp_ao = split(/\,|\:/, $ao);


#print "The call to the database is $ao_final_call\n";
#------------------------------
#Connect to the database:
#database username, password, and server
#------------------------------
#$user="browser";
#$passwd="newuser";

# NEW OCAT USERNAME database username, password, and server
$user="acisops";
$passwd="gpCjops)";

$serverstr="dbi:Sybase:${server}";

#open connection to sql server
my $dbh = DBI->connect(($serverstr, $user, $passwd)) || die "Unable to connect to database". DBI->errstr;
# use axafocat and clean up
$dbh->do(q{use axafocat}) || die "Unable to access database axafocat". DBI->errstr;

#----------------------------------------
# COLLECT FROM TABLE
# get stuff from acis table, clean up
# CHANGE HERE FOR CALL TO ARCHIVE
#---------------------------------------

foreach $t (@tmp_ao){
    $sth2=$dbh->prepare(q{select seq_nbr, obsid,instrument,ccdi0_on,ccdi1_on,ccdi2_on,ccdi3_on,ccds0_on,ccds1_on,ccds2_on,ccds3_on,ccds4_on,ccds5_on,multiple_spectral_lines,spectra_max_count,obs_ao_str from target,acisparam where (target.acisid = acisparam.acisid) and (instrument = 'ACIS-I') and (grating = 'NONE') and (obs_ao_str=?)});
    
    
    $sth2->execute($t) || die "Unable to query acisparam" . $sth->errstr;
    $acisdata_ref = $sth2->fetchall_arrayref();
    $sth2->finish();
    
    
    
    #------------------------------
    #go through each row, parse data and 
    #perform logic to place this in the 
    #correct data bin
    #------------------------------
    foreach $acisdata (@{$acisdata_ref}){
	# define stuff from acis table
	($seq_num,$obsid,$inst,$i0,$i1,$i2,$i3,$s0,$s1,$s2,$s3,$s4,$s5,$msl,$smc,$obs_ao_str)=@$acisdata;
	
	#Determine the actual CCD number on, off and optional
	$opt_count=0;
	$ccd_count=0;
	$optional='N';
	$drop=0;             ##################Don't Deal with Dropped CCDs YET
	@ccdarray=($i0,$i1,$i2,$i3,$s0,$s1,$s2,$s3,$s4,$s5);
	for($ii=0;$ii<10;$ii++){
	    if(@ccdarray[$ii] =~/O/){
		$optional='Y';
		$opt_count++;
		$foo=substr(@ccdarray[$ii],1,1);        
		if ($foo <= $drop){
		    @ccdarray[$ii]= "N";
		} else{
		    @ccdarray[$ii]="O";
		}
	    }
	    
	    if(@ccdarray[$ii] !~/N/){
		$ccd_count=$ccd_count+1;
	    }
	}
	
	$ccdstr=join("",@ccdarray);
	
	#informational
	#print "obsid=$obsid the optional is $optional, the count is $ccd_count\n";   
	
	#Build output string
	$str="$seq_num\t$obsid\t$smc\t$msl\tReq:$ccd_count\tOpt:$opt_count\t$ccdstr\t$obs_ao_str\n";
	
	if($smc >5000 &&
	   $msl =~ /Y/ &&
	   $ccd_count == 6 &&
	   $optional =~  /N/ ){
	    push(@fivecnts_6ccd,$str);
	}
	if($smc >5000 &&
	   $msl =~ /Y/ &&
	   ($ccd_count < 6 || ($ccd_count == 6 && $optional =~ /Y/))){
	    push(@fivecnts_5ccd,$str);
	}
	if($smc >30000 &&
	   $msl =~ /N/ &&
	   $ccd_count == 6 &&
	   $optional =~ /N/){
	    push(@tencnts_6ccd,$str);
	}
	if($smc >30000 &&
	   $msl =~ /N/ &&
	   ($ccd_count < 6 || ($ccd_count == 6 && $optional =~ /Y/))){
	    push(@tencnts_5ccd,$str);
	}
	
    } #end  each element
}#end each AO
#------------------------------
#open outfile and write elements to the file
#------------------------------


open(OUT,"> $outfile") ||warn "couldn't open out\n";
print OUT "Seq\tobsid\tcnts\tLines\tCCD counts\tActual CCDs\tAO\n";
#print OUT "Obsids with greater than 5,000 cnts, Multiple spectral lines, 6 CCDs\n";



@outarray=(@fivecnts_6ccd,@fivecnts_5ccd,@tencnts_6ccd,@tencnts_5ccd);
@outarray=sort(@outarray); #sort by sequence number

foreach $item(@outarray){
    print OUT "$item";
}
close(OUT);
exit(1);




#--------------------------------------------------------------------------------
# function: print help
#                     if -h option is used, this is printed
#--------------------------------------------------------------------------------

sub print_help(){
    
    print "  fptemp_sens_finder.pl -c <string with AO Cycles (comma delimited)> -s <ocat server name> -o <outputfile> -h\n";
    print "\n";
    print "This script will select all of the obsids that have been classified as focal\n";
    print "plane temperature sensitive. The default AO Cycle is 13, which can be overridden\n";
    print "with the -c <string> command. Multiple AOs can be searched by using a comma\n";
    print "delimited list. The default output file name is \"thermal_sensitive.txt\".\n"; 
    print "Use the -o <filename> option to overide this name.\n";
    print "The -s <server name> will override the default server in the case that the \n";
    print "main server is down. The -h option prints this text.\n\n";
    print "EXAMPLES\n\n";
    print "  fptemp_sens_finder.pl -c 13,14 -o cycles_13_14.txt\n\n";
    print "\tThis command will collect all temperature senstive observations\n";
    print "\tfrom cycles 13 and 14 and use \"cycles_13_14.txt\" as an output.\n\n";
    print "  fptemp_sens_finder.pl -c 13 \n\n";
    print "\tThis command will collect all temperature senstive observations\n";
    print "\tfrom cycle 13 and 14  \"thermal_sensitive.txt\" as an output.\n";
    

}
	
    
