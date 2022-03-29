#! /usr/local/bin/python
#
# Deadman.py - Deadman Timing Checker
#
"""

Guideline: 
https://occweb.cfa.harvard.edu/twiki/bin/view/Constraints/MPGuidelines/Development/GuidelineRadiationSafingWithoutHRC


      Ensure the following is commanded for every rad entry Priority 2: 

      Time 	                   Event 	                       Source
============================================================================================
Rad Entry Minus 48h 	Activate SCS-155 containing; 	    Weekly Loads (via fot request)
                         A_NSM_XXHR.RTS timer = 48h, 10m
                         
Rad Entry 	              Nominal SI Safing              Weekly Loads (via ORViewer)
Rad Entry + 5m 	              Disable SCS-155                Weekly Loads (via fot request)

IMPORTANT: VO (Vehicle Only) loads DO NOT HAVE OORMPDS or OORMPEN
              VO loads DO have EQF013M and EEF1000
           VpS (Vehicle plus Science) loads have EQF013M and EEF1000
           So this program focuses on using EQF013M and EEF1000 to determine Radzone
           entry for all loads.

  There are 4 values you need in order to assess the timing of the SCS-155 Deadman commands:

    SCS-155 enable
    SCS-155 activate
    Radzone Entry
    SCS-155 deactivate.

    In this program these 4 commands or states will be referred to as Deadman 155 states.
    The complete set of 4 states will be referred to as a state group.

  The Deadman timeout is fixed at 48 hours 10 minutes from activation.

"""
import argparse
import numpy as np
import sys

# Import the BackstopHistory class
from backstop_history import BackstopHistory

# ACIS Ops Imports
import apt_date_secs as apt
import Calc_Delta as cd
import ORP_File_Class as ofc

#
# Parse the input arguments
#
deadman_parser = argparse.ArgumentParser()
deadman_parser.add_argument("review_load_path", help="Path to the Review load directory. e.g. /data/acis/LoadReviews/2022/FEB2122/ofls'")

deadman_parser.add_argument("nlet_file_path", help="Path to the NLET file to be used in assembling the history. e.g. /data/acis/LoadReviews/TEST_NLET_FILES/FEB2122A_NonLoadTrackedEvents.txt")

args = deadman_parser.parse_args()

#
# Inits
# 
# Create an instance of the Backstop History class
BSC = BackstopHistory.Backstop_History_Class('ACIS-Continuity.txt',
                                             args.nlet_file_path,
                                             args.review_load_path,
                                             0)
# Create an instance of the ORP File Class
ofci =  ofc.ORP_File_Class()

load_week_path = args.review_load_path
nlet_file_path = args.nlet_file_path

# Extract the load week out from the path
load_week = load_week_path.split('/')[5]

# Read the review load - results are in BSC.master_list
bs_cmds = BSC.Read_Review_Load(BSC.outdir)

# Capture the start date and time of the Review load
rev_start_date = bs_cmds[0]['date']
rev_start_time = bs_cmds[0]['time']

# Calculate a tbegin time such that you will backchain one Continuity load.
# 50 hours will be enough - you want to capture any SCS-155 activation
# that may have occurred

tbegin_time = rev_start_time - (50.0 * 3600)
tbegin = apt.date(tbegin_time)

# Assemble the command history going back one Continuity Load.
assembled_commands = BSC.Assemble_History(BSC.outdir, tbegin, False)

# Iniitalize the event dates to None, and flags to False
COENAS1_date=None
COENAS1_time=None
scs_155_en = False
COENAS1_acq = False

COACTS1_date=None
COACTS1_time=None
scs_155_act=False
COACTS1_acq = False

EQF013M_date = None
eqf013m_acq = False

EEF1000_date = None
eef1000_acq = False

OORMPDS_date = None
OORMPDS_time = None
oormpds_acq = False

CODISAS1_date=None
scs_155_disa = False
CODISAS1_acq = False

# Tell the user what we are checking
print('\n SCS-155 Deadman Check for load week: ', load_week)

# Inform the user that the first results are from the Continuity load.
print('\nThis is the Continuity Load:')

# Initialize the flag which will indicate when the review load output has begun
review_load_started_flag = False

