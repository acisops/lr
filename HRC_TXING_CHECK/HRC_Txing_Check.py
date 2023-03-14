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

"""
The basic structure of an SI mode command sequence is:

AA00000000   < START OF THE BIAS
AA00000000
WSPOW00000
WSPOWxxxxx  <--- The last digits of the power command change with different SI modes
RS_0000001
RH_0000001
WTxxxxxxxx   <--- The last digits of the parameter block identifies the SI mode
XTZ0000005    <---- Start Science Command; would be XCZ if it's continuous clocking

The structure is identical for all  SI modes. The only items that change from one SI mode
to another are the second WSPOWxxxxx, the WTxxxxxxxx, and the Start Science command.

This program assumes that no ACISPKT command will be inserted inside the block of SI mode
commands by mission planning.  It would be illegal for any the 8 commands of the SI mode to be 
moved with respect to each other. This can never happen because ACIS has created the the SI modes
as a unit and the load builder loads the SI modes as a unit.

You would use those differences to identify the SI mode being loaded by this sequence of commands.
As of the first iteration of this program, SI modes H1C_001(B) and H2C_001(B) will be the ONLY
ones used to set up Txings for HRC science observations. And these two SI modes will only be used
for that purpose. The parameter blocks that correspond to these two SI modes are:

 WT00D98014 and WT00D96014

The time delta between the loading of the SI mode and the SCSD-134 activation for
 Event Histograms run during HRC science observatgions is = bias time + 1152seconds.
The bias time differs from one SI mode to another if the number of chips differ.
The bias time calculation starts at the time of the first command of the SI mode load.

The 1152 seconds is the time it takes for txings to have taken enough samples (6) to
determine that a storm is bad enough to trigger a shutdown.

These are the checks and errors performed by this program:

1)  Event Histogram SI mode loaded and it was previously loaded before without
completing an HRC observation.

2) COACTS1=134

        ERROR - 134 activation but no event histogram loaded
        ERROR - 134 activation but event histogram not running

3)  COACTS1=134, EH loaded, EH running

     OK - Event Histogram is running long enough before  COACTS1=134
     ERROR - Event Histogram not running long enough before  COACTS1=134


4) 215PCAOF Command
          OK - 215PCAOF and Event Histogram running
          ERROR - 215PCAOF but there wasn't any COACTS1=134
	  ERROR - 215PCAOF EH loaded but not running
                      - Allows a 1 second differential IF Stop Science occurs first.

"""
# Parser code

hrc_txing_parser = argparse.ArgumentParser()

# Path to the ofls directory
hrc_txing_parser.add_argument("review_load_path", help="Path to the Review load directory. e.g. /data/acis/LoadReviews/2022/FEB2122/ofls")

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

# Initialize the stop science date and time to the load start date/time
# That way when one of the tests below executes early on because of a really
# messed up load  and uses those times there is SOME value in the variables.
stop_science_date = rev_start_date
stop_science_time = rev_start_time

# Two flags indicating that SCS-134 was activated and that it is still running
hrc_activated_flag = False
hrc_running_flag = False

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
       ("COACTS1=134" in eachcmd["commands"]) or \
       ("215PCAOF" in eachcmd["commands"]):
        new_row = np.array( [ (eachcmd["commands"],
                                             eachcmd["time"],
                                             eachcmd["date"]) ], dtype = BSC.CR_DTYPE)
        
        extracted_cmds =  np.append(extracted_cmds, new_row, axis=0)

# Initialize the event histogram loaded flag to False
evh_loaded_flag = False
    
