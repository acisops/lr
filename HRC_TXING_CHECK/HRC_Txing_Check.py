################################################################################
#
# HRC_Txing_Check.py - Check of the Txing activation to HRC HV Powerup timing.
#
# V1.0
#
# Update V2.0
#              Gregg Germain
#              November 19, 2023
#              1) Incorporation of the new H2C_0002(B) SI mode
#                   - Has extra window command along with a 4 second delay as compared
#                     to H2C_0001(B)
#              2) Searches for full SI mode packet sequence to located the first
#                  AA00.  Checks the SI mode command load sequence for extra or missing
#                  ACISPKT commands and incorrect timing between commands.
#              3) Modified the program so that new SI modes do not require code modification
#
################################################################################
import argparse
import math
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
The basic structure of a with-bias SI mode command sequence is:

AA00000000   < START OF THE BIAS
AA00000000
WSPOW00000
WSPOWxxxxx  <--- The last digits of the power command change with different SI modes
RS_0000001
RH_0000001
WTxxxxxxxx   <--- The last digits of the parameter block identifies the SI mode
XTZ0000005    <---- Start Science Command; would be XCZ if it's continuous clocking

This program assumes that no ACISPKT command will be inserted inside the block of SI mode
commands by mission planning.  It would be illegal for any the 8 commands of the SI mode to be 
moved with respect to each other. This shouldn't happen because ACIS has created the the SI modes
as a unit and the load builder loads the SI modes as a unit. However the program checks the sequence
and timing of the commands in case a hand edit of the load introduced an error.

The structure is identical for all with-bias SI modes. The only items that change from one SI mode
to another are the second WSPOWxxxxx, the WTxxxxxxxx, the Start Science command, and the
possible addition of a window block.

You would use those differences to identify the SI mode being loaded by this sequence of commands.
SI modes H1C_0001B, H2C_0001B and H2C_0002B will be the ONLY ones used to set up Txings 
for HRC science observations, at this time.  The parameter blocks that correspond to these
SI modes are:

 WT00D98014 and WT00D96014 and WT00DAA014

The time delta between the loading of the SI mode and the SCS-134 activation for
 NIL SI modes which are run during HRC science observations is = bias time + 1152seconds.
The bias time differs from one SI mode to another if the number of chips differ.
The bias time calculation starts at the time of the first command of the SI mode load.

The 1152 seconds is the worst case time it takes for txings to have taken enough samples (6) to
determine that a storm is bad enough to trigger a shutdown.

These are the checks, errors and warnings performed by this program:

1) COACTS1=134

        ERROR - 134 activation but no NIL SI mode loaded
        ERROR - 134 activation but  NIL SI mode not running

2)  COACTS1=134, NIL SI mode  loaded and running

     OK - NIL SI mode  is running long enough before  COACTS1=134
     ERROR -  NIL SI mode not running long enough before  COACTS1=134


3) 215PCAOF Command
          OK - 215PCAOF and  NIL SI mode running
          ERROR - 215PCAOF issued but there wasn't any COACTS1=134
	  ERROR - 215PCAOF issued, NIL SI mode  loaded but not running
                      - Allows a 1 second differential IF Stop Science occurs first.

4) WARINING - The sequence of the commands to load the NIL SI mode is missing a command

5) WARNING - The timing of the commands to load the NIL SI mode has an extra command inserted

6) WARNING - Informs the user that there were no  NIL SI mode/SCS-134 activation/215PCAOF groups
                      in the load.

Version 2.0:

    H2C_0002(B) is now recognized as a valid SI mode to be used
    when HRC is observing. The changes are backward compatible so that the other 
    SI modes will still be recognized and processed correctly even though they might
    no longer be used in the future. This allows regression testing using old tests and
    a return to using the old SI modes in the future if desired.

    The NIL SI modes are no longer limited to Event Histogram type SI modes. 
    The code comments and informational statements were changed to reflect this.
    New SI modes can be added by creating a .dat  file with the commands and delays.
    and editing the PB_to_Mode_Map.dat file.  The program no longer needs to be modified
    when a new NIL SI mode is created. Since we usually use the same SI mode
    for HRC observations in a load, the code will check to see if the command sequence
    for that load was already loaded and if so, will not repeat the loading.

    Function Check_Command_Sequence was added to detect if the SI mode command
    sequence was tampered with inadvertantly. The sequence of commands and times 
    between the commands are checked.
    
