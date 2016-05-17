#! /usr/local/bin/perl
# Plucknames.pm - Provides routines that permit the ACIS lr script to
# avoid the use of backquote commands with return values.
# Two routines at present.
# findNames(dir, string) - return an array of files on dir whose names
#  contain the string.
# tarNames(\@filnms, tarfile, string array) - return an array of files in
#  the tarfile whose names contain each of the strings.

package Plucknames;
use Exporter;
our @EXPORT = qw[findNames tarNames];
use warnings;

# Usage: findNames ($directoryFullPath, $matchString)
# Returns a list of all files in the directory which match the
# regular expression in the string. 
#
sub findNames {
    my ($self, $dirpath, $matchStr) = @_;
    my @matches = ();
    opendir(DIR, $dirpath) ||
	die "Could not find directory $dirpath, much less $matchStr\n";
    my @allfiles = readdir(DIR);
    foreach $flnm (@allfiles) {
	if ($flnm =~ /$matchStr/) {
	    push (@matches, $flnm);
	}
    }
    closedir(DIR);
    return @matches;
}

# Usage: tarNames(\@filnms, matchString [, matchString...])
#   Returns an array of all items in filnms which match
#   all of the regular expressions in the list of match strings.
#
sub  tarNames {
    my ($self, $flnmRef, @matchStr) = @_;
    my @flnms = @$flnmRef;
    my @matches = ();
    foreach $fname (@flnms) {
	$doesMatch = 1;
	foreach $mstr (@matchStr) {
	    if (! ($fname =~ $mstr)) {
		$doesMatch = 0;
		last;
	    }
	}
	if ($doesMatch) {
	    push (@matches, $fname);
	}
    }
    return @matches;
}

