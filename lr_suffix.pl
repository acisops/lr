#!/usr/bin/env perl
#lr_suffix.pl returns either "_bak" or a null string,
# depending on whether the current machine is the backup machine for lr
# runs.
#$Log
#$Date

$execPlease = 0;
while (@ARGV) {
    $arg = shift(@ARGV);
    if ($arg eq "-x") {     # User wants execution version of string?
	$execPlease = 1;
        next;
    }
    &displayUsage();   # Shouldn't ever get here
    exit -1;
}

if ($ENV{HOST} =~/colossus-v/) {
    if ($execPlease) {
	print "_bak";
    } else {
	print "-bak";
    }
}
else {
    print "";
}

sub displayUsage {  # no arguments
print STDERR
  "Usage: lr_suffix.pl [-x]\n" .
"      -x switch will return -bak instead of -bak if on backup machine\n";
}
