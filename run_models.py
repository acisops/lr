import argparse
import os
import shutil
import subprocess
import sys


"""

 run_models: 
 
 This is a wrapper script that calls the ska thermal models.

This program is the Python replacement of the Perl program run_models.pl

LR calls this program but differentiates between two cases:

   if you use the -T switch with LR, then LR calls run_models with the -out switch
           - switch argument is the OFLS Directory. 
           - run_models sets the LR_DIR to the OFLS directory (e.g. TEST_MAY0525)
           - PREVENTS run_models from copying the resultant files into the web directory

   if you DO NOT use the -T switch with LR, then LR calls run_models without the --out switch.
          - run_models creates a PRODUCTION ofls directory and uses that 
   

There are a number of changes between this version and the perl version.

1) No Linux/hostname check

2) The Perl version uses $lr_dir for both the thermal model --oflsdir AND the -out command line switches.  This
    prevents the user from running a model  on an existing OFLS directory but putting the results elsewhere:
    which one might do for testing purposes.

    This version has 2 separate command line switches:  --oflsdir and --out and that allows test runs
    to use an OFLS directory for input without writing into that official OFLS directory. If --out is not
    supplied, then the output  will be written into the ofls directory.  This is to maintain backward
    compatibility,

    This means that if you want to put the output files anywhere other than the ofls directory you MUST
    specify where they should go, withthe path switch.  The Perl version used the $path variable to
    determine whether or not to copy the plot files to the web for display.  Since we have disassociated path from oflsdir
    we need another way to prevent copies to the web page.  For that, we use the --web switch.


 This program should fail any particular script and continue on if there 
 is an issue. 


  Usage:
 Specifying a Test Directory:
 
   /data/acis/LoadReviews/script/run_models.pl load_name -h $hostname  ofls_dir break_string -nlet_file $nlet_file 

 Production Run:
 /data/acis/LoadReviews/script/run_models.py load_name -h $hostname $break_str -nlet_file $nlet_file

 Inputs: load_name - Required. Name of the Review load including letter (e.g. AUG0924A) comes from LR

             oflsdir -   Optional full path to an ofls directory (e.g. /data/acis/LoadReviews/2025/APR2825/oflsa)
                                 - If you supply this path, is is assumed that the backstop file for that load week
                                   has been expanded into this directory and that the directory permissions are such
                                   that the out_* model subdirectories can be created and written into.
                                          NOTE: If the ACIS backstop history state builder is ued, it is assumed that
                                                     all necessary previous load weeks exist using the same base path
                                                     as the present review load.

                             If an OFLS directory is not supplied, the program will formulate one with  /data/acis/LoadReviews
                             as the base of the path, extract the year and version letter from the load week name. This means
                             that if you DON'T supply an ofls path then run_models will formulate a path to a PRODUCTION
                             ofls directory.
                                  - and if you don't specify the --out switch, run_models will WRITE into that PRODUCTION ofls directory.

                             NOTE: If you are running run_models.py from lr, and use the -T switch on lr, then --out need not be specified 
                                        and the out_* directories will appear under th eTEST directory.

             out - Optional full, alternate path for the out_* directories. This allows you to run the models
                     on a production load but not write the output files into the production ofls directory.
                        - If not specified, the output directory is set to be the same as OFLS dir.
             
             b  -  Switch indicating that the load was an interrupt load 

             nlet_file - Full path to the NLET file to be used. (e.g. /data/acis/LoadReviews/NonLoadTrackedEvents.txt)
                                - The default is the production version

             -t - If true, write the out_<model> subdirectories to the TEST web pages. The default is False to eliminate
                   the need to specify this switch and maintain backwards compatibility. So if this switch is False, the resultant
                   output files will be written to the PRODUCTION web pages.

 Here is a truth table for different inputs for --oflsdir and --out:

      -- oflsdir                                 --out                                          --oflsdir                                                   --out
          input                                   input                                            output                                                  output
==========================================================================
           ---                                         ---                         Formulates path to OFLS directory       Formulated path to OFLS directory 
Path to OFLS directory                    ---                                   Path to OFLS directory                         Path to OFLS directory
           ---                           Path to output directory     Formulates path to OFLS directory               Path to output directory
Path to OFLS directory      Path to output directory              Path to OFLS directory                         Path to output directory

   The formulated path to the OFLS directory is:  /data/acis/LoadReviews/<year>/<load>/ofls<version letter>
   It is based upon the load week and version letter which are  required input.

 Example command line for the 1DPAMZT model:

    /proj/sot/ska3/flight/bin/dpa_check APR2825 --oflsdir  /data/acis/LoadReviews/2025/APR2825/ofls -nlet_file nlet_file "b"

 Initial: July 23, 2025
           Gregg Germain

"""

# Set up the parser
rmparser = argparse.ArgumentParser()
rmparser.add_argument("load_name", help="Name of the Review load including letter (e.g. AUG0924A)")
rmparser.add_argument("--oflsdir", help="Full path to the OFLS directory of the review load")
rmparser.add_argument("--out", help="Full path output  directory for the out_* files (e.g. /data/acis/LoadReviews/2025/APR2825/ofls)")
rmparser.add_argument("-b", help="If in the command line, specifies if the load is an interrupt load",  action="store_true")

