#! /usr/bin/env perl
# lr_regress_check.pl
#
# A simple series of comparisons between files in the working directory
# and similarly named files in the directory named by the -o switch.
# The latter are the expected data out of a regression test run of
# a load review script.
# Most of the comparisons are simply diffs. However,
#   - In ACIS-LoadReview.txt, the "Exposure Time" lines will
#   always differ. These were grepped out of the comparison files,
#   and this script greps them out of the regression run outputs.
# There are two output files. <case>_regress.log states which
# files were compared, with a result of either "***PASS***"
# or "***FAIL***\n  differences". <case>_alldiffs concatenates the diff files,
# with the exception of the ACIS Tables .cfg diff file, since
# it will always either be empty or consist of all records. 
# 
# Environment: "REGOUT" points to the directory containing
# the expected output files for the current regression case.
# The $REGOUT directory also contains difflist.txt,
# a list of the files to be compared.
# "CASE" defines which regression case is under test, and
# will be a component of a number of output file names.
# "SGDAT" is the (test) version of SGDAT, to be defined in
# ~/acis_source
# $Date: 2012/06/13 18:52:20 $
# $Log: lr_regress_check.pl,v $
# Revision 1.8  2012/06/13 18:52:20  royceb
# Include scenario in environment description at start of diff file.
#
# Revision 1.7  2012/04/13 19:42:52  royceb
# Skip even existence checks for LRHS if scenario is BACKS.
#
# Revision 1.6  2012/02/16 19:41:50  royceb
# If scenario is H_AND_S, check only the HandS report.
#
# Revision 1.5  2011/12/20 21:09:19  royceb
# If the scenario is BACKS, don't check for the existence-only outputs.
#
# Revision 1.4  2011/11/29 21:42:00  royceb
# No error return on 'FAIL' message - allow next case to run.
# Check for presence of output file before diffing.
#
# Revision 1.3  2011/11/10 21:58:04  royceb
# Note Date and Log in these comments.
#
#---------------------------------------------------------------

$sgdat = $ENV{"SGDAT"};
$appx = `lr_suffix.pl`;
$regress = $ENV{"REGRESS"};
$reg_case = $ENV{"CASE"};
if ($reg_case =~ /.(\d\d)(\d\d)/) {
    $case_yr = "20$2";
}
$scenario = $ENV{"SCEN"};
$ld_dir = "RG_$reg_case";
$ldRevision = chop $ld_dir;
$ld_dir = "/data/acis${appx}/LoadReviews/$case_yr/\U$ld_dir" . "/ofls$ldRevision";
$regout = $ENV{"REGOUT"};
$qcheck = 0;  # Flag to quick-check, only for presence of output file
$dy = "ddd_yyyy";   # Date encoded in backstop filename
$saw_diffs = 0;

$precis = "qwik_regr.log";  # File for test results compressed and consolidated
$allall = "qwik_alldiffs";  # File to conjoin diffs from all cases

&parseCmdLn();

# Determine operating system
$platform = "unknown";
open(OSNM, "/bin/uname -a |") || die 
  "Couldn't open pipe to uname\n";
while (<OSNM>) {
    $platform = substr($_, 0, 5); 
}
close (OSNM);

# Determine doy_year string in filenames.
opendir RESLTS, $ld_dir;
@allOutFiles = readdir RESLTS;
closedir RESLTS;
for ($fx = 0; $fx <= $#allOutFiles; $fx++) {
    if ($allOutFiles[$fx] =~ /CR(\d+_\d+).backstop/) {
	$dy = $1;
	last;
    }
}

#---------------------------------------------------------------
open (DIFFS, ">$reg_case" . "_regr.log") || die
    "Couldn't open $reg_case" . "_regr.log for output.\n";

$punch_flnm = "$regout/difflist.txt";
print DIFFS "\$SGDAT is $sgdat\n";
print DIFFS "\$REGRESS is $regress\n";
print DIFFS "Scenario is $scenario\n".
print DIFFS "\$CASE is $reg_case\n";
print DIFFS "\$REGOUT is $regout.\n";
close DIFFS;
system("echo \"Differences found for $reg_case\:" > "$reg_case" 
       . "_alldiffs\"");

# Process list of files to be compared.
open(PUNCH, "<$punch_flnm") || die
    "Couldn't open $punch_flnm for input.\n";
$qcheck = 0;
while (<PUNCH>) {
    if ($_ =~ /^#.*/) {  # Comment line?
	next;             # ignore
    }
    if ($scenario eq "H_AND_S") {  # In hands scenario, compare only HandS
	if (! ($_ =~ /HandS.txt/)) {
	    next;
	}
    }
    if ($scenario eq "BACKS") { # Other script outputs - not even exist check
	if ($_ =~ /presence of/) {
	    last;
	}
	if ($_ =~ /HandS.txt/) {
	    next;
	}
    }
    if ($_ =~ /presence of/) {
	$qcheck = 1;
	next;
    }
    if ($_ =~ /MNVR_SUMMARY_CR(.*).txt/) {
	# Fill in specific date for expected maneuver summary file
	$_ =~ s/$1/$dy/g;
    }
    chop;
    $saw_diffs = 0;
    &compare("$regout/$_", "$ld_dir/$_");
}
close PUNCH;