# Now step through the array and look for any command which contains one of  the
# parameter block WT commands that are presently used for HRC observation
# Event Histograms.
for index, each_cmd in enumerate(extracted_cmds):
    # EVENT HISTOGRAM LOAD
    # Detect if we are loading one of the two Event Histograms used when HRC is observing.
    # If any Event History WT packet name exists in this backstop command,
    # save it.  Otherwise the list will be empty
    key_list = [eachkey  for eachkey in ev_parameter_block_dict.keys() if eachkey in each_cmd["commands"]  ]

    # If  one of the HRC Event Histogram SI modes parameter blocks appears in this
    # command line but we already found an Event Histogram but have not yet seen
    # its corresponding SCS-134 activation command, we found an error
    if key_list and (evh_loaded_flag == True):
        # ERROR -  Place an error statement in the comments list, and print it out for the log file.
        full_comment = " ".join((each_cmd["date"], "\n>>> ERROR -", each_cmd["date"], "Multiple Event Histogram SI Mode loads without an intervening SCS-134 activation"))
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
    elif key_list and (evh_loaded_flag == False):
        
        # You have found one of the event histogram modes used during an HRC science observation
        # Set the Event History SI mode found flag to True
        evh_loaded_flag = True
     
        # Calculate the index of the first start science command in the SI mode load
        first_start_science_index = index - 6

        # Calculate the required delta t given the SI mode bias time
        required_dt = ev_parameter_block_dict[key_list[0]] + 1152.0
         
        # The next step is to find the corresponding COACTS1=134 command that subsequently
        # appears in the load.  This will allow you to calculate the time delta between the start
        # of loading that SI mode and the activation of SCS-134

        # Record the start date and time of the first command in the SI mode load
        bias_start_date = extracted_cmds[index - 6]["date"]
        bias_start_time = extracted_cmds[index - 6]["time"]
        
    # If this is an ACISPKT command and a  parameter block load command
    # (starts with WT) but not one of the two Event Histogram modes used when
    # HRC is observing, then you are loading some other SI mode which
    # "overwrites" whatever the active SI mode is. So set the loaded flag to False.
    if (not key_list) and \
       ("ACISPKT" in each_cmd["commands"]) and \
       ("TLMSID= WT" in each_cmd["commands"]):
        evh_loaded_flag = False

    # XTZ0000005 - and an Event Histogram SI mode was loaded . Signal that the
    # Event Histogram has started.
    if ("XTZ0000005" in  each_cmd["commands"]) and (evh_loaded_flag == True):
        event_hist_running = True;

    # XTZ0000005 - and an Event Histogram SI mode has NOT been loaded.  Signal that
    # Event Histogram has not started.
    elif ("XTZ0000005" in  each_cmd["commands"]) and (evh_loaded_flag == False):
        event_hist_running = False;

    # COACTS1=134 - HRC Observation begins.
    # ERROR - Event Histogram never loaded
    # Else you see an SCS-134 activation but you have NOT seen the Event Histogram
    # load that should have come prior to this command.  This is an error. Add an error
    # comment, and print it out for the log file. This will catch all errors of this type if there
    # are one or more HRC observations in the load.
    if ("COACTS1=134" in each_cmd["commands"]) and \
         ( evh_loaded_flag == False):

        # Set the hrc activated and running flags to True
        hrc_running_flag = True
        hrc_activated_flag = True
        
       # Create the SCS-134 activation information line
        scs134_act_string =  each_cmd["date"] + " SCS-134 Activation: HRC Observation Begun"

        # Create the error string telling the reviewer that no EVHIST SI mode was loaded
        error_comment = " ".join((scs134_act_string, "\n>>> ERROR - Event Histogram SI Mode Load never loaded prior to an SCS-134 activation"))
        # Print it for the log file
        print("\n", error_comment)
        
        # Append the comment to the comment list
        comment_list.append([each_cmd["date"], each_cmd["time"], error_comment])

    # ERROR - Event Histogram not running
    # HRC START command but the Event Histogram is NOT running. Give a grace
    # period of one second to account for time calculation accuracies.It may not happen the same way next time. 
    elif ("COACTS1=134" in each_cmd["commands"]) and \
         ( event_hist_running == False):
        
        # Set the hrc activated and running flags to True
        hrc_running_flag = True
        hrc_activated_flag = True
         
        # Create a string to record the SCS-134 activation date 
        scs134_act_string =  each_cmd["date"] + " SCS-134 Activation: HRC Observation Begun"
        
        # Calculate the time between the start of SI mode load and the activation of
        # SCS-134. Even though we've detected that the EVHIST is not running, we also
        # need to check that the timing between SI mode load and SCS-134 activation is correct.
        delta_t = round(each_cmd["time"] - bias_start_time, 2)
        
        # Check to see if the time is long enough and write the corresponding comment.
        # Create the delta t comment either way.
        if delta_t < required_dt:
            # ERROR - Time delta is not long enough
            delta_t_comment = " ".join((scs134_act_string, "\n>>> ERROR - Time between SI mode load start and SCS-134 activation is too short\n            SI Mode Load Start: ", bias_start_date, "\n     SCS-134 Activation: ", each_cmd["date"], "\n     Required Delta T:", str(required_dt), "        Actual Delta T:" , str(delta_t)))
            
            # Print the error comment for the log file
            print("\n", delta_t_comment)
            
        else: # The time delta is long enough
            delta_t_comment = " ".join((scs134_act_string, "\n      Time between SI Mode load start and SCS-134 activation is good: \n     Required Delta T:", str(required_dt), "       Actual Delta T:" , str(delta_t)))

        # Append the delta t comment comment to the comment list
        comment_list.append([each_cmd["date"], each_cmd["time"], delta_t_comment])

        # Now here is the error statement due to the fact that the EVHIST is not running.
        error_comment = " ".join((scs134_act_string, "\n>>> ERROR - SCS-134 activated but Event Histogram not running"))
        
        # Print the error out for the log file
        print("\n", error_comment)
        # Append the comment to the comment list
        comment_list.append([each_cmd["date"], each_cmd["time"], error_comment])
        
    # Else, if you have found an Event Histogram Mode used for HRC observations
    # and this command is the corresponding SCS-134 activation, you can calculate
    # the delta time
    elif ("COACTS1=134" in each_cmd["commands"]) and \
         ( evh_loaded_flag == True) and \
         (event_hist_running == True):
        
        # Set the hrc activated and running flags to True
        hrc_running_flag = True
        hrc_activated_flag = True
 
        # Calculate the time between the start of SI mode load and the activation of
        # SCS-134
        delta_t = round(each_cmd["time"] - bias_start_time, 2)
  
        # Write the SCS-134 activation information line
        scs134_act_string =  each_cmd["date"] + " SCS-134 Activation: HRC Observation Begun"

        # Check to see if the time is long enough and write the corresponding comment.
        if delta_t < required_dt:
            # ERROR - Time delta is not long enough
            full_comment = " ".join((scs134_act_string, "\n>>> ERROR - Time between SI mode load start and SCS-134 activation is too short\n     SI Mode Load Start: ", bias_start_date, "\n     SCS-134 Activation: ", each_cmd["date"], "\n     Required Delta T:", str(required_dt), "        Actual Delta T:" , str(delta_t)))
            print("\n",full_comment)
            
        else: # The time delta is long enough
            full_comment = " ".join((scs134_act_string, "\n    Time between SI Mode load start and SCS-134 activation is good: \n     Required Delta T:", str(required_dt), "       Actual Delta T:" , str(delta_t)))

        # Append the comment to the comment list
        comment_list.append([each_cmd["date"], each_cmd["time"], full_comment])

    # AA00000000 - No matter what ACIS SI mode is loaded this command stops the
    #                         clocking. And if an HRC Event Histogram is running that gets
    #                         stopped too. So there's no need to differentiate between one of
    #                         the two Event Histograms or any other.
    if  ("AA00000000" in  each_cmd["commands"]):
        event_hist_running = False
        stop_science_date = each_cmd["date"]
        stop_science_time = each_cmd["time"]
        
    # 215PCAOF - HRC Observation complete.
    if ("215PCAOF" in  each_cmd["commands"]):
        # Create the string that indicates the HRC obs 15V power down command issued.
        HRC_shutdown_string = each_cmd["date"] + " 215PCAOF command: HRC Observation Ends"
        
        # Now check to see if the event histogram was running at this point of
        # the load. Several situations have to be covered:
        #
        #    1) The 215PCAOF comes before the EVHIST stop science (i.e. EVHIST
        #        still running) - always OK.
        #
        #    2) SCS-134 was never activated - ERROR because if you are stopping HRC you
        #        must have expected that it was started
        #
        #    3) The EVHIST stop science comes before the 215PCAOF command
        #         -  Delta t between the  AA00 and 215PCAOF commands <= 1 second - OK
        #         -  Delta t between the  AA00 and 215PCAOF commands > 1 second - NOT OK
        #                - See Guideline
        #
        #
        #
        # Possibility #1 - EVHIST still running
        if event_hist_running == True:
            comment_list.append([each_cmd["date"], each_cmd["time"], HRC_shutdown_string])
            
        # Possibility #2 - Check to see if the SCS-134 activation ever occurred
        elif hrc_activated_flag == False:
            HRC_activation_error_string = " ".join((HRC_shutdown_string, "\n>>> ERROR - SCS-134  was never activated"))
            print("\n", HRC_activation_error_string)
            comment_list.append([each_cmd["date"], each_cmd["time"], HRC_activation_error_string])

        # Possibility #3  - EVHIST loaded, run, and was shut down prior to 215PCAOF
        elif (evh_loaded_flag == True) and \
              (event_hist_running == False):
            # Calculate the detla t between the EVHIST shutdown and this 215PCAOF command
            delta_t = each_cmd["time"]  -  stop_science_time

            # If delta t is one second or less, then the EVHIST was shut down closely enough
            # to this HRC shutdown to nor risk the HRC
            if delta_t <= 1:
                # Good shutdown timing with regard to the AA00000000. Record the
                # shutdown time.
                comment_list.append([each_cmd["date"], each_cmd["time"], HRC_shutdown_string])
            else: # HRC was running too long past the EVHIST stop science
                HRC_shutdown_error_string = " ".join((HRC_shutdown_string, "\n>>> ERROR - The Event Histogram was shut down more than 1 second prior to  the time of HRC shutdown"))
                print("\n", HRC_shutdown_error_string)
                comment_list.append([each_cmd["date"], each_cmd["time"], HRC_shutdown_error_string])
 
        # HRC is not running so set the HRC running flag to false. And set the
        # activated flag to False since this command de-activates it.
        hrc_running_flag = False
        hrc_activated_flag = False


# Done finding all HRC Txing delta t's. If there are lines in the comment_list, insert
# them in a copy of ACIS_LoadReview.txt called ACIS_LoadReview.txt.TXING_COMMENT
if len(comment_list)> 0:
    # There are comments - insert them
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

