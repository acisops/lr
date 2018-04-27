#!/usr/bin/env perl
use MachinePath();
@mach=( "han-v", "luke-v", "acis60-v", "acisocc-v", "colossus-v", "aciscdp-v", "xcanuck", "acis");

# Run through each host in the machine list
foreach $f (@mach){
    print "---------- $f ----------\n";
    $root,$host = GetPathandNode($f);
    print "GetPathandNode PATH and NODE for $f is: $root $host\n";
    $root=GetFluMon($f);
    print "GetFluMon FluMon PATH for $f is: $root\n";
    $root=GetRTpath($f);
    print "GetRTpath RT PATH for $f is: $root\n";
    $root=GetPMONpath($f);
    print "GetPMON PMON PATH for $f is: $root\n";
    $root=GetWebPath($f);
    print "GetWebPath Web PATH for $f is: $root\n\n";
}

# Now test with no argument:
print "---------- NO ARGUMENT ----------\n";
$root,$host = GetPathandNode();
print "PATH and NODE for NO ARGUMENT  is: $root $host\n";
$root=GetFluMon();
print "FluMon PATH for NO ARGUMENT  is: $root\n";
$root=GetRTpath();
print "RT PATH for NO ARGUMENT  is: $root\n";
$root=GetPMONpath();
print "PMON PATH forNO ARGUMENT   is: $root\n";
$root=GetWebPath();
print "Web PATH for NO ARGUMENT  is: $root\n\n";

exit;
