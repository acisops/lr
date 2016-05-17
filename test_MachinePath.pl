#!/usr/bin/env perl
use MachinePath();
@mach=("xcanuck", "han-v", "luke-v", "colossus-v", "han", "acis", "acis60-v", "acisocc-v", "aciscdp-v");


foreach $f (@mach){
    print "--------------------\n";
    $root=GetFluMon($f);
    print "FluMon PATH for $f is: $root\n";
    $root=GetRTpath($f);
    print "RT PATH for $f is: $root\n";
    $root=GetPMONpath($f);
    print "PMON PATH for $f is: $root\n";
    $root=GetWebPath($f);
    print "Web PATH for $f is: $root\n";
}



exit;
