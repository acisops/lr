#! /usr/local/bin/python
#
# HETG_Check.py - Perigee Passage Gratings Insertion Check
#
"""

Guideline: 
https://occweb.cfa.harvard.edu/twiki/bin/view/Constraints/MPGuidelines/Development/GuidelineRadiationSafingWithoutHRC

" When HRC data is not used for onboard radiation monitoring and safing, ensure the following:

    HETG is inserted by rad entry, either during the same maneuver used to safe the 
    SIM or prior, and kept in until at least the start of the maneuver to the first 
    target exiting the rad zone Priority 2"
   
Check the Weekly load to be sure that the HETG has been inserted for the Perigee passage.

IMPORTANT: VO (Vehicle Only) loads DO NOT HAVE OORMPDS or OORMPEN
              VO loads DO have EQF013M and EEF1000 and XQF013M, XEF1000
           VpS (Vehicle plus Science) loads have EQF013M and EEF1000 and XQF013M, XEF1000
                            
           So since the proton and electron events exist in both VO and VpS files, this 
           program focuses on using EQF013M, EEF1000, XQF013M and XEF1000 to determine
           Radzone entry for all loads.

  There are 4 values you need in order to be sure the Gratings are in:

    HETG In  - MSID= 4OHETGIN
    HETG Out - MSID= 4OHETGRE
    Radzone Entry
    Radzone Exit

    In this progam these 4 commands or states will be referred to as HETG states.
    The complete set of 4 states will be referred to as a state group.

  The HETG is not guaranteed to be in prior to the HRC-S SIMTRANS, and it is usually retracted
  during the outbound ECS measurement so it's retracted prior to XEF1000. Therefore this
  program will check to be sure it's in during the Perigee Passage and will report the 
  percentage time of the passage it was in.

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
import OFLS_File_Utilities as oflsu

#
# Parse the input arguments
#
hetg_parser = argparse.ArgumentParser()
hetg_parser.add_argument("review_load_path", help="Path to the Review load directory. e.g. /data/acis/LoadReviews/2022/FEB2122/ofls'")

hetg_parser.add_argument("nlet_file_path", help="Path to the NLET file to be used in assembling the history. e.g. /data/acis/LoadReviews/TEST_NLET_FILES/FEB2122A_NonLoadTrackedEvents.txt")

args = hetg_parser.parse_args()

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
assembled_commands = BSC.Read_Review_Load(BSC.outdir)

# Capture the start date and time of the Review load
rev_start_date = assembled_commands[0]['date']
rev_start_time = assembled_commands[0]['time']

# Next, find the status of the HETG at the end of the Continuity load
cont_status = oflsu.Get_OFLS_Status_Line(load_week_path)

# Iniitalize the event dates
if cont_status['HETG_status'] == 'HETG-IN':

    HETG_in_date = cont_status['date']
    HETG_in_time = apt.secs(HETG_in_date)
    hetg_in = True
    
    HETG_out_date = None
    HETG_out_time = None
    hetg_out = False
    
    HETG_status = 'IN'
    # Inform the user that the first results are from the Continuity load.
    print('\nThis is the Continuity Load:')
    print('     ' + cont_status['date']+'      HETG INSERTED in the Continuity load')
else:

    HETG_in_date=None
    HETG_in_time=None
    hetg_in = False
    
    HETG_out_date=cont_status['date']
    HETG_out_time=apt.secs(HETG_out_date)
    hetg_out = True
    
    HETG_status = 'UNK'

EQF013M_date = None
eqf013m_acq = False

EEF1000_date = None
eef1000_acq = False

XQF013M_date = None
xqf013m_acq = False

XEF1000_date = None
xef1000_acq = False

OORMPDS_date = None
OORMPDS_time = None
oormpds_acq = False

OORMPEN_date = None
OORMPEN_time = None
oormpen_acq = False

# Tell the user what load week we are checking
print('\n HETG Check for load week: ', load_week)

# Initialize the flag which will indicate when the review load output has begun
review_load_started_flag = False

# Walk through the assembled history of commands and set dates and flags whenever
# you read a command or event that we need to note.
for each_cmd in assembled_commands:

    # If the date of this command is after the Review Load ToFC, then 
    # print a line out that delineates Continuity load HETG reports from
    # Review load HETG reports
    if (each_cmd['time'] >= rev_start_time) and \
       (not review_load_started_flag):
        # Set the flag to True so that this line gets written out only once
        review_load_started_flag = True
        # inform the user that the review load  commands are being processed
        print('\nThis is the start of the Review Load:\n')

    # If this command contains one of the components we need to note,
    # set that component's date, time and flag. For HETG insert and retract
    # commands print out the execution time of the command for the load
    # reviewer.
    if 'MSID= 4OHETGIN' in each_cmd['commands']:
        HETG_in_date = each_cmd['date']
        HETG_in_time = each_cmd['time']
        hetg_in = True
        hetg_out = False
        HETG_status = 'IN'
        print('     '+each_cmd['date']+'      HETG INSERTED')

    elif 'MSID= 4OHETGRE' in each_cmd['commands']:
        HETG_out_date = each_cmd['date']
        HETG_out_time = each_cmd['time']
        hetg_out = True
        hetg_in = False
        HETG_status = 'OUT'
        print('     '+each_cmd['date']+'      HETG RETRACTED')

    elif 'EQF013M' in each_cmd['commands']:
        EQF013M_date = each_cmd['date']
        eqf013m_acq = True

    elif 'EEF1000' in each_cmd['commands']:
        EEF1000_date = each_cmd['date']
        eef1000_acq = True

    elif 'XQF013M' in each_cmd['commands']:
        XQF013M_date = each_cmd['date']
        xqf013m_acq = True

    elif 'XEF1000' in each_cmd['commands']:
        XEF1000_date = each_cmd['date']
        xef1000_acq = True

    # If the event is EPERIGEE, determine if the HETG is in - it better be.
    elif 'EPERIGEE' in each_cmd['commands']:
        eqf013m_acq = False
        eef1000_acq = False
        # Perigee Check - if the HETG is not in by now that is an error
        if HETG_status != 'IN':
            print('>>> ERROR - We are at perigee and the HETG is not in!')
        else:
            print('     ' + each_cmd['date'], '     EPERIGEE HETG Status is:   ',HETG_status, 'ok')

    # Now check to see if this latest command that you've processed gives you enough
    # information to make an assessment

    # If you have both the EQF013M and EEF1000, you can calculate the Radmon Entry time
    if eqf013m_acq and eef1000_acq:
        # Calculate the Radzone Entry time. We imported ORP_File_Class which has
        # a method to do this, we will use that.
        OORMPDS_date, OORMPDS_time = ofci.Obtain_Rad_Entry_Time(EQF013M_date, EEF1000_date)
        # Set the flag indicating you now have the Radzone Entry time
        oormpds_acq = True
        # Set the EQF and EEF flags to false to prevent unnecessary re-calculation
        eqf013m_acq = False
        eef1000_acq = False

        # If you have acquired the OORMPDS time, check to see if the HETG is in
        if HETG_status == 'IN':
            print('     '+OORMPDS_date+'      OORMPDS - HETG status:     ', HETG_status,'ok.' )
            # Shut off the booleans acquisition of OORMPDS to avoid recalculation
            oormpds_acq = False
    
        elif HETG_status == 'OUT':
            print('     '+OORMPDS_date+'      >>>ERROR OORMPDS and HETG status is: ',HETG_status  )
            # Shut off the boolean acquisition of OORMPDS to avoid recalculation
            oormpds_acq = False
    
    # If you have both the XQF013M and XEF1000, you can calculate the Radmon Exit time
    if xqf013m_acq and xef1000_acq:
        # Calculate the Radzone Exit time. The ORP_File_Class has a handy method to do
        # this, so we will use that.
        OORMPEN_date, OORMPEN_time = ofci.Obtain_Rad_Exit_Time(XQF013M_date, XEF1000_date)
        # Show the user the execution time of OORMPEN
        print('     '+OORMPEN_date+'      OORMPEN - HETG status:     ', HETG_status )
        # Next, calculate the percentage of time of the Radzone passage the HETG was IN
        # But you can only do this if you have all the data from a perigee passage. At
        # the start and end of the loads you may not have that data
        if (OORMPDS_date != None) and \
           (OORMPEN_date != None) and \
           (HETG_in_date != None) and \
           (HETG_out_date != None):
            # Calculate the length of the perigee passage
            radzone_length = cd.Calc_Delta_Time(OORMPDS_date, OORMPEN_date)

            # If this is the end of the perigee passage and the HETG was retracted prior to
            # OORMPEN then calculate the percentage the HETG was in for the passage
            if (radzone_length[0] > 0.0) and \
               (HETG_status == 'OUT'):
                HETG_in_length = cd.Calc_Delta_Time(HETG_in_date, HETG_out_date)
                percent_in = HETG_in_length[0]/radzone_length[0] * 100.0
                print('          Percent time the HETG was in for this Perigee Passage: %.2f' % (percent_in),'%')
                # Also calculate the amount of time between the HETG Retraction and OORMPEN
                time_hetg_out = cd.Calc_Delta_Time(HETG_out_date , OORMPEN_date)
                # ...and display that for the user
                print("          The HETG retraction began %.2f hours or %.2f minutes prior to RADMON EN" % (time_hetg_out[2], time_hetg_out[1]))
                
            elif (radzone_length[0] > 0.0) and \
                 (HETG_status == 'IN'):
                # But if the HETG is still in, calculate the percentage using the OORMPEN time
                # for the HETG time interval calculation
                HETG_in_length = cd.Calc_Delta_Time(HETG_in_date, OORMPEN_date)
                percent_in = HETG_in_length[0]/radzone_length[0] * 100.0
                print('          Percent time the HETG was in for this Perigee Passage: %.2f' % (percent_in),'%')
        print('\n')
        # You are done with this Perigee Passage so set all of the flags to false
        eqf013m_acq = False
        eef1000_acq = False
        xqf013m_acq = False
        xef1000_acq = False
        oormpds_acq = False


# At this point, you have processed all the complete, radzones in the load
# Very often, however, a Radzone can be split across loads. So this check is
# for a partial radzone:
#  if we are at the end of the load and OORMPDS has occurred and OORMPEN has NOT occurred then 
#  Check the HETG status

if oormpds_acq and not oormpen_acq:
    if HETG_status == 'IN':
        print('End of load; RADMON Disabled; HETG status is: ', HETG_status, 'ok.')
    else:
        print('>>>ERROR - End of load; RADMON Disabled; HETG status is: ', HETG_status, 'not ok.')

   
