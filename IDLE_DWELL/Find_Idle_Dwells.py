import argparse
import glob
import numpy as np
import shutil

import apt_date_secs as apt
import Calc_Delta as cd
import SIM_Class as sim_class

from backstop_history import BackstopHistory

import Backstop_File_Processing as bfp

import Insert_Comment_In_ALR as icia

import OFLS_File_Utilities as oflsfu

"""
Idle Dwell time is defined as that time between the first stop science of an ACIS
science run and the Start Science (XTZ or XCZ) of the next ACIS science run.

This program marches through a CR*.backstop file of the continuity and
review loads, and  measures  the idle dwell times.  The program will write
a warning out if any of those times are longer than a specified cutoff value: 

long_dwell_cutoff.

The continuity load is scanned so that any delta t violation between the last
observation of the continuity load and the first observation of the review load
is reported. Often perigee passages are split between loads. perigee passages
may have both inbound and outbound ECS measurements, or just inbound, 
or just outbound, or neither.

All time deltas between the Stop Science and the next Start Science are calculated.
But they are only reported if they exceed the delta limit. Presently the limit is 1.5 hours.

The only case where a time delta exceeding long_dwell_cutoff is NOT reported
is the long delay between the inbound and the outbound ECS measurement,
should both exist.  There is always a WSPOW0002A command after the EEF1000
time, so this long dwell is safe.   So it was easier to write the program to find only
those  cases where a warning should NOT be issued.

If the inbound ECS measurement is missing there still could be a very long 
delay between the stop science of the last science measurement before the
perigee passage  and the next ACIS Start Science. So a warning is given
and the reviewer will have to assess the situation. 

There could be warnings in the Continuity Load but they are ignored as they
were reported when the Continuity load was checked as the Review Load.
Any warnings occurring prior to the Time of First Command of the Review load
are not entered into the list of idle dwell warnings.

Any time it finds an idle dwell longer than long_dwell_cutoff, that should be reported,
the program forms  an informational string with a date  and collects those in a list.
Any items in that list are inserted into the ACIS-LoadReview.dat file at the point
of the start science where the measured dwell ends.

IMPORTANT: This program must be run AFTER LR has created the CR*backstop.hist
file

"""

#
# Parse the input argument
#
dwell_time_parser = argparse.ArgumentParser()

# Path to the ofls directory
dwell_time_parser.add_argument("load_week_path", help="/data/acis/LoadReviews/2022/OCT3122'")

# Vehicle only flag argument as NON-POSITIONAL.  
dwell_time_parser.add_argument("--vo", help="Flag which signals to run this on the VR*.backstop file", default = "")

# Add the TEST argument as NON-POSITIONAL.  
dwell_time_parser.add_argument("-t", "--test", help="In test mode", action="store_true")

dwell_args = dwell_time_parser.parse_args()

load_week_path = dwell_args.load_week_path
vo_arg = dwell_args.vo
test_flag = dwell_args.test

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

# Create an instance of Backstop_History
BSHI = BackstopHistory.Backstop_History_Class(outdir = "./", verbose = 0)

# Variable for the stop science command string.
stop_science_command = "AA00000000"
start_science_command_list = [ "XCZ0000005", "XTZ0000005"]

# Create an instance of Backstop_History
BSHI = BackstopHistory.Backstop_History_Class(outdir = "./", verbose = 0)

# Read the Review load. The ONLY reason we do this read is to get the time
# of first command of the review load.
rev_cmds = BSHI.Read_Review_Load(load_week_path)