# Walk through the assembled history of commands and set dates and flags whenever
# you read a command or event that we need to note.
for each_cmd in assembled_commands:

    # If the date of this command is after the Review Load ToFC, then 
    # print a line out that delineates Continuity load deadman reports from
    # Review load Deadman reports
    if (each_cmd['time'] >= rev_start_time) and \
       (not review_load_started_flag):
        # Set the flag to True so that this line gets written out only once
        review_load_started_flag = True
        # inform the user that the review load  commands are being processed
        print('\nThis is the start of the Review Load:\n')

    # If this command contains one of the components we need to note,
    # set that component's date, time and flag. For SCS155 enable and activate
    # commands print out the execution time of the command for the load
    # reviewer.
    if 'COENAS1=155' in each_cmd['commands']:
        COENAS1_date = each_cmd['date']
        COENAS1_time = each_cmd['time']
        scs_155_en = True
        COENAS1_acq = True
        print('     '+each_cmd['date']+'      SCS 155 Enable COENAS1')

    elif 'COACTS1=155' in each_cmd['commands']:
        COACTS1_date = each_cmd['date']
        COACTS1_time = each_cmd['time']
        scs_155_act=True
        COACTS1_acq = True
        print('     '+each_cmd['date']+'      SCS 155 Activate COACTS1')

    elif 'EQF013M' in each_cmd['commands']:
        EQF013M_date = each_cmd['date']
        eqf013m_acq = True

    elif 'EEF1000' in each_cmd['commands']:
        EEF1000_date = each_cmd['date']
        eef1000_acq = True

    elif 'CODISAS1=155' in each_cmd['commands']:
        CODISAS1_date = each_cmd['date']
        CODISAS1_time = each_cmd['time']
        scs_155_disa = True
        CODISAS1_acq = True

    # If the event is EPERIGEE
    elif 'EPERIGEE' in each_cmd['commands']:
        print('     '+each_cmd['date']+'      EPERIGEE')
        # Check to see if you got all three commands required to manage
        # SCS-155 handling.  If you got here and you didn't then one
        # or more commands were left out of the load
        if not COENAS1_acq:
            print('>>>ERROR - There was no COENAS1 command this orbit.')
        if not COACTS1_acq:
            print('>>>ERROR - There was no COACTS1 command this orbit.')
        if not CODISAS1_acq:
            print('>>>ERROR - There was no CODISAS1 command this orbit.')

        # Clear all flags in preparation for the next orbit
        scs_155_act=False
        scs_155_en = False
        oormpds_acq=False
        scs_155_disa = False
        eqf013m_acq = False
        eef1000_acq = False
        COENAS1_acq = False
        COACTS1_acq = False
        CODISAS1_acq = False
        print('\n')

    # Now check to see if this latest command that you've processed gives you enough
    # information to make an assessment

    # If you have both the EQF013M and EEF1000, you can calculate the Radmon Entry time
    if eqf013m_acq and eef1000_acq:
        # Calculate the Radzone Entry time. Since we imported ORP_File_Class which has
        # a method to do this, we will use that.
        OORMPDS_date, OORMPDS_time = ofci.Obtain_Rad_Entry_Time(EQF013M_date, EEF1000_date)
        # Set the flag indicating you now have the Radzone Entry time
        oormpds_acq = True
        # Set the EQF and EEF flags to false to prevent unnecessary re-calculation
        eqf013m_acq = False
        eef1000_acq = False

    # If SCS-155 is enabled and activated, and if you have acquired the OORMPDS time
    # after the 155 enable and activate, then you can check the time interval between
    # SCS-155 enable and OORMPDS.
    if scs_155_en and scs_155_act and oormpds_acq:
        # Set the required secondss between SCS-155 enable and OORMPDS
        required_minutes = 2880.0
        required_seconds = (48.0 * 3600.0)

        delta_t_seconds, delta_t_minutes, delta_t_hours = cd.Calc_Delta_Time(COENAS1_date, OORMPDS_date)
        # Check the value returned - it should be 48 hours
        required_v_actual = required_seconds - delta_t_seconds

        # If the time delta between SCS-155 enable and OORMPDS differs by less
        # than 3 minutes, all is good. Otherwise throw an error
        if abs(required_seconds - delta_t_seconds) <= 180.0:
            print('     '+OORMPDS_date+'      RADMON DISABLE  ==> Time between 155 ENABLE and OORMPDS:  %.4f hours off by %.4f seconds.  Ok.' % (delta_t_hours, required_v_actual) )
        else:
            print('     '+OORMPDS_date+'      RADMON DISABLE ==> Time between 155 ENABLE and OORMPDS: %.4f hours off by %.4f seconds. ERROR.' % (delta_t_hours, required_v_actual) )

        # Shut off the booleans for enable and activate to avoid recalculation
        scs_155_en=False
        scs_155_act=False

    # If you have acquired the OORMPDS time and the SCS-155 DISABLE time
    # then you can calculate the delta shutoff time between RADMON DIS and 
    # SCS-155 DISA
    if oormpds_acq and scs_155_disa:
        delta_t_sec, delta_t_minutes, delta_t_hours = cd.Calc_Delta_Time(OORMPDS_date, CODISAS1_date)
        # Check the calculated time delta - it should be 5 minutes (rounded)
        delta_t_minutes = round(delta_t_minutes, 0)
        if delta_t_minutes == 5.0:
            print('     '+CODISAS1_date+'      SCS-155 Disable ==> Time between OORMPDS and SCS-155 DISA', delta_t_minutes, 'minutes. Ok.')
        else:
            print('     '+CODISAS1_date+'      SCS-155 Disable >>> ERROR: Time Between OORMPDS and DEACTIVATION is NOT 5 minutes: ', delta_t_minutes, 'minutes' )

        # Calculate the prospective deadman timeout time.
        # There is a special case where the Continuity load begins with
        #   EQF013M, CODISAS1=155, and EEF1000
        # The enable and activate commands appeared in the load before the continuity load.
        # When this happens, you can do the calculation above which compares only the
        # RADMON DIS time with the SCS-155 disable time.  But you cannot proceed to
        # this next section which calculates the time delta between SCS-155 activation
        # and RADMON DIS (because you don't have the activation time). This is only
        # a problem at the start analysis of the Continuity load.
        if COACTS1_time is not None:
             deadman_timeout_secs = COACTS1_time + (48.0 * 3600.0) + (10.0 * 60.0)
             deadman_timeout_date = apt.date(deadman_timeout_secs)
     
             # Print out the expected Deadman timeout date
             print('     '+deadman_timeout_date+'      SCS 155 Timeout & Execution (Activate + 002:00:10)')
     
             # Check to see if it is 5 minutes after the CODISAS1 and 10 minutes after OORMPDS
             delta_t_sec, delta_t_minutes, delta_t_hours = cd.Calc_Delta_Time(OORMPDS_date, deadman_timeout_date)
             # Round off to the nearest minute
             delta_t_minutes = round(  delta_t_minutes, 0)
             if delta_t_minutes == 10.0:
                 print('          ==> Time between OORMPDS and Deadman Timeout:', delta_t_minutes, 'minutes. Ok.')
             else:
                 print('>>>WARNING: Time Between OORMPDS and Deadman Timeout is not 10 mins.: ', delta_t_minutes, 'minutes' )
     
             # Double check to be certain the Deadman timeout is not before the deadman DISA
             if deadman_timeout_secs <= CODISAS1_time:
                 print('>>> Error Deadman Timeout at: %s occurs on or before the SCS-155 Disable Command at: %s' % (deadman_timeout_date, CODISAS1_date ) )

        # Shut off the remaining booleans in preparation for the next orbit
        oormpds_acq=False
        scs_155_disa = False

