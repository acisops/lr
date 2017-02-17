#!/usr/bin/env perl

#This script creates a log file of bad solar array angles (SAA) for a given
#load review week.  It also creates a history file if the last maneuver
#in the mm*.sum file has a bad SAA.

#argument from lr passed to here via: system ("script $var")

#code by: Joe DePasquale
#started: 29 OCT 2002
#last update: 16 JAN 2003

#NOV0102 update - added time constraint so only observations longer than 30.0ks
#included in table.
#NOV0402 - removed the time constraint (might miss back to back observations)
#JAN1603 - added code to determine last digit of year from argument
#APR1703 - added code to compute differences in perigee timings (also found
# in mm*.sum file).
#OCT0809 - changed first argument to be a full directory name
#APR2111 - added in times for tail sun (greater than 130
#--------------------------------------------------------------------
if(@ARGV < 1){
    print "USAGE: $0 <full directory name of previous load>\n";
    exit (1);
}
$mm_file = `ls | grep mm | grep sum`;
$outfile = "saa_check.txt";

$prev_dir = $ARGV[0]; #SHOULD be the full directory name

$appx = `lr_suffix.pl`; # Null string or "-bak"
$workdir=</data/acis${appx}/LoadReviews>;

#If the history file exists from the last load - assign those values

if(-e "${prev_dir}/saa_check_history.txt"){
    open (HST, "${prev_dir}/saa_check_history.txt"); 
    while (<HST>)
    {
	@hist_line = split (/\s+/, $_);
	$obsid = $hist_line[1];
	chomp($obsid);
	$start = $hist_line[2];
	chomp($start);
	$saa = $hist_line[3];
	chomp($saa);
    }
    $start_dec_year=parse_time($start);
    @st_time = split(/\:/, $start);
    $start = join(":",$st_time[0],$st_time[1],$st_time[2],$st_time[3]);

close (HST);
}#end if

#open mm*.sum file for reading and open saa_check.txt file for writing
open (DAT, $mm_file) || die "ERROR! can't open mm*.sum file";
open (OUT, ">$outfile");
print OUT "   OBSID\tSTART(GMT)\tEND(GMT)\tSUN ANGLE(deg)\tDuration(ks)\n";

#loop through mm*.sum file to find bad pitch angles and record them 
$flag=0;
while (<DAT>)
{
    @row = split (/\s+/, $_);
    if (@row != " ")
    {
	$description = $row[1];
	chomp($description);
	
	if ($description eq "FINAL" && $row[2] eq "ID:")
	{
	    $obsid = $row[3];
	    chomp($obsid);
	}
	elsif ($description eq "STOP" && $row[2] eq "TIME")
	{
	     $start_dec_year=parse_time($row[4]);
	     $start=$row[4]; #remove the seconds....
	     @st_time = split(/\:/, $row[4]);
	     $start = join(":",$st_time[0],$st_time[1],$st_time[2],$st_time[3]);
	     
	}
	elsif ($description eq "Sun" && $row[2] eq "Angle")
	{
	    $saa = $row[4];
	    chomp($saa);
	}
	elsif ($description eq "START" && $row[2] eq "TIME")
	{
	    $stop1 = $row[4];
	    chomp($stop);
	    $stop_dec_year=parse_time($row[4]);
	    $stop=$row[4]; #remove the seconds....

	    @s_time = split(/\:/, $row[4]);
	    $stop = join(":",$s_time[0],$s_time[1],$s_time[2],$s_time[3]);
	    $i=1;
	}

	if ($saa <= 60.0 || $saa >= 130.0)
	{
	    if ($i == 1 && $start != " ")
	    {	
		$time_delta = $stop_dec_year - $start_dec_year;
		$ks_td = ($time_delta * 31536000)/1000;
		if ($ks_td >= 0.0 && $obsid =~ /^\d/) # obsid MUST start with a digit.
		{
		printf OUT "%10s\t%10s\t%10s\t%5.2f\t\t%5.2f\n", $obsid, $start, $stop, $saa, $ks_td;
		}
		$i=0;
	    }
	}
#reach end of pertinent information, if last $saa is bad, create history file
	if ($description eq "SIM" && $row[2] eq "POSITIONING" && ($saa <= 60.0 || $saa >= 130.0) )
	{
	    $outfile2 = "saa_check_history.txt";
	    open (OUT2, ">$outfile2");
	    printf OUT2 "To be used as continuity for next load; SAA is < 60.0 or > 130 for last maneuver.\n";
	    printf OUT2 "   OBSID\tSTART(GMT)\t\tSUN ANGLE(deg)\n";
	    printf OUT2 "%10s\t%10s\t%5.2f\n", $obsid, $stop1, $saa;
	    close (OUT2);
	}
	if ($description eq "SUMMARY")
	{
	    $flag=1;
	    $i=0;
	}
	if ($flag == 1 && $row[1] =~ /^2/)
	{
	    $date = $row[1];
	    chomp($date);
	    push(@full_p,$date);
	    $p_dec_year=parse_time($date);
	    push(@perigee,$p_dec_year);
	    $i++;
	}
    }
}

for ($j = 0; $j <= $i-2; $j++)
{
    $diff = $perigee[$j+1] - $perigee[$j];
    if ($diff > 0.00729){ 
	print "\nATTENTION! - Difference in PERIGEE times greater than 630 sec at:\n";
	print "$full_p[$j+1] and $full_p[$j]\n";
	print "Please investigate.\n\n";
    }
}

close (DAT);
close (OUT);




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






