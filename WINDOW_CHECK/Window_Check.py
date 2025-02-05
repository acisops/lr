from collections import Counter
#from collections import OrderedDict
import numpy as np
import os
import re
import subprocess
import sys

import SI_Mode_Class

"""
   Window_Check.py - Check any windows in each SI mode for the following faults:
 
      1) If the first window block has a sample cycle of 0 and covers the 
         entire CCD, an ERROR should be produced. 
 
      2) If the the first  window has a sample cycle of one and covers 
         part of the CCD, a warning should be produced that no events 
         will be accepted from this region
 
      3) Third if the the first window has a sample cycle of one and covers part of
         the CCD, a warning should be produced that no events will be accepted from 
         this region of the CCD and the load reviewer should check the OBSCAT 
         and perhaps check with USINT if this is what is desired.


   IMPORTANT: This program must be run under Python3 - the dictionaries it
              creates must be in the order in which the blocks appear.  Most
              especially the window blocks which must be processed in the exact
              order in wich they appear.

   A 1D window block looks like this:

      windows[0] = { ccdId                    = 5
                     ccdColumn                = 0
                     width                    = 1023
                     sampleCycle              = 0
                     lowerEventAmplitude      = 1645
                     eventAmplitudeRange      = 1305
                    }

   A 2D window block looks like this:

      windows[0] = { ccdId                    = 7
                     ccdRow                   = 49
                     ccdColumn                = 127
                     width                    = 127
                     height                   = 255
                     sampleCycle              = 1
                     lowerEventAmplitude      = 100
                     eventAmplitudeRange      = 2900
                   }

  so the blocks have to be handled differently when looking for bad blocks

  V3.0 - works through the ACIS-LoadReview.txt file and writes out the new ACIS-Load_Review.txt file
         as it goes.  It does the window checks as soon as it hits the "==> Parameter Block 
         for SI mode ...." line. Any errors it finds regarding the windows (if any) in that SI mode
         are immediately written out.

"""
# Inits
error_list = []
# regex for time stamps in ACIS-LoadReview.txt files
DOY_full_3f = re.compile('\\d\\d\\d\\d:\\d\\d\\d:\\d\\d:\\d\\d:\\d\\d.\\d\\d\\d$')

#-------------------------------------------------------------------------------
#
#  CLASS INSTANCES
#
#-------------------------------------------------------------------------------
# Create an instance of the SI_Mode_Class
si_mode_info = SI_Mode_Class.SI_Mode_Info()

#==================================================
# This is the ACIS-LoadReview.txt file

# CC_00170B in FEB1819B load
#filespec = '/data/acis/LoadReviews/2019/FEB1819/ofls/ACIS-LoadReview.txt'

#filespec = '/data/acis/LoadReviews/2020/JAN0620/ofls/ACIS-LoadReview.txt'
#filespec = '/data/acis/LoadReviews/2020/JAN1320/ofls/ACIS-LoadReview.txt'
#filespec = '/data/acis/LoadReviews/2020/JAN2020/ofls/ACIS-LoadReview.txt'
#filespec = '/data/acis/LoadReviews/2020/JAN2720/ofls/ACIS-LoadReview.txt'
#filespec = '/data/acis/LoadReviews/2020/FEB0320/ofls/ACIS-LoadReview.txt'

filespec = 'ACIS-LoadReview.txt'

# Open the input ACIS-LoadReview.txt file
in_alr = open(filespec, 'r')

# Open the OUT ACIS-LoadReview.txt.WINDOW file
#out_alr = open(filespec+'.WINDOW', 'w')
out_alr = open('ACIS-LoadReview.txt.WINDOW', 'w')

si_modes = []

