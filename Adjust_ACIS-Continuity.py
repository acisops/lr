
import argparse
import shutil

import apt_date_secs as apt
#import BackstopCommandsClass
from backstop_history import BackstopHistory
"""
Adjust_ACIS-Continuity.py - LR has determined that a continuity load was reviewed as a full load,
                                              but was uplinked and run VEHICLE ONLY because the load prior to
                                              the Continuity load was interrupted by either a 107-only or a
                                              Full Stop AFTER the Continuity load was reviewed and approved.

                                              Therefore the Continuity load's ACIS-Continuity.txt file needs to
                                              be updated with the interrupt type and the time of interrupt. This
                                              information is available in the NLET file.

                                              Also important is the fact that this adjustment need only be done once:
                                              when the Review load is the A load. So this routine is only called for A loads.

                                              The NLET file entries that matter are either "S107" or "STOP"
                                              The ACIS-Continuity.txt file adjustment will be SCS-107  for S107
                                              or STOP for Full Stops.

The graphical timeline representation of events:

| Continuity-Continuity Load|    
             |
      Interrupt

                      | Continuity load built, Reviewed and Approved prior to the interrupt |

                                                                                                               |    Review Load |                                          
"""
# Create a parser instance
myparser = argparse.ArgumentParser()

# Adding  switches that are both REQUIRED and POSITIONAL

myparser.add_argument("rev_load_ofls_dir", help="Full path to the Review load Directory.")

myparser.add_argument("cont_load_dir", help="Full path to the Continuity load directory.")

myparser.add_argument("nlet_file_path", help="Full path to the NLET file.")

args = myparser.parse_args()

# Create an array of event types to recognize
event_types =  ["S107", "STOP", "VO_SCS-107"]

# Capture the command line arguments into variables.
rev_load_ofls_dir = args.rev_load_ofls_dir
cont_load_dir = args.cont_load_dir
nlet_file_path =  args.nlet_file_path
      
# Capture the Review and Continuity load week names
rev_load_week = rev_load_ofls_dir[28:35]
cont_load_week = cont_load_dir[28:35]

# Create an instance of the Backstop History class
BSC = BackstopHistory.Backstop_History_Class(
            "ACIS-Continuity.txt",
            nlet_file_path,
            rev_load_ofls_dir,
            0,
        )

# Create a path to the ACIS-Continuity.txt file
cont_load_continuity_file_path = "/".join((cont_load_dir, "ACIS-Continuity.txt"))

# Step 1 is to copy the ACIS-Continuity.txt file to ACIS-Continuity.txt.BAK
try:
    print('\n    Copying ACIS-Continuity.txt to ACIS-Continuity.txt.BAK')
    shutil.copy(cont_load_dir+'/ACIS-Continuity.txt', cont_load_dir+'/ACIS-Continuity.txt.BAK')
except OSError as err:
    print(err)
    print("Could not back up the ", cont_load_week, " ACIS-Continuity.txt file")
else:
    print('    Copy was successful')

    # Step 2 - Read the contents of the ACIS-Continuity.txt file in the Continuity load
    continuity_load_path, review_load_type, interrupt_time = BSC.get_continuity_file_info(cont_load_dir)
        
    # continuity_load_path contains the path to the Continuity load that was interrupted.
    # Find out the start and stop time of that load.  Use those times for the event searach within NLET
    cont_cont_cmds = BSC.Read_Review_Load(continuity_load_path)

    # Now collect any events that occurred between the Continuity-Continuity load start and stop
    # times
    events = BSC.Find_Events_Between_Dates(BSC.review_file_tstart, BSC.review_file_tstop)

    # Loop through any events found. If one of them is a STOP or S107 event then
    # you must modify the second line of the Continuity Load's ACIS-Continuity.txt
    # file with the Interrupt type and the interrupt time.
    for each_event in events:
        # Check to see if this event is in the array of event types to recognize
        if  each_event.split()[1] in event_types:
            
            # This is one of the events so assemble the second line of the ACSI-Continuity.txt file
            # Split the input line
            split_line = each_event.split()

            # Translate the S107 to SCS-107 if that is the event type
            if split_line[1] == "S107":
                out_event_type = "SCS-107"
            else: # Otherwise use what's there.
                out_event_type = split_line[1]
                
            # Assemble the output line with the date stamp and event type and cut time.
            out_line = out_event_type+ " "+ split_line[0] 

            # Write out the updated ACIS-Continuity.txt file
            # Open the ACIS-Continuity.txt file for writing
            f = open(cont_load_dir+"/ACIS-Continuity.txt", "w")

            # Write out the fullpath to the Continuity load
            f.write( continuity_load_path+"\n")

            # Write out the interrupt type and cut time
            f.write(out_line+"\n")

            # Close the ACIS-Continuity.txt file
            f.close()
            
                                                      
        
            
            
 
    
