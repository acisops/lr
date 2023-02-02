# To run it:
#
# extract_specific.py --nargs <path to Tar file> [extract_file_1...extract_file_n]
#
# e.g.:
#
# extract_specific.py --nargs DEC1922A_backstop.tar mps/or/DEC1922_A.or vehicle/VR353_0101.backstop

import argparse
import os
import tarfile as tf

"""
This program will extract one or more files from a given tar file and place
them  in, or underneath  the appropriate subdirectory, wherever you are sitting.

The tar file can be a .tar file or a gzipped or bzipped file. You can specify a full 
path to the tar file.

inputs:  Required - 1)  Path to the tar file 
                                    - Must always be the first argument
                                    - Can be a .tar, .gz or .bz file

                             2)  One or more files to extract with their subdirectory path
                             For example, if you want the ORLIST file (.or) you would
                             specify: mps/or/DEC1922_A.or (for the DEC1922A load).

                             If you want the load week backstop file just specify it's name
                             e.g. CR353_0101.backstop because that file is at the top
                             level of the tar file.

                             If you want the vehicle load you'd specify: 
                                  vehicle/VR353_0101.backstop (also for the DEC1922A load)

                             Obviously, for this program, you must know the location and
                             the exact names of the file(s) you wish to extract. To obtain those
                             you can use the .getmember, .getmembers, .getnames or .list 
                             methods in the tarfile module.

                             If you don't specify any files nothing bad will happen but
                             nothing will get extracted.

outputs:  The extracted files will appear in the present directory or the appropriate,
               created subdirectory underneath.
"""
# Set up the parser
parser = argparse.ArgumentParser()

# Add the --nargs argument which, with a "+" will collect all subsequent
# arguments and present them in a list of strings.
parser.add_argument('--nargs', nargs='+')

# Parse the input
args = parser.parse_args()

# Capture the list of strings 
arg_list = args.nargs

# The first argument must always be the tar file from which you want to read
# It can be either a .tar file or a gzipped tar file with .gz extension. Also .bz
# files should work.
lwtf = tf.open(arg_list[0], mode="r")

# For each item in the list after the name of the tar file, extract that file
for each_file in arg_list[1:]:
    
    # Extract that file
    lwtf.extract(each_file, path=os.getcwd())

# Done with the tar file - close it
lwtf.close()
