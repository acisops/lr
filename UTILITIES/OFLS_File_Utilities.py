#! /usr/local/bin/python

import glob

import apt_date_secs as apt
"""
Utilities which capture the information in various ancillary files which appear
in the OFLS directories.  These include:

     ACIS-History.txt 
     ACIS_History_edit.txt 
     ACIS-Continuity.txt

"""
import apt_date_secs as apt


#--------------------------------------------------------------------
#
# Function - Read_ACIS_History_file
#
#--------------------------------------------------------------------
def Read_ACIS_History_file(ofls_dir, edit=False):
    """
    The purpose of this program is to capture the information in the ACIS-History.txt 
    or the ACIS-History_edit.txt file. 

    ACIS-History.txt appears in the ofls directory of every ACIS load review directory. 

    ACIS_History_edit.txt only appears in the OFLS directory if THAT review load 
    interrupted the Continuity load due to a TOO, SCS-107, or Full Stop.  It 
    gives the status of the Continuity load at the point of interruption

    The format of the two files are identical. So one routine can be used to read
    both. 

    The line in ACIS-History.txt looks like this (all one line):
    
    2023:036:20:04:06.343 ====> CHANDRA STATUS ARRAY AT LOAD END = (ACIS-I,HETG-OUT,LETG-OUT,27683,OORMPEN,CSELFMT2,ENAB,WT00458034,WC00174014,WSPOW20002,W10011C014,TE_00458)

    Occasionally there can be a space between the SI Mode at the end of the actual
    status array and the right paren.  Like this:

    2023:030:07:38:00.000 ====> CHANDRA STATUS ARRAY AT LOAD END = (HRC-S,HETG-IN,LETG-OUT,44844,OORMPDS,CSELFMT2,ENAB,WT00CA8014,WC00174014,WSPOW20002,W10011C014,TE_00CA8B )

    That is why we first split on the equal sign and then clear any spaces from the
    status array. This is followed by splitting the status array on commas.

    input: ofls_dir The path to the ofls directory containing the ACIS-History[_edit].txt
           file you want to read.

           edit - A boolean informing the functions whether to read the 
                  ACIS-History.txt or the  ACIS-History_edit.txt file. 
                   - If False, read the ACIS-History.txt file.
           
    output: A dictionary of the information contained in the status line of the
            ACIS-History_[edit].txt file.
    """
    # Open the ACIS-History.txt file in the OFLS directory for reading
    # Check the boolean as to which file to read
    if edit:
        ofls_file = open( '/'.join((ofls_dir, 'ACIS-History_edit.txt')), 'r')
    else:
        ofls_file = open( '/'.join((ofls_dir, 'ACIS-History.txt')), 'r')
    
    
    # The file reads in as a single line and eliminate the CR at the end
    line = ofls_file.readline()[:-1]

    # Split the line on the equal sign
    splitline = line.split("=")
    
    # Capture the date stamp in the file and translate it into seconds
    hist_date = splitline[0]
    hist_time = apt.secs(hist_date)
    
    # Start the dictionary which will hold all the information from this file
    hist_dict = {'date': hist_date,
                       'time': hist_time}

    # The last list element in the split line is the status line which gives you 
    # things like the instrument, HETG and LETG status, obsid, Radmon status,
    # what format we are in, and whether Dither is enabled. Eliminate any
    # spaces that may be in the string.
    status_line = splitline[-1].replace(" ", "") 
    
    # Split the status line on commas.
    split_status_line = status_line.split(',')
    
    # Extract the information and add it to the dictionary
    hist_dict['instrume'] = split_status_line[0][1:]
    hist_dict['HETG_status'] = split_status_line[1]
    hist_dict['LETG_status'] = split_status_line[2]
    hist_dict['obsid'] = split_status_line[3]
    hist_dict['radmon_status'] = split_status_line[4]
    hist_dict['format'] = split_status_line[5]
    hist_dict['dither'] = split_status_line[6]
    
    # Done with the OFLS file - close it
    ofls_file.close()
    
    # Return the dictionary
    return hist_dict

#--------------------------------------------------------------------
#
# Function - Read_ACIS_Continuity_file
#
#--------------------------------------------------------------------
def Read_ACIS_Continuity_file(ofls_dir):
    """
    Read the contents of an ACIS-Continuity.txt file located in ofls_dir
    and return the information in a dictionary

    input: ofls_dir - Path to the OFLS directory contining the ACIS-Continuity.txt file

    output: continuity_dict - Dictionary containing the information stored
                                           in the ACIS-Continuity.txt file
    """
    # Open the ACIS-Continuity.txt file in the OFLS directory for reading
    cont_file = open( '/'.join((ofls_dir, 'ACIS-Continuity.txt')), 'r')
    
    # Read the first line which supplies the path to the Continuity file
    cont_path = cont_file.readline()[:-1]
    
    continuity_dict = {'cont_load_path': cont_path}
 
    # Read the second line which tells you if the Review load is Normal
    # in which case you will see only the word "Normal" in the line,
    # or if the Review load is a TOO, SCS-107, or Full Stop load in which
    # case you will see the type, and then the time of interrupt of the
    # Continuity load.
    load_type = cont_file.readline()

    # Done with the file - close it
    cont_file.close()

    # Split the second line on spaces
    splitline = load_type.split()

    # Store the type in the dictionary no matter which it is
    continuity_dict['type'] = splitline[0]

    # If the length of the list is one, it's a Normal load
    if len(splitline) == 1:
        # ...and the interrupt time will be set to None
        continuity_dict['interrupt_date'] = None
        continuity_dict['interrupt_time'] = None
    else:  # Else the load type is one of the three interrupt types
         continuity_dict['interrupt_date'] = splitline[1]
         continuity_dict['interrupt_time'] = apt.secs(splitline[1])

    # Finished capturing the information - return the dictionary
    return continuity_dict



#--------------------------------------------------------------------
#
# Function - Get_Continuity_Status_Line
#
#--------------------------------------------------------------------
def Get_OFLS_Status_Line(ofls_dir):
    """
    Given an OFLS directory this function will obtain the status line 
    at either the end of the Continuity load, or at the point where the
    Continuity load was cut due to a TOO, SCS-107 or Full Stop.

    input: ofls_dir - path to the OFLS directory of the Review load

    output: continuity_status - Dictionary of the contents of the status line
    """
    # If an ACIS-History_edit.txt file exists in the Review OFLS directory
    # then you can use that to capture the status data at the cut time of the
    # TOO, SCS-107 or Full Stop
    e_file = glob.glob('/'.join((ofls_dir, 'ACIS-History_edit.txt')))

    # If e_file is not empty, then read the ACIS-History_edit.txt file
    if len(e_file) != 0:
        status_line = Read_ACIS_History_file(ofls_dir, edit=True)

    else:  # There is no ACIS-History_edit.txt file in the Review OFLS
          # directory so then you obtain the path to the Continuity load directory
          # and read the ACIS-History.txt file in that directory
        cont_data = Read_ACIS_Continuity_file(ofls_dir)
        status_line = Read_ACIS_History_file(cont_data['cont_load_path'], edit=False)

    # Return the status line dictionary containing the date representing the 
    # endpoint status of the Continuity load whether it ran to completion or
    # was cut but a TOO, SCS-107 or Full Stop.
    return status_line