rmparser.add_argument("--nlet_file", help="Full Path to the Non Load Event Tracking file to be used", default="/data/acis/LoadReviews/NonLoadTrackedEvents.txt" )
rmparser.add_argument("--verbose", help="Indicates verbosity of debug comments", default = 0)

rmparser.add_argument("-t", help="Flag to allow/prevents writing the out_<model> directories to the web page", action="store_true")

# Get the arguments
args = rmparser.parse_args()

# Capture the name of the load.  e.g. DEC0224A
load_name = args.load_name

# Extract the year and load version letter from the load name
year = "20"+load_name[5:-1]

# load is the weekly load name without the letter version
load = load_name[:-1]

# ver is the version letter of the load (e.g. the "A" of AUG1224A)
ver = load_name[-1]

# OFLSDIR - If the user specified an OFLS directory path then use that one.
# Otherwise form the usual production path using the year, the load and the version
if args.oflsdir:
    # Use the supplied directory
    oflsdir = args.oflsdir
else:
    # Formulate the PRODUCTION directory
    oflsdir = "/".join(("/data/acis/LoadReviews/" + year, load, "ofls"+ver.lower()))

# OUT - If a --out switch value was supplied, capture it. Otherwise write the output
# files into the OFLS directory (as you would for production or when you use the -T switch
# in LR)
if args.out:
    # Use the supplied output directory and add to it.
    out_dir = "/".join((args.out,  "ofls"+ver.lower()))
else: #...otherwise the output directory is the same as the ofls directory
    out_dir =  oflsdir


# BREAK - Process the load interrupt switch
if args.b:
    break_str =  "--interrupt"
else:
    break_str = ""

# VERBOSE - Process the verbose switch. If a value was given use it. Otherwise
# Select minimal verbosity
if args.verbose:
    verbose_val = str(args.verbose)
else:
    verbose_val = "0"
    
# TEST - Process the -t switch. This controls whether the files are copied to the production or
# test web page
test_flag = args.t
    
# Now set the SKA environment variable for this run
os.environ["SKA"] = "/proj/sot/ska3/flight"

# Capture the nlet file argument
nlet_file = args.nlet_file

#---------------------------------------------
#Set up the ska environment to run
#---------------------------------------------

ska_bin_base = '/proj/sot/ska3/flight/bin/'

# Argument list for us in formulating the run_models command. Specifies
# the model name, part of the output directory where resultant files are located,
# and part of the path where the web copies are located.
# There r twopossibilities: if you are running for production the web page
# subdirectory is the Production subdir. Otherwise it's a test directory

# TEST
if test_flag == True:
    exec_args = [ ["dpa_check", "out_dpa", "TEST_DPA_thermPredic"],
                           ["psmc_check",  "out_psmc", "TEST_PSMC_thermPredic"],
                           ["dpamyt_check", "out_dpamyt", "TEST_DPAMYT_thermPredic"],
                           ["dea_check", "out_dea", "TEST_DEA_thermPredic"],
                           ["acisfp_check", "out_fptemp", "TEST_FP_thermPredic"],
                           ["fep1_mong_check", "out_fep1_mong", "TEST_FEP1_MONG_thermPredic"],
                           ["fep1_actel_check",  "out_fep1_actel",  "TEST_FEP1_ACTEL_thermPredic"],
                           ["bep_pcb_check", "out_bep_pcb", "TEST_BEP_PCB_thermPredic"]]
else:
    exec_args = [ ["dpa_check", "out_dpa", "DPA_thermPredic"],
                           ["psmc_check",  "out_psmc", "PSMC_thermPredic"],
                           ["dpamyt_check", "out_dpamyt", "DPAMYT_thermPredic"],
                           ["dea_check", "out_dea", "DEA_thermPredic"],
                           ["acisfp_check", "out_fptemp", "FP_thermPredic"],
                           ["fep1_mong_check", "out_fep1_mong", "FEP1_MONG_thermPredic"],
                           ["fep1_actel_check",  "out_fep1_actel",  "FEP1_ACTEL_thermPredic"],
                           ["bep_pcb_check", "out_bep_pcb", "BEP_PCB_thermPredic"] ]


# Specify the base web directory
webroot = "/proj/web-cxc/htdocs/acis"

# Now run each model and create the web directory for the output files, and copy
# the files into that directory
#
for each_model in exec_args:
    print("\nExecuting model: ", each_model[0])
    sys.stdout.flush()
    
    out_path = "/".join((out_dir, each_model[1]))
    # Now create the command line for executing this model 
    model_cmd_line = " ".join((ska_bin_base + each_model[0], "--oflsdir", oflsdir, "--out", out_path, "--nlet_file", nlet_file, "--verbose", verbose_val, break_str ))

    # Run the model
    results = subprocess.run(model_cmd_line, shell = True)

    # Next  copy the contents of the oflsdir out_<model> directories
    # into the appropriate web directory: either the TEST or PRODUCTION directory

    # Formulate the web destination
    web_dir_dest = "/".join((webroot, each_model[2], load, "ofls" + ver.lower(), each_model[1] ))
   
    # Does the directory exist?
    dir_exist = os.path.isdir(web_dir_dest)

    # Create the directory if it doesn't exist
    if dir_exist == False:
        os.makedirs(web_dir_dest, exist_ok=True)

    # Copy each file in the directory
    for item in os.listdir(out_path):
        shutil.copy2("/".join((out_path, item)), web_dir_dest)
        