# At this point, you have processed all the complete, 4 state, Deadman 155 
# state groups in the Review load. But Deadman 155 state groups can be split
# across loads. For example it's common that the SCS-155 enable and activate
# appear at the end of this week's review load, but the Radzone Entry will
# appear in next week's. But you don't have next week's load to assess
# the timing of the enab/act with the future Radzone Entry.
#
# We have the 4 flags used in the above loop:
#   scs_155_act
#   scs_155_en
#   oormpds_acq
#   scs_155_disa
# Their values, at the end of the loop, tell us which, if any of the
# 4 states in the group have been commanded. The possibilities are:
#
#                   Flags                              Action
#   scs_155_act scs_155_en oormpds_acq scs_155_disa
#      False        False     False      False       No action - analysis complete
#      True         False     False      False       No action - not enough data
#      True         True      False      False       Use ORP file for Radzone Entry
#      True         True      True       False       No action -  not enough data
#
# The only data available for assessing the future is the Orbit Events File 
# a.k.a. the ORP file. The ORP file contains only orbital events such as 
# EQF013M and EEF1000. The ORP file is used to build the load and extends
# beyond the end of the load. It is delivered with the weekly backstop tarball.
# lr has been modified to extract that file from the tarball and place it 
# in the weekly ofls directory.
#
# As there are no commands in the ORP file that would enable/disable SCS-155,
# The only further processing we can do is the third case: where SCS-155 has
# been enabled and activated but the Radzone Entry won't appear until the
# next week's load.