# If the Review load is a maneuver-only load or if the Review load is a full
# load but the VOR or VOB switch was used in the LR command line,
# do nothing. Maneuver-only loads are not indicated by a VOR or VOB
# switch to the LR command
if (len([index  for index,each_cmd in enumerate(rev_cmds["commands"]) if "ACISPKT" in each_cmd]) != 0) and \
   (vo_arg not in ["VOR", "VOB"]):

    # Read the Time of First Command of the review load via it's attribute
    ToFC_review = BSHI.review_file_tstart
    DoFC_review = apt.date(ToFC_review)
    
    # Now read the CR*.backstop.hist file
    hist_file = glob.glob(load_week_path+"/CR*.backstop.hist")

    assembled_cmds = BSHI.read_CR_backstop_file(hist_file[0])

    # Create an instance of the Backstop File Processing Class
    BFCI = bfp.Backstop_File_Class()

    # Process the assembled commands through the method which converts the commands
    # into a numpy array with individual columns such as date, time,  command_type,
    # TLMSID string etc. This prepares it for the extraction of specific commands
    processed_history = BFCI.Process_BSH_Array(assembled_cmds) 

    # Create a list of tokens which tells the program which commands to extract
    token_list = ["SIMTRANS", "XCZ0000005", "XTZ0000005", "AA00000000", "OORMPDS", "EPERIGEE", "OORMPEN"]

    # Extract the SIMTRANS, Start and Stop Science, and RADMON commands
    # out of the assembled and processed commands
    sim_acis_cmds = BFCI.Extract_Type_and_TLMSID(token_list, processed_history)
    
    # Now remove all the extra AA00000000's except the one immediately after
    # any  Start Science as we don't need them. Also, the very first command in this
    # array will always be AA00000000 and you need to keep that. So start the
    # index at 1.
    index = 1

    # We are going to use masks to delete rows so create an empty mask list
    AA_mask_list = []

    # Set the start science flag to False.  This is the trigger to tell you to
    # keep the next AA00.
    start_sci_flag = False
    
    while index < len(sim_acis_cmds):
        # If this is a stop science command and we haven't seen a start science
        # we want to eliminate this line. Append it to AA_mask_list
        if (stop_science_command in sim_acis_cmds[index]["tlmsid_string"]) and \
           (start_sci_flag == False):
            AA_mask_list.append(index)

        # If this is a start science command, set the start_sci_flag to True
        if any( cmd in sim_acis_cmds[index]["tlmsid_string"] for cmd in start_science_command_list):
            start_sci_flag = True

        # If this is a stop science command and it's the first one after a
        # start science, set the start_sci_flag to False but don't add
        # this line to the masking list
        if  (stop_science_command in sim_acis_cmds[index]["tlmsid_string"]) and \
            (start_sci_flag == True):
            start_sci_flag = False
            
        index += 1

    # Delete all those rows in the mask
    working_array = np.delete(sim_acis_cmds, AA_mask_list, 0)

    # working_array is the array of events we will scan and analyze for long
    # idle dwells

    # Initialize the Perigee Passage dictionary.  This data structure keeps track
    # of whether or not inbound and/or outbound ECS measurements were
    # executed.
    perigee_passage_dict = {"radmon_dis_date": "1999:001:00:00:00.00",
                                             "radmon_dis_time": apt.secs("1999:001:00:00:00.00"),
                                             "radmon_state": "DISA",
                                             "eperigee_state": False,
                                             "inbound_ecs_taken": False,
                                             "outbound_ecs_taken": False}
    # Initialize the index
    index = 0
    # Initialize the dwell start date to the date of first commnd of the working
    # array. This will generate a false delta t but as it's inthe continuity load
    # any violations will be discarded.
    dwell_start_date = working_array[index]["date"]
    
    # For each line in working array...
    while index < len(working_array):
        
        # OORMPDS - Is this line a RADMON DISABLE entry
        if "OORMPDS" in working_array[index]["tlmsid_string"]:
            # Initialize the perigee_passage_dict
            perigee_passage_dict = {"radmon_dis_date": working_array[index]["date"],
                                                     "radmon_dis_time": working_array[index]["time"],
                                                     "radmon_state": "DISA",
                                                     "eperigee_state": False,
                                                     "inbound_ecs_taken": False,
                                                     "outbound_ecs_taken": False}

        # EPERIGEE - If this is this line an EPERIGEE line, set the perigee passage
        #                    eperigee state to True
        if "EPERIGEE" in working_array[index]["tlmsid_string"]:
            # Set the state of perigee in the perigee passage dict to True
            perigee_passage_dict["eperigee_state"] = True
            
        # OORMPEN - If this is this line a RADMON ENABLE initialize the
        #                     initialize the perigee passage dict
        if "OORMPEN" in working_array[index]["tlmsid_string"]:
            # Since RADMON is now enabled,  you no longer need the data stored
            # in the perigee passage dict for this perigee passage So re-init the dict. 
            perigee_passage_dict = {"radmon_dis_date": "1999:001:00:00:00.00",
                                                     "radmon_dis_time": apt.secs("1999:001:00:00:00.00"),
                                                     "radmon_state": "ENAB",
                                                     "eperigee_state": False,
                                                     "inbound_ecs_taken": False,
                                                     "outbound_ecs_taken": False}
    
        # SIMTRANS - If this is the SIMTRANS command, process it
        if working_array[index]["command_type"] == "SIMTRANS":
            # Fill in the previous obs data structure with values from the
            # state dictionary
            
            # Extract the step value and translate that into an instrument
            # string

            # Fill in the values that changed due to a SIM translation
            instrument =  BFCI.Get_Instrument(working_array[index]["tlmsid_string"])

        # START SCIENCE - Is this a start science command? If so you have enough
        # information to  calculate the dwell time
        if any( cmd in working_array[index]["tlmsid_string"] for cmd in start_science_command_list):

            # If yes, you have enough information to calculate the Dwell Time
            dwell_stop_date = working_array[index]["date"].strip()
            dwell_stop_time = working_array[index]["time"]
    
            # Calculate the delta t
            dwell_time_secs, dwell_time_mins, dwell_time_hours = cd.Calc_Delta_Time(dwell_start_date, dwell_stop_date)

            # Report the dwell time if dwell time is >= to the cutoff, and this is not the gap
            # between ECS measurements.  Set the report_flag to True.
            report_flag = True

            # INBOUND ECS- If the present observation is an inbound ECS measurement
            #                   record that
            if (perigee_passage_dict["radmon_state"] == "DISA") and \
               (perigee_passage_dict["eperigee_state"] == False):
                # Then this start science is for the inbound ECS measurement
                perigee_passage_dict["inbound_ecs_taken"] = True
                

            # OUTBOUND ECS - If the present observation is an outbound ECS measurement
            #                               record that
            if (perigee_passage_dict["radmon_state"] == "DISA") and \
               (perigee_passage_dict["eperigee_state"] == True):
                perigee_passage_dict["outbound_ecs_taken"] = True
                
                # Since this is an outbound ECS meaurement, check to see if there
                # was an inbound ECS measurement. If there was, then DO NOT
                # report the violation of the time gap between the two ECS obs
                if (perigee_passage_dict["inbound_ecs_taken"] == True) and \
                   (perigee_passage_dict["outbound_ecs_taken"] == True):
                    report_flag = False

            # If the report flag is True and the calculated dwell is >= the long dwell cutoff time
            if (report_flag == True) and \
               (dwell_time_secs >= long_dwell_cutoff) and \
               (working_array[index]["time"] >= ToFC_review):
                dwell_string = " ".join((">>> Warning - Long Dwell:", working_array[index]["date"],  "Dwell time: ", str(round(dwell_time_secs,1)), "seconds"))


                # Print the warning out to STDOUT so that the load reviewer sees it
                # and it gets logged in the log file we create when running lr
                print( "\n", dwell_string)
                
                # Append the dwell stop date and time, and the dwell string to
                # the list of dwell strings.  This will cause the information line to appear just
                # before the Start Science in ACIS-LoadReview.dat.
                if dwell_stop_time >= ToFC_review:
                    long_dwell_list.append([dwell_stop_date, dwell_stop_time, dwell_string])


       # AA00000000 - Is this line a Stop Science line?
        if stop_science_command in working_array[index]["tlmsid_string"]:
            # Yes. Set the dwell start date and time
            dwell_start_date = working_array[index]["date"]
            dwell_start_time = working_array[index]["time"]
            
        # Look at the next row in the working array
        index += 1
        
    # Done finding any long dwells. If there are lines in long_dwell_list, insert
    # them in a copy of ACIS_LoadReview.txt called ACIS_LoadReview.txt.DWELL_COMMENT
    if len(long_dwell_list)> 0:
        icia.Insert_Comment_In_ALR(long_dwell_list, load_week_path, "DWELL_COMMENTS")

        # Copy the updated ACIS-LoadReview.txt file
        # If the test flag was False, then move the .DWELL_COMMENTS file to
        # ACIS-LoadReview.txt.
        # If it was True then we leave the original ACIS-LoadReview.txt and the
        # ACIS-LoadReview.txt.DWELL_COMMENTS files intact for comparison.
        if dwell_args.test == False:
            try:
                print('\nMoving ACIS-LoadReview.txt.DWELL_COMMENTS to ACIS-LoadReview.txt')
                shutil.copy(load_week_path+'/ACIS-LoadReview.txt.DWELL_COMMENTS', load_week_path+'/ACIS-LoadReview.txt')
            except OSError as err:
                print(err)
                print('Examine the ofls directory and look for the DWELL_COMMENTS file.')
            else:
                print('    Copy was successful')
        else:
            print('\nTEST MODE - Leaving the ACIS-LoadReview.txt  unchanged')

    else: # long_dwell_list length <= 0 Let the user know in the log file.
        print("\nNo Idle Dwells above the specified length of: ", long_dwell_cutoff, " seconds.")

else: # The Review Load is a maneuver-only load
    print("\nReview Load is either a maneuver-only load or a full load with only the Vehicle Load executing - No Idle Dwell Check.")
    

    
          
