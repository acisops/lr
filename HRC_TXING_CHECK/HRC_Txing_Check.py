#
# HRC_Txing_Check.py - Check of the Txing activation to HRC HV Powerup timing.

import argparse
import numpy as np
import shutil
import sys

# Import the BackstopHistory class
from backstop_history import BackstopHistory

# ACIS Ops Imports
import apt_date_secs as apt
import Backstop_File_Processing as bfp
import Calc_Delta as cd

import Insert_Comment_In_ALR as icia

import ORP_File_Class as ofc
import OFLS_File_Utilities as oflsu

"""
The basic structure of an SI mode command sequence is:

AA00000000   < START OF THE BIAS
AA00000000
WSPOW00000
WSPOW08812  <--- The last digits of the power command change with different SI modes
RS_0000001
RH_0000001
WT00D96014   <--- The last digits of the parameter block  command change with different SI modes
XTZ0000005    <---- Start Science Command; would be XCZ if it's continuous clocking

The structure is identical for all  SI modes. The only items that change from one SI mode
to another are the second WSPOWxxxxx, the WTxxxxxxxx, and the Start Science command.

This program assumes that no ACISPKT command will be inserted inside the block of SI mode
commands by mission planning.

You would use those differences to identify the SI mode being loaded by this sequence of commands.

The time delta between the loading of the SI mode and the SCSD-134 activation for
 Event Histograms run during HRC science observatgions is = bias time + 1152seconds.
The bias time differs from one SI mode to another if the number of chips differ.
The bias time calculation starts at the time of the first command of the SI mode load.

The 1152 seconds is the time it takes for txings to have taken enough samples (6) to
determine that a storm is bad enough to trigger a shutdown.

"""
# Parser code

hrc_txing_parser = argparse.ArgumentParser()

# Path to the ofls directory
hrc_txing_parser.add_argument("review_load_path", help="Path to the Review load directory. e.g. /data/acis/LoadReviews/2022/FEB2122/ofls'")

# Add the TEST argument as NON-POSITIONAL.  
hrc_txing_parser.add_argument("-t", "--test", help="In test mode", action="store_true")

args = hrc_txing_parser.parse_args()

load_week_path = args.review_load_path

#
# Inits
#

# Create the list which will contain all the HRC/Txing time delta comments
# which will appear in the ACIS-LoadReview.txt file.
comment_list = []

# The following  dictionary contains the WT parameter block  commands which
# appear in all of the  Event Histogram SI modes run  during an HRC is science
# observation. Each entry  consists of the parameter block packet name and
# the bias time for that SI mode.
ev_parameter_block_dict = {"WT00D98014": 454, "WT00D96014": 919}

# Create an instance of the Backstop History class
BSC = BackstopHistory.Backstop_History_Class( outdir = load_week_path, verbose = 0)

# Create an instance of the ORP File Class
ofci =  ofc.ORP_File_Class()

# Extract the load week out from the path
load_week = load_week_path.split('/')[5]

# Read the review load - results are in BSC.master_list
rev_load_commands = BSC.Read_Review_Load(BSC.outdir)

# Capture the start date and time of the Review load
rev_start_date = rev_load_commands[0]['date']
rev_start_time = rev_load_commands[0]['time']

# Calculate a tbegin time such that you will backchain one Continuity load.
# 50 hours will be enough - you want to capture any Event History activation
# that may have occurred
tbegin_time = rev_start_time - (50.0 * 3600)
tbegin = apt.date(tbegin_time)

# Assemble the command history going back one Continuity Load.
assembled_commands = BSC.Assemble_History(BSC.outdir, tbegin, False)

# Tell the user what we are checking
print('\n    HRC/Txing  Check for load week: ', load_week)

# Make a new numpy array which will contain any command that is either an ACISPKT
# command or has COACTS1=134 in the command string
extracted_cmds = np.array([], dtype = assembled_commands.dtype)

# Run through the commands and assemble the array
for eachcmd in assembled_commands:
    # Test to see if this is one of the commands we want to keep
    if ("ACISPKT" in eachcmd["commands"]) or \
       ("COACTS1=134" in eachcmd["commands"]):
        new_row = np.array( [ (eachcmd["commands"],
                                             eachcmd["time"],
                                             eachcmd["date"]) ], dtype = BSC.CR_DTYPE)
        
        extracted_cmds =  np.append(extracted_cmds, new_row, axis=0)


# Initialize the event histogram found flag to False
evh_found_flag = False
    