# If you have SCS-155 enabled and activated but the Radzone Entry time is
# not available, use the ORP file to determine the future Radzone Entry.
if scs_155_act and scs_155_en and not oormpds_acq:

    # Read the ORP file located in the ofls directory
    orp_file_name, orp_cmds = ofci.Read_Orp_File(load_week_path)
    
    # Find the review load time of last command (tolc) which is either the enable
    # date or the activate date whichever is latest
    
    if apt.secs(COENAS1_date) > apt.secs(COACTS1_date):
        tolc = COENAS1_time
        dolc = COENAS1_date
    else:
        tolc = COACTS1_time
        dolc = COACTS1_date

    # Set up the list to extract, from the orp file array, entries whose
    # EVENT column values are EQF013M and EEF1000
    ex_cmds = ofci.Extract_Commands(['EQF013M',  'EEF1000'])

    # Find all those EQF and EEF rows whose time is after the time of last command
    indices_after = np.where(ex_cmds['time'] > tolc)
    # Grab the first two resultant indices
    first = indices_after[0][0]
    next = indices_after[0][1]
    
    # Check and be sure they are in the same orbit.  If they are, all is well
    # so calculate the Radzone Entry Time
    if ex_cmds[first]['ORBIT'] == ex_cmds[next]['ORBIT']:
        OORMPDS_date, OORMPDS_time = ofci.Obtain_Rad_Entry_Time(ex_cmds[first]['time'], ex_cmds[next]['time'])
        print('     '+OORMPDS_date+ '      Projected Radmon Disable from ORP file: ', orp_file_name)
        # Calculate the prospective deadman timeout time.
        deadman_timeout_secs = COACTS1_time + (48.0 * 3600.0) + (10.0 * 60.0)
        deadman_timeout_date = apt.date(deadman_timeout_secs)
     
        # Expected length of the deadman timer in minutes
        expected_deadman_timer = 48.0 * 60.0

        # Print out the expected Deadman timeout date
        print('     '+deadman_timeout_date+'      SCS 155 Timeout & Execution (Activate + 002:00:10)')

        # Now you have everything you need to check the timing of the SCS-155
        # enable and activate commands. Determine the actual time delta between SCS-155
        # enable and Radmon Entry
        delta_t_sec, delta_t_minutes, delta_t_hours = cd.Calc_Delta_Time(COENAS1_date, OORMPDS_date)

        # Check the value returned - it should be 48 hours 
        delta_t_minutes_r = round(delta_t_minutes, 0)

        # Compare the prospective to the actual with an allowable difference or 3 minutes
        if abs(delta_t_minutes_r - expected_deadman_timer) <=3.0:
            print('          ==> The time between ENABLE and OORMPDS: %.2f hours. Ok.' % (delta_t_hours) )
        else:
            print('>>>ERROR: Time Between ENABLE and OORMPDS is NOT 48 hours: %f hours' % (delta_t_hours))
            print('    Nominal Timer length: ', expected_deadman_timer)
            print('      Actual Timer length: ', delta_t_minutes_r)
            print('           difference: ', expected_deadman_timer - delta_t_minutes_r,  'minutes')

    else:
        print('\n Big Trouble - the EEF and EQF are not in the same orbit')


