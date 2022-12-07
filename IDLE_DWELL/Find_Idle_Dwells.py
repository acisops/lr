import argparse
import glob
import numpy as np
import shutil

import apt_date_secs as apt
import Calc_Delta as cd
import SIM_Class as sim_class

import Backstop_File_Processing as bfp

import Insert_Comment_In_ALR as icia

import OFLS_File_Utilities as oflsfu

"""
Idle Dwell time is defined as that time between the first stop science of an ACIS
science run and the next Start Science (XTZ or XCZ).  

This program marches through a CR*.backstop file of the review load, and 
measures  the idle dwell times and reports if any of those times are longer than
a specified cutoff value: long_dwell_cutoff.

Any time it finds an idle dwell longer than long_dwell_cutoff, the program forms 
an informational string with a date  and collects those in a list. Any items in that
list are inserted into the ACIS-LoadReview.dat file before the start science of
the next observataion.

"""
#
# Parse the input argument
#
dwell_time_parser = argparse.ArgumentParser()

# Path to the ofls directory
dwell_time_parser.add_argument("load_week_path", help="/data/acis/LoadReviews/2022/FEB2122'")

# Vehicle only flag argument as NON-POSITIONAL.  
dwell_time_parser.add_argument("--vo", help="Flag which signals to run this on the VR*.backstop file", default = "")

# Add the TEST argument as NON-POSITIONAL.  
dwell_time_parser.add_argument("-t", "--test", help="In test mode", action="store_true")

dwell_args = dwell_time_parser.parse_args()


# Inits

dwell_time_mins = 0.0
dwell_time_hours = 0.0

dwell_start_date = None
dwell_start_time = None

dwell_end_date = None
dwell_end_time = None

long_dwell_list = []

# Definition of a "Long Idle Dwell" is 1.5 hours. Convert to seconds
long_dwell_cutoff = 1.5 * 3600.0

# Create a state dictionary which tracks the state of instrument in the
# focal plane - past and present - RADMON status, and set was_an_obs
# to True.
# was_an_obs tells the system whether or not there was an ACIS observation after
# the last seen SIMTRANS. An example where there was not an observation would
# be if SIMTRANS put HRC in the focal plane and there was no NIL run for ACIS
# We don't know anything about any previous observation,
# but since we are initializing both present and previous to the same value
# then a SIMTRANS won't have any effect.
# The first_AA00_flag is used to allow the code to process the first AA00000000
# after a Start Science but none of the succeeding AA00000000's.
# radmon_status will show if Radmon is enabled or disabled
state_dict = {"radmon_state": "UNK",
                      "previous_fp_instrument": "UNK",
                      "present_fp_instrument": "UNK",
                      "was_an_obs": True,
                      "first_AA00_flag": False,
                      "radmon_status": "UNK"}

# Variable for the stop science command string.
stop_science_command = "AA00000000"