# Now step through the array and look for any command which contains one of  the
# parameter block WT commands that are presentlyu used for HRC observation
# Event Histograms.
for index, each_cmd in enumerate(extracted_cmds):
    # If any Event History WT packet name exists in this backstop command,
    # save it. otherwise the list will be empty
    key_list = [eachkey  for eachkey in ev_parameter_block_dict.keys() if eachkey in each_cmd["commands"]  ]

    # If  one of the HRC Event Histogram SI modes parameter blocks appears in this
    # command line but we already found an Event Histogram but have not yet seen
    # its corresponding SCS-134 activation command, we found an error
    if key_list and (evh_found_flag == True):
        # We foung an error. Place an error statement in the comments list, and print it out for the log file.
        full_comment = " ".join((">>> ERROR -", each_cmd["date"], "Multiple Event Histogram SI Mode loads without intervening SCS-134 activation"))
        print("\n", full_comment)
        # Append the comment to the comment list
        comment_list.append([each_cmd["date"], each_cmd["time"], full_comment])
        # Set the bias start date and time to this latest Event Histogram SI Mode load
        # That way when the next COACT1=134 is observed, the correct actual delta T
        # will be calculated from this SI mode load.
        bias_start_date = extracted_cmds[index - 6]["date"]
        bias_start_time = extracted_cmds[index - 6]["time"]

        # Else if this is the first Event Histogram SI Mode load since the start of
    # the load or the first since the last EV Load/SCS-134 activation pair.
    elif key_list and (evh_found_flag == False):
        
        # Calculate the index of the first start science command in the SI mode load
        first_start_science_index = index - 6

        # Calculate the required delta t given the SI mode bias time
        required_dt = ev_parameter_block_dict[key_list[0]] + 1152.0
        
        # You have found one of the event histogram modes used during an HRC science observation
        # Set the Event History SI mode found flag to True
        evh_found_flag = True
         
        # The next step is to find the corresponding COACTS1=134 command that subsequently
        # appears in the load.  This will allow you to calculate the time delta between the start
        # of loading that SI mode and the activation of SCS-134

        # Record the start date and time of the first command in the SI mode load
        bias_start_date = extracted_cmds[index - 6]["date"]
        bias_start_time = extracted_cmds[index - 6]["time"]

    # Else you see an SCS-134 activation but you have NOT seen the Event Histogram
    # load that should have come prior to this command.  This is an error. Add an error
    # comment, and print it out for the log file.
    elif ("COACTS1=134" in each_cmd["commands"]) and \
         ( evh_found_flag == False):
        full_comment = " ".join((">>> ERROR -", each_cmd["date"], "SCS-134 activation without a prior Event Histogram SI Mode Load"))
        print("\n", full_comment)
        # Append the comment to the comment list
        comment_list.append([each_cmd["date"], each_cmd["time"], full_comment])
        
    # Else, if you have found an Event Histogram Mode used for HRC observations
    # and this command is the corresponding SCS-134 activation, you can calculate
    # the delta time
    elif ("COACTS1=134" in each_cmd["commands"]) and \
         ( evh_found_flag == True):

        # Calculate the time between the start of SI mode load and the activation of
        # SCS-134
        delta_t = round(each_cmd["time"] - bias_start_time, 2)
  
        # Write the SCS-134 activation information line
        scs134_act_string =  each_cmd["date"] + " SCS-134 Activation"
        
        # Check to see if the time is long enough and write the corresponding comment.
        if delta_t < required_dt:
            # ERROR - Time delta is not long enough
            full_comment = " ".join((scs134_act_string, "\n",">>> ERROR - Time between SI load start and SCS-134 activation is too short\n             Bias Start: ", bias_start_date, "\n     SCS-134 Activation: ", each_cmd["date"], "\n     Required Delta T:", str(required_dt), "\n        Actual Delta T:" , str(delta_t)))
            print(full_comment)
            
        else: # The time delta is long enough
            full_comment = " ".join((scs134_act_string, "\n", "    Time between SI Mode load start and SCS-134 activation is good: \n     Required Delta T:", str(required_dt), "\n         Actual Delta T:" , str(delta_t)))

        # Append the comment to the comment list
        comment_list.append([each_cmd["date"], each_cmd["time"], full_comment])
        
        # Set the evh_found_flag to False so that you can find the next SI mode load.
        evh_found_flag = False
        
               
# Done finding all HRC Txing delta t's. If there are lines in the comment_list, insert
# them in a copy of ACIS_LoadReview.txt called ACIS_LoadReview.txt.TXING_COMMENT
if len(comment_list)> 0:
    icia.Insert_Comment_In_ALR(comment_list, load_week_path, "HRC_TXING")

    # Copy the updated ACIS-LoadReview.txt file
    # If the test flag was False, and there were comments, then copy the .HRC_TXING
    # file to ACIS-LoadReview.txt.
    # If the test flag was True then we leave the original ACIS-LoadReview.txt and the
    # ACIS-LoadReview.txt.HRC_TXING (if there is one)  files intact for comparison.
    if (args.test == False):
        try:
            print('\n    Moving ACIS-LoadReview.txt.HRC_TXING to ACIS-LoadReview.txt')
            shutil.copy(load_week_path+'/ACIS-LoadReview.txt.HRC_TXING', load_week_path+'/ACIS-LoadReview.txt')
        except OSError as err:
            print(err)
            print('Examine the ofls directory and look for the HRC_TXING file.')
        else:
            print('    Copy was successful')
    else:
        print('\n    Leaving the ACIS-LoadReview.txt  unchanged')

else:
    print(">>> Warning - No Event Histogram/SCS-134 Activation pairs found in this load.")

    