"""

#-------------------------------------------------------------------------------
#
# Read_PB_to_Mode_Map
#
#-------------------------------------------------------------------------------
def PB_to_Mode_Map(data_files_dir):
    """
    Read in the PB_to_Mode_Map.dat file and create a dictionary of
    the two entries on each line of the file. The first entry is the
    parameter block command for that NIL SI mode 
    (e.g.WT00DAA014) and the second entry is the name of the file
    (no extension) that can be read to obtain the sequence of commands
    for that SI mode.

    This mapping is done because it's easier to recognize the SI mode
    represented by a file if we use the SI mode name (e.g. H2C_0002B)
    and not the parameter block command.
    """
    # Initialize an empty dictionary
    pb_to_mode_map = {}

    # Open the mapping file
    mapfile = open(data_files_dir+"PB_to_Mode_Map.dat", "r")

    # Read each line in the map file and process the two entries turning the
    # entries into a dictionary which maps the parameter block command
    # (WT.......) with the file that contains the information about that  sequence.
    for eachline in mapfile:
        # Update the dictionary with the new entry
        pb_to_mode_map.update({eachline.split()[0]: eachline.split()[1]+".dat"})

    # Done with the file: close it.
    mapfile.close()

    # Return the mapping dictionary which maps the  parameter block to SI mode
    # the SI mode defintion file
    return pb_to_mode_map

#-------------------------------------------------------------------------------
#
# extract_command_packet
#
#-------------------------------------------------------------------------------
def extract_command_packet(cmd_string):
    """
    Given any CR*.backstop file ACISPKT line, strip out the ACIS command that is
    contained within that line. This function assumes that only ACISPKT lines
    will be input.
    """
    # Extract the value after "TLMSID=" by successive splits and strip
    # out any leading or trailing blanks
    packet = cmd_string["commands"].split("TLMSID=")[1].split(",")[0].strip()
    
    # Return the extracted ACIS packet command
    return packet


#-------------------------------------------------------------------------------
#
# Read SI Mode
#
#-------------------------------------------------------------------------------
def Read_SI_Mode_File(filespec):
    """
    Given the path to an NIL SI mode definition file, this function will
    read the specified SI mode command file and store the data in a list
    of lists. Each sublist consists of:

        [ "command", delay]

        or, in the case of the parameter block command:

         [ "command", delay, bias_secs]

    Command is a string and the delays and bias_secs are integers.

    The order of the commands in the list is the same as what appears in the ACIS tables.

    """
    # Open the required file for reading
    mode_file = open(filespec, "r")
    
    # Read each line, split on spaces and add the command delay values
    # as a list to the command list.
    file_list = [data_line.split() for data_line in mode_file]

    # Initialize the output command list
    command_list = []
    
    # Convert all the delays and bias times into integers
    for each_cmd in file_list:
        command_list.append([each_cmd[0]] + [int(each_num) for each_num in each_cmd[1:]])
    
    # Return the command list
    return command_list
                

#-------------------------------------------------------------------------------
#
# Check_Command_Sequence
#
#-------------------------------------------------------------------------------
def Check_Command_Sequence(extracted_cmds, wt_index, pb_command, si_mode_command_list, comment_list  ):
    
    """
    This function works through the array of commands which consist of the
    ACISPKT, COACTS1=134 and 215PCAOF commands, extracted from the load,
    and starting from the WT parameter block commands and working backwards,
    looks for:
         - Any commands missing from the SI mode load sequence
         - Any extra commands inside the SI mode load sequence
         - Any timing errors between successive commands 

    The function only produces warnings. Any generated warnings will appear in
    the ACIS-LoadReview.txt file.   Also, since a missing command will throw the
    entire command sequence off, the function will throw only one command
    warning and only one timing warning.

    inputs:

        extracted_cmds -   All the extracted commands: extracted_cmds
        wt_index -  The index of the WT command in the extracted commands
        pb_command -  The WT Command itself
        si_mode_command_list -  The <SI Mode>.dat file information contents
                                                 which is the command sequence for this SI mode.
    """
    #
    # Inits
    #
    
    # Epsilon allowed for calculation of the delta between execution times
    epsilon = 0.1
    
    # Using the data for  the required SI mode, work through the commands in
    # the command list for that  si mode and make sure they exist in the load at the
    # proper intervals. You are starting with the WT parameter block command
    # and moving BACKWARD.

    # Get the index of the WT command within the si_mode_command_list
    present_cmd_index_simode =  [each_index for each_index, WTcmd in enumerate(si_mode_command_list) if WTcmd[0] == pb_command][0]
    
    #wt_index points to the WT parameter block command in the load.
    present_cmd_index_load = wt_index
    
    # Set the warning flags to False as we want to report only the first
    # sequence and/or timing warning
    warning_sequence_flag = False
    warning_timing_flag = False
    
    # Loop through the comands for this SI mode (skipping the parameter
    # block/bias value line) and,
    # 1) Check that the previous command matches the expected si
    #     mode command and
    # 2) compare the delta t between the present command and the one before it

    # For every command that comes before the WT command.....
    while present_cmd_index_simode != 0:
        # Extract the expected command from the si_mode_command_list
        each_expected_cmd = si_mode_command_list[present_cmd_index_simode-1]
        
        # Extract the actual ACIS command from the load line
        actual_cmd = extract_command_packet(extracted_cmds[present_cmd_index_load - 1])
    
        # COMMAND MNEMONIC CHECK - Check to see if the command matches the expected command
        if (warning_sequence_flag == False) and (each_expected_cmd[0] != actual_cmd):
                    
            # WARNING -  Place a warning statement in the comments list, and print it out for the log file.
            full_comment = " ".join(( ">>> WARNING - ", extracted_cmds[present_cmd_index_load - 1]["date"], "The actual command in the load: ", actual_cmd, "does not match the expected command: ", each_expected_cmd[0] ))
            
            # Inform the Load Reviewer in real time that a problem was found.
            print("\n",extracted_cmds[present_cmd_index_load - 1]["date"], full_comment)
            
            # Append the comment to the comment list
            comment_list.append([extracted_cmds[present_cmd_index_load - 1]["date"], extracted_cmds[present_cmd_index_load - 1]["time"], full_comment])
            # Set the warning flag to True so that only one warning of this type is given
            warning_sequence_flag = True

        # TIMING CHECK  - Correct command; now check the time delta between this
        # command and the one before it in the load
        else: 
                # delta between this command and the one before it in the load
            dt_load = extracted_cmds[present_cmd_index_load]["time"] - extracted_cmds[present_cmd_index_load - 1]["time"]

            # Extract the expected dt between this command and the one before
            # it in the SI mode command list
            dt_smcl = each_expected_cmd[1]           
            
            # If the time pointed to by present_cmd_index minus dt is equal
            # to the time of the previous command, all is well.
            if (warning_timing_flag == False) and (not math.isclose( dt_load, dt_smcl, rel_tol = epsilon)):
                full_comment = " ".join(( ">>> WARNING - ", extracted_cmds[present_cmd_index_load - 1]["date"], " The Time delta between the present command and the previous one does not match the si mode definition.\n", "Expected: ", str(each_expected_cmd[1]), "Actual: ", str(dt_load)))
                
                # Inform the Load Reviewer in real time that a problem was found.
                print("\n", extracted_cmds[present_cmd_index_load - 1]["date"], full_comment)

                # Append the comment to the comment list
                comment_list.append([extracted_cmds[present_cmd_index_load - 1]["date"], extracted_cmds[present_cmd_index_load - 1]["time"], full_comment])
                # Set the warning flag to True so that only one warning of this type is given
                warning_timing_flag = True
    
            # Move up one command in the load extracted command array
            present_cmd_index_load -= 1
            present_cmd_index_simode -=1
            
    # Return the comment list
    return comment_list
    



#===============================================================================
#
# MAIN
#
#===============================================================================
# Parser code

hrc_txing_parser = argparse.ArgumentParser()

# Path to the ofls directory
hrc_txing_parser.add_argument("review_load_path", help="Path to the Review load directory. e.g. /data/acis/LoadReviews/2022/OCT2823T/ofls")

# Add the TEST argument as NON-POSITIONAL.  
hrc_txing_parser.add_argument("-t", "--test", help="In test mode", action="store_true")

args = hrc_txing_parser.parse_args()

load_week_path = args.review_load_path

#
# Inits
#

# Set the variable specifying which was the last SI mode file read to None
last_si_mode_file_read = None

# Initialize the NIL SI mode loaded flag to False
si_mode_loaded_flag = False

# Initialize the container for NIL SI mode commands to None
si_mode_command_list = None

# Create the list which will contain all the HRC/Txing time delta comments
# which will appear in the ACIS-LoadReview.txt file.
comment_list = []

# Specify the base directory with the data files reside
data_files_dir = "/data/acis/LoadReviews/script/HRC_TXING_CHECK/"

# Read the Parameter Block to SI mode definition file map
pb_to_mode_map = PB_to_Mode_Map(data_files_dir)

# Make a list, using the pb_to_mode_map dict keys, of all the parameter blocks in
# the SI modes that could be used when HRC is observing
NIL_SI_parameter_block_list = (pb_to_mode_map.keys())

#
# Assemble the Load History
#

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

#
# Extract the useful command lines from the Assembled Load History
#

# Tell the user what we are checking
print('\n    HRC Txing  Check for load week: ', load_week)

# Make a new, empty, numpy array which will contain any command that is either
# an ACISPKT command or has COACTS1=134 in the command string
extracted_cmds = np.array([], dtype = assembled_commands.dtype)

# Run through the commands and create the array: extracted_cmds
# extracted_cmds will contain any command that:
#    1) is an ACISPKT command,
#    2) contains COACTS1=134
#    3) contains 215PCAOF
# These are the commands we need in order to check the TXING timing.
for eachcmd in assembled_commands:
    # Test to see if this is one of the commands we want to keep
    if ("ACISPKT" in eachcmd["commands"]) or \
       ("COACTS1=134" in eachcmd["commands"]) or \
       ("215PCAOF" in eachcmd["commands"]):
        new_row = np.array( [ (eachcmd["commands"],
                                             eachcmd["time"],
                                             eachcmd["date"]) ], dtype = BSC.CR_DTYPE)
        
        extracted_cmds =  np.append(extracted_cmds, new_row, axis=0)

#
# Process the extracted commands checking any NIL SI modes that appear.
#

# Now step through the array and look for any command which contains one of  the
# parameter block WT commands that are presently used for HRC observation
# si modes. If you find one process that command sequence checking for errors.
#
# index is an index into the extracted_cmds array.
for index, each_cmd in enumerate(extracted_cmds):
    # HRC OBSERVING?
    # Detect if we are loading one of the  SI modes used when HRC is observing.
    # Any time one of the HRC Observation SI modes exists in extracted_cmds,
    # save it.  If there are no HRC Observations in the load,  the list will be empty
    key_list = [eachkey  for eachkey in NIL_SI_parameter_block_list if eachkey in each_cmd["commands"]  ]

    # If  one of the HRC-Observing SI modes parameter blocks appears in this
    # command line but we already found an HRC observing si mode but have not yet seen
    # its corresponding SCS-134 activation command, we found an error
    if key_list and (si_mode_loaded_flag == True):
        
        # ERROR -  Place an error statement in the comments list, and print it out for the log file.
        full_comment = " ".join((each_cmd["date"], "\n>>> ERROR - ", each_cmd["date"], "Multiple NIL SI Mode loads without an intervening SCS-134 activation"))
        print("\n", full_comment)
        # Append the comment to the comment list
        comment_list.append([each_cmd["date"], each_cmd["time"], full_comment])
        # Set the bias start date and time to this latest NIL  SI Mode load
        # That way when the next COACT1=134 is observed, the correct actual delta T
        # will be calculated from this SI mode load.
        bias_start_date = extracted_cmds[index - 6]["date"]
        bias_start_time = extracted_cmds[index - 6]["time"]

    # Else if this is the first HRC Observing SI Mode load since the start of
    # the load or the first since the last EV Load/SCS-134 activation pair.
    elif key_list and (si_mode_loaded_flag == False):
        
        # You have found one of the SI modes used during an HRC science observation
        # Set the Event History SI mode found flag to True
        si_mode_loaded_flag = True

        # Capture the name of the WT packet id
        pb_command = key_list[0]
        
        # Determine the name of the file required to read in the commands for this SI mode
        
        # Next load in the appropriate NIL SI mode file unless it was the last file
        # to have been loaded.
        required_file = pb_to_mode_map[pb_command]

        # Ordinarily the same SI mode is used every time an HRC observation is
        # executed. So if we have already processed an HRC observation and loaded
        # in an SI mode we can save some time by not re-loading it.
        # But it's not an ironclad rule. So in case there's a mix of NIL SI
        # modes used in the load, we will check to see if the presently required
        # SI mode file has  already been read in. 
        if (not si_mode_command_list) or  last_si_mode_file_read != required_file:
        
            # This SI mode is not loaded. Either because it's the first time
            # it's been seen in the load or because some other HRC-observing
            # si mode was seen before this one.
               
            # Load the commands for this SI mode
            si_mode_command_list = Read_SI_Mode_File(data_files_dir+required_file)
            
            # Set the last file read variable
            last_si_mode_file_read = required_file
        
        # Call the Check_Command_Sequence function to look for any commands within the
        # SI mode loading sequence that were inserted, or missing or have unexpected timing.
        comment_list = Check_Command_Sequence(extracted_cmds, index,  pb_command, si_mode_command_list, comment_list)

        # Calculate the index of the first start science command in the SI mode load
        # This assumes the SI mode is with bias and there are no intervening or missing
        # ACIS commands in the SI mode load sequence.
        first_start_science_index = index - 6

        # Calculate the required delta t given the SI mode bias time
        # Extract the bias time from the si_mode_command_list
        bias_secs = si_mode_command_list[[index for index, each_cmd in enumerate(si_mode_command_list) if each_cmd[0] == pb_command][0]][2]
        required_dt = bias_secs + 1152.0
         
        # The next step is to find the corresponding COACTS1=134 command that subsequently
        # appears in the load.  This will allow you to calculate the time delta between the start
        # of loading that SI mode and the activation of SCS-134

        # Record the start date and time of the first command in the SI mode load
        bias_start_date = extracted_cmds[index - 6]["date"]
        bias_start_time = extracted_cmds[index - 6]["time"]
        
    # If this is an ACISPKT command and a  parameter block load command
    # (starts with WT) but not one of the NIL SI  modes used when
    # HRC is observing, then you are loading some other SI mode which
    # "overwrites" whatever the active SI mode is. So set the loaded flag to False.
    if (not key_list) and \
       ("ACISPKT" in each_cmd["commands"]) and \
       (("TLMSID= WT" in each_cmd["commands"]) or \
        ("TLMSID= WC" in each_cmd["commands"])):
        si_mode_loaded_flag = False

    # XTZ0000005 - and an NIL SI mode was loaded . Signal the
    # NIL Start Science.
    if ("XTZ0000005" in  each_cmd["commands"]) and \
       (si_mode_loaded_flag == True):
        nil_si_mode_running = True

    # XTZ0000005 - and an NIL SI mode has NOT been loaded.  Signal that
    # an NIL SI mode has not started.
    elif ("XTZ0000005" in  each_cmd["commands"]) and \
         (si_mode_loaded_flag == False):
        nil_si_mode_running = False

    # In this case if a CC mode is started then you know that and an NIL command was not loaded
    # and cannot be running
    elif "XCZ0000005" in  each_cmd["commands"]:
        si_mode_loaded_flag == False
        nil_si_mode_running = False
        
    # COACTS1=134 - HRC Observation begins.
    # ERROR - NIL SI mode never loaded
    # Else you see an SCS-134 activation but you have NOT seen the NIL SI mode
    # load that should have come prior to this command.  This is an error. Add an error
    # comment, and print it out for the log file. This will catch all errors of this type if there
    # are one or more HRC observations in the load.
    if ("COACTS1=134" in each_cmd["commands"]) and \
         ( si_mode_loaded_flag == False):

        # Set the hrc activated and running flags to True
        hrc_running_flag = True
        hrc_activated_flag = True
        
       # Create the SCS-134 activation information line
        scs134_act_string =  each_cmd["date"] + " SCS-134 Activation: HRC Observation Begun"

        # Create the error string telling the reviewer that no acceptable SI mode was loaded
        error_comment = " ".join((scs134_act_string, "\n>>> ERROR - HRC Observation: no acceptable NIL SI Mode Load  loaded prior to an SCS-134 activation"))
        # Print it for the log file
        print("\n", error_comment)
        
        # Append the comment to the comment list
        comment_list.append([each_cmd["date"], each_cmd["time"], error_comment])

    # ERROR 
    # HRC START command but no acceptable ACIS SI mode  is  running. Give a grace
    # period of one second to account for time calculation accuracies.It may not happen the same way next time. 
    elif ("COACTS1=134" in each_cmd["commands"]) and \
         ( nil_si_mode_running == False):
        
        # Set the hrc activated and running flags to True
        hrc_running_flag = True
        hrc_activated_flag = True
         
        # Create a string to record the SCS-134 activation date 
        scs134_act_string =  each_cmd["date"] + " SCS-134 Activation: HRC Observation Begun"
        
        # Calculate the time between the start of SI mode load and the activation of
        # SCS-134. Even though we've detected that an  NIL SI mode is running, we also
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

        # Now here is the error statement due to the fact that the NIL SI mode is not running.
        error_comment = " ".join((scs134_act_string, "\n>>> ERROR - SCS-134 activated but an NIL SI mode is not running"))
        
        # Print the error out for the log file
        print("\n", error_comment)
        # Append the comment to the comment list
        comment_list.append([each_cmd["date"], each_cmd["time"], error_comment])
        
    # Else, if you have found an NIL SI mode and this command is the 
    # corresponding SCS-134 activation, you can calculate  the delta time
 
    elif ("COACTS1=134" in each_cmd["commands"]) and \
         ( si_mode_loaded_flag == True) and \
         (nil_si_mode_running == True):
        
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
    #                         clocking. And if an NIL SI mode  is running that gets
    #                         stopped too. So there's no need to differentiate between one of
    #                         the two NIL SI modes or any other.
    if  ("AA00000000" in  each_cmd["commands"]):
        nil_si_mode_running = False
        stop_science_date = each_cmd["date"]
        stop_science_time = each_cmd["time"]
        
    # 215PCAOF - HRC Observation complete.
    if ("215PCAOF" in  each_cmd["commands"]):
        # Create the string that indicates the HRC obs 15V power down command issued.
        HRC_shutdown_string = each_cmd["date"] + " 215PCAOF command: HRC Observation Ends"
        
        # Now check to see if the NIL SI mode was running at this point of
        # the load. Several situations have to be covered:
        #
        #    1) The 215PCAOF comes before the NIL SI mode stop science (i.e. NIL SI mode
        #        still running) - always OK.
        #
        #    2) SCS-134 was never activated - ERROR because if you are stopping HRC you
        #        must have expected that it was started
        #
        #    3) The NIL SI mode stop science comes before the 215PCAOF command
        #         -  Delta t between the  AA00 and 215PCAOF commands <= 1 second - OK
        #         -  Delta t between the  AA00 and 215PCAOF commands > 1 second - NOT OK
        #                - See Guideline
        #
        #
        #
        # Possibility #1 - NIL SI mode still running
        if nil_si_mode_running == True:
            comment_list.append([each_cmd["date"], each_cmd["time"], HRC_shutdown_string])
            
        # Possibility #2 - Check to see if the SCS-134 activation ever occurred
        elif hrc_activated_flag == False:
            HRC_activation_error_string = " ".join((HRC_shutdown_string, "\n>>> ERROR - SCS-134  was never activated"))
            print("\n", HRC_activation_error_string)
            comment_list.append([each_cmd["date"], each_cmd["time"], HRC_activation_error_string])

        # Possibility #3  - NIL SI mode loaded, run, and was shut down prior to 215PCAOF
        elif (si_mode_loaded_flag == True) and \
              (nil_si_mode_running == False):
            # Calculate the detla t between the NIL SI mode shutdown and this 215PCAOF command
            delta_t = each_cmd["time"]  -  stop_science_time

            # If delta t is one second or less, then the NIL SI mode was shut down closely enough
            # to this HRC shutdown to nor risk the HRC
            if delta_t <= 1:
                # Good shutdown timing with regard to the AA00000000. Record the
                # shutdown time.
                comment_list.append([each_cmd["date"], each_cmd["time"], HRC_shutdown_string])
            else: # HRC was running too long past the NIL SI mode stop science
                HRC_shutdown_error_string = " ".join((HRC_shutdown_string, "\n>>> ERROR - The NIL SI mode was shut down more than 1 second prior to  the time of HRC shutdown"))
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
            print('\n    Copying ACIS-LoadReview.txt.HRC_TXING to ACIS-LoadReview.txt')
            shutil.copy(load_week_path+'/ACIS-LoadReview.txt.HRC_TXING', load_week_path+'/ACIS-LoadReview.txt')
        except OSError as err:
            print(err)
            print('Examine the ofls directory and look for the HRC_TXING file.')
        else:
            print('    Copy was successful')
    else:
        print('\n    Leaving the ACIS-LoadReview.txt  unchanged')

else:
    print(">>> WARNING - No NIL SI mode/SCS-134 Activation pairs found in this load.")