# If the review load is a full load but only the vehicle portion is to be
# executed, do nothing as LR was instructed to ignore ACISPKT commands
if (dwell_args.vo != "VOR") and \
   (dwell_args.vo != "VOB"):

    # Capture the path to the OFLS directory
    load_week_path = dwell_args.load_week_path
    
    # Find out the status at the start of this load by reading the load's
    # ACIS-Continuity.txt file to see if this is a Normal load or  other
    #        (TOO, SCS-107, FULL STOP).
    # If Normal get the values in the continuity load's ACIS-History.txt file.
    # If not Normal, get the values in the review load's ACIS-History_edit.txt file.

    # As an extra bonus, you will know whether you are in the Radzone or not
    # because the ACIS-History[_edit].txt file gives you the RADMON status

    # Read the ACIS-Continuity.txt file
    continuity_dict = oflsfu.Read_ACIS_Continuity_file(load_week_path)

    # If this load is a Normal load then use the ACIS-History.txt file located
    # In the continuity file ofls directory
    if continuity_dict["type"] == "Normal":
        hist_dict = oflsfu.Read_ACIS_History_file(continuity_dict["cont_load_path"])
    else:
        # The review load is a TOO, SCS-107 or Full stop Return to Science load
        # So read the review load's ACIS-History_edit.txt file
        hist_dict = oflsfu.Read_ACIS_History_file(load_week_path, edit=True)

    # Now set the value of previous and present instrument
    # from the hist dictionary
    state_dict["present_fp_instrument"] = hist_dict["instrume"]
    state_dict["previous_fp_instrument"] = hist_dict["instrume"]

    # Capture the RADMON status and store in the state dictionary
    state_dict["radmon_state"] = hist_dict["radmon_status"]

    # Find and read the CR*.backstop file
    # First formulate the path to the CR*.backstop file with wild cards
    partial_path = "/".join((load_week_path, "CR*.backstop"))

    # Get the name of the CR*.backstop file. There is only one per OFLS directory
    backstop_file_path = glob.glob(partial_path)[0]

    # Create an instance of the Backstop File Processing Class
    BFCI = bfp.Backstop_File_Class()
    
    # Read the backstop file and extract all commands of command type:
    #    ACISPKT, SIMTRANS,  OORMPDS, OORMPEN

    all_commands = BFCI.Read_BS_File(backstop_file_path) 

    # Extract the SIM, ACISPKT and RADMON commands out of all of the commands
    sim_acis_commands = BFCI.Extract_Type_and_TLMSID(["SIMTRANS", "ACISPKT", "OORMPDS", "OORMPEN"], all_commands)

    # ----------------------------------  BEGIN DWELL PROCESSING ---------------------------------------------------
    # The assumption here is that at the start of a load, you will not be in the middle of
    # any kind of observation (neither science nor ECS)
    # So for the first check, set the start of the search be the first command,
    # and look for the first Start Science.
    
    dwell_start_date = all_commands[0]["date"]
    dwell_start_time = all_commands[0]["time"]
    
    # Now scan through all the rest of the extracted  commands until
    # you see a start science. That defines the first "dwell"
    index = 0

    while index < len(sim_acis_commands):

        # Is this an OORMPDS command? If so set the value of the
        # state dictionary
         if "OORMPDS" in  sim_acis_commands[index]["tlmsid_string"]:
             state_dict["radmon_status"] = "RADMON_DIS"
                   
        # Is this an OORMPEN command? If so set the value of the
        # state dictionary
         if "OORMPEN" in  sim_acis_commands[index]["tlmsid_string"]:
             state_dict["radmon_status"] = "RADMON_EN"
        
        # Is this a SIMTRANS? If so set the present instrument to the commanded value
         if sim_acis_commands[index]["command_type"] == "SIMTRANS":
            # If was_an_obs is False, set the previous FP instrument to the
            # present FP instrument. When there was a previous observation,
            # the processing for the AA00 command does this.
            if state_dict["was_an_obs"] == False:
                state_dict["previous_fp_instrument"] = state_dict["present_fp_instrument"]
            # Now set the present FP instrument to this SIMTRANS command value
            state_dict["present_fp_instrument"] = BFCI.Get_Instrument(sim_acis_commands[index]["tlmsid_string"])

        # Is this a Start Science Command?
         if ("XTZ0000005" in  sim_acis_commands[index]["tlmsid_string"]) or \
           ("XCZ0000005" in  sim_acis_commands[index]["tlmsid_string"]):
            # If yes, you have enough information to calculate the Dwell Time
            dwell_stop_date = sim_acis_commands[index]["date"].lstrip().rstrip()
            dwell_stop_time = sim_acis_commands[index]["time"]
    
            # Calculate the delta t
            dwell_time_secs, dwell_time_mins, dwell_time_hours = cd.Calc_Delta_Time(dwell_start_date, dwell_stop_date)
            
            # If the instrument is ACIS-I or ACIS-S or we are in the radzone
            # executing an ECS measurement, and the dwell time is 1.5 hours or more
            # then create an entry for the long_dwell_list.
            if ( (state_dict["present_fp_instrument"] == "ACIS-I") or \
                 (state_dict["present_fp_instrument"] == "ACIS-S") or \
                 (state_dict["radmon_status"] == "RADMON_DIS") ) and \
                 (dwell_time_secs >= long_dwell_cutoff):
                dwell_string = " ".join((">>> Warning - Long Dwell:", state_dict["present_fp_instrument"], "in the F.P.",  state_dict["radmon_status"], "Dwell time: ", str(round(dwell_time_secs,1)), "seconds"))

                # Print the warning out to STDOUT so that the load reviewer sees it
                # and it gets logged in the log file we create when running lr
                print( dwell_string)
                
                # Append the dwell stop date and time, and the dwell string to
                # the list of dwell strings.  This will cause the information line
                # to appear just before the Start Science
                long_dwell_list.append([dwell_stop_date, dwell_stop_time, dwell_string])
                
            # Set the value of was_an_obs to True
            state_dict["was_an_obs"] = True
            
            # Set AAOO flag to False so that we will process the first AA00
            # command that comes after this Start Science when we get to it
            state_dict["first_AA00_flag"] = False
 
         # Check for a Stop Science: AA00000000
         if (stop_science_command in sim_acis_commands[index]["tlmsid_string"]) and \
           (state_dict["first_AA00_flag"] == False):
            
            # --------------- DWELL START: AA00 ----------------------------------------------
            # You found the  Stop Science for that observation. Capture the
            # time of that command as the dwell start date and time
            dwell_start_date = sim_acis_commands[index]["date"]
            dwell_start_time = sim_acis_commands[index]["time"]

            # Copy the present FP intrument into the previous FP instrument
            state_dict["previous_fp_instrument"] = state_dict["present_fp_instrument"] 

            # Set the AA00 flag to True so that no AA00 command between this
            # one and the next Start Science will be processed
            state_dict["first_AA00_flag"] = True
 
         # Haven't seen any Start Science commands, keep looking
         index += 1

    # Done finding any long dwells. If there are lines in long_dwell_list, insert
    # them in a copy of ACIS_LoadReview.txt called ACIS_LoadReview.txt.DWELL_COMMENT

    if len(long_dwell_list)> 0:
        icia.Insert_Comment_In_ALR(long_dwell_list, load_week_path, "DWELL_COMMENTS")


    # Copy the updated ACIS-LoadReview.txt file
    # If the test flag was False, then move the .DWELL_COMMENTS file to
    # ACIS-LoadReview.txt.
    # If it was True then we leave the original ACIS-LoadReview.txt and the
    # ACIS-LoadReview.txt.ERRORS files intact for comparison.
    if dwell_args.test == False:
        try:
            print('Moving ACIS-LoadReview.txt.DWELL_COMMENTS to ACIS-LoadReview.txt')
            shutil.move(load_week_path+'/ACIS-LoadReview.txt.DWELL_COMMENTS', load_week_path+'/ACIS-LoadReview.txt')
        except OSError as err:
            print(err)
            print('Examine the ofls directory and look for the DWELL_COMMENTS file.')
        else:
            print('Copy was successful')
    else:
        print('\nTEST MODE - Leaving the ACIS-LoadReview.txt and ACIS-LoadReview.txt.DWELL_COMMENTS files intact for comparison')
else:
    # It's a Vehicle-Only load. Inform the user and bail
    print("Vehicle_only load: No Idle Dwell Check")
    