# Collecting SI modes from the AIS-LoadReview.dat file
# "alr" stands for ACIS_LoadReview.txt
for eachline in in_alr:
    # Write the line out to the output file; the \n at the end of the line
    # will be preserved.
    out_alr.write(eachline)

    # Now check to see if this is the line which tells you what the
    # SI mode is for th eobservation. If it is, grab the SI mode and
    # text it for windows errors (if it hs windows)
    #  
    if '==> Parameter Block for SI mode' in eachline:
        splitline = eachline[:-1].split()
        si_mode = splitline[6]

        # Append it to the list of SI modes in case you want to look at them
        si_modes.append(si_mode)
        # Keep a single instance of all SI modes. Some loads use a mode more 
        # than once
        si_modes = list(set(si_modes))
        
        #===================================================
        #
        # These are temporary assignments for testing purposes. 
        #
        #si_mode = 
        
        #si_mode = ['TE_00586B']
        
        #si_mode = ['CC_00170B']  # BAD BLOCK
                                   # load1dBlock
                                   # ...and 4 windows
        
        #===================================================
        

        # STEP 1 - Run ratcfg/lcmd on the SI mode in order to generate the
        # ascii version of the packets. It stores the ascii in a data file
        # Located at pb_ascii_dest
        pb_ascii_dest = '/data/acis/LoadReviews/script/WINDOW_CHECK/LCMDs/'
        si_mode_info.RunRat(si_mode, pb_ascii_dest)
        
        # Read in the ratcfg output for this SI mode
        mode_lines = si_mode_info.ReadSIcfg(pb_ascii_dest, si_mode)
        
        # Ok time to build the dictionary out of the processed ratcfg output
        si_mode_info.make_si_mode_dict(si_mode, mode_lines)
    
        # Now extract useful values from the dictionary
        si_mode_info.Extract_info()
        
        #--------------------------------------------------------------------------
        #   Windows Checks - If you have windows - check them for errors.
        #--------------------------------------------------------------------------
        # A windowSlotIndex value of 65535 means there are no windows
        # whereas a 4 means you have windows.
        # So...if you have windows.....
        if si_mode_info.loadblocks_1d_keys:
            # ...check to see if there are any errors or warnings regarding
            # these windows.
            ccd_error_list, ccd_warning_list = si_mode_info.Test_1d_window_blocks()
            # If there are any error(s)......
            if ccd_error_list:
                # .....write the error(s) to the ACIS_LoadReview.txt file
                for eacherror in ccd_error_list:
                    print(eacherror[0])
                    out_alr.write(eacherror[0]+'\n')
                
            # Write out any warnings that may have occurred
            if ccd_warning_list:
                # Write the error(s) to the ACIS_LoadReview.txt file
                for eachwarning in ccd_warning_list:
                    print(eachwarning[0])
                    out_alr.write(eachwarning[0]+'\n')
    
        # Check for 2d window errors...if you have 2D windows....
        if si_mode_info.loadblocks_2d_keys:
            # Got 2d windows...check to see if there are any errors or warnings regarding
            # these windows.
            ccd_error_list, ccd_warning_list = si_mode_info.Test_2d_window_blocks()
            # If there's any errors......
            if ccd_error_list:
                # .....write the error(s) to the ACIS_LoadReview.txt file
               for eacherror in ccd_error_list:
                    print(eacherror[0])
                    out_alr.write(eacherror[0]+'\n')

            # If you have warnings, tack the time onto the list
            if ccd_warning_list:
                for eachwarning in ccd_warning_list:
                    print(eachwarning[0])
                    out_alr.write(eachwarning[0]+'\n')
    
# Close both the input an doutput files.
in_alr.close()
out_alr.close()

# OK now copy the ACIS-LoadReview.txt.WINDOW file into ACIS-LoadReview.txt
try:
    print('\nCopying ACIS-LoadReview.txt.WINDOW to ACIS-LoadReview.txt\n\n')
    mv_status = subprocess.run(['mv', 'ACIS-LoadReview.txt.WINDOW', 'ACIS-LoadReview.txt'])
except:
    print('\nThe move command failed. Examine the ofls directory and look for the .WINDOW file.\n\n', mv_status)