#------------------------------------------------------------------
# compare accepts two pathnames, and compares the two files.
# Writes second filename on DIFFS. If the two don't differ,
# writes "PASS" message on DIFFS. If they do, displays differences.
# Special handling for napc2par.log and for *.idp.
#------------------------------------------------------------------
sub compare {
    my ($regPath, $tstPath) = @_;
    my ($tstFlNm, $isSpecial);
    $tstPath =~ /.*\/(.*)/;
    $tstFlNm = $1;  # File to be tested, with pathname stripped.
    $isSpecial = 0;
    if ($tstFlNm eq "ACIS-LoadReview.txt") {  
	$isSpecial = 1;
    } 

    if ($isSpecial) {
       &comparePrep($tstPath);
    }
    open (DIFFS, ">>$reg_case" . "_regr.log") || die
	"Couldn't open $reg_case" . "_regr.log for appending.\n";
    open(SIGMA, ">>$precis") || die
	"Couldn't open $precis for appending.\n";
    $echo_str = "Comparing $tstPath to $regPath.\n";
    if (-f "$tstPath") {
	if ($qcheck) {
	    print DIFFS "$tstPath - file found\n***PASS***\n";
	}
    } else {
	$failrpt =  "$tstPath - not found\n***FAIL***\n";
	print DIFFS  $failRpt;
	$saw_diffs = 1;
	close DIFFS;
	print SIGMA $failRpt;
	close SIGMA;
	return;
    }
    if ($qcheck) { # Check only for existence of file?
	close DIFFS;    
	return;
    }
    system( "diff $regPath $tstPath > tmp.dif");

    print DIFFS $echo_str;
    if ((! -e $tstPath) || (! -e $regPath)) {
	$saw_diffs = 1;
	print DIFFS "Both comparison files must exist.\n";
	close DIFFS;
	print SIGMA  $echo_str . "Both comparison files must exist.\n";
	close SIGMA;
	die "Couldn't compare nonexistent file.\n";
    }

    stat("tmp.dif");
    # NB: Single underscore below signifies the handle for the most 
    # recently returned stat results. Perl saved me five or six chars
    # of typing with this shortcut, requiring this 3 line explanation.
    if ( -s _) {   # tmp.dif nonempty?
	$fail_rpt = "***FAIL*** differences found\n";
	print DIFFS $fail_rpt;
	print SIGMA "$reg_case\: $echo_str$fail_rpt";
	$saw_diffs = 1;
    } else {
	print DIFFS "***PASS***\n";
    }
    close DIFFS;
    close SIGMA;
    if ($tstPath =~ ".cfg") {
	# ACIS Tables cfg file will only clutter alldiffs with all
	# records, so skip it.
	;
    } else {
	if ($saw_diffs) {
	    open(ALLALL, ">> $allall");
	    print ALLALL "$reg_case\: $echo_str";
	    close ALLALL;
	    system ("cat tmp.dif >> $allall");
	}
	system ("cat tmp.dif >> $reg_case" . "_alldiffs");
    }
}

#------------------------------------------------------------------
# comparePrep accepts a pathname.
# It opens the file and massages out idiosyncracies that might 
# keep it from comparing to the corresponding regression output file.
#------------------------------------------------------------------
sub comparePrep {
    my ($flNm) = @_;
    if ($flNm == "ACIS-LoadReview.txt") {
	open(TMP, "<$flNm") || die 
	    "Error: Could not open $flNm for input.\n";
	open(TMPOUT, ">alrtxt.tmp") || die 
	    "Error: Couldn't open alrtxt.tmp for output.\n";
    } else {
	return;
    }

    while (<TMP>) {
	$theLn = $_;
	if ($theLn =~ /Exposure Time/) {
	    next;
	}
	if ($theLn =~ /(.*)acis-bak(.*)/) {  # Regression on backup machine?
	    $theLn = $1 . "acis" . $2 . "\n";
	}
	print TMPOUT "$theLn";
    }
    close TMP;
    close TMPOUT;
    system ("mv  alrtxt.tmp $flNm");
}

#--------------------------------
# Interpret the command line.
#--------------------------------
sub parseCmdLn {
    while (@ARGV) {
	$arg = shift(@ARGV);
	if ($arg eq "-h" || $arg eq "-H") {   # help
	    &displayUsage();
	    exit;
	}
	if ($arg eq "-o") {
	    $regout = shift(@ARGV);
	    next;
	}
	if ($arg eq "-r") {
	    $regress = shift(@ARGV);
	    next;
	}
	if ($arg eq "-s") {
	    $reg_case = shift(@ARGV);
	    next;
	}
	print STDERR "Error: Unrecognized cmd line switch $arg.\n";
	&displayUsage();
	exit -1;
    }
    if (! $reg_case || ! $regout || ! $regress) {
	print STDERR "Error: Environment must define CASE, REGOUT, " .
	    "and REGRESS\n";
	exit -1;
    }
}

#--------------------------
# Show user the expected command line format.
#--------------------------
sub displayUsage {  # no arguments
print STDERR
  "Usage: lr_regress_check.pl -r \n",
    "     [-h] (displays this message)\n",
}
