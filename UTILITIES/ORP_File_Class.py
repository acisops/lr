import glob
import numpy as np
import os

import apt_date_secs as apt

class ORP_File_Class():

    def __init__(self, orp_file_path = None):
        self.orp_file_path = orp_file_path
        self.ORBIT_EVENT_FILE_NAME = None
        self.ORBIT_EVENT_START_TIME = None
        self.ORBIT_EVENT_START_secs = None
        self.ORBIT_EVENT_END_TIME =None
        self. ORBIT_EVENT_END_secs = None
        self.orp_data_array = None
        self.orp_dtype = [('GMT', '|U21'), ('time', '<f8') , ('ORBIT', '<i4'),  ('EVENT', '|U8'),     ('DESCRIPTION', '|U50')]

        self.pad_time = 10000  # Pad time used by FOT in seconds

    #---------------------------------------------------------------------------
    #
    #  Method - Read_Orp_File
    #
    #---------------------------------------------------------------------------
    def Read_Orp_File(self, orp_file_dir):
        """
        This method will seach for a file whose name is DO*.orp in the specified path.
        It will search for the file and if it cannot find one it will return None
    
        If it finds a file, it will read the file, capture all of the informational lines
        in class attributes, then read the data and place the data in an array whose column
        names match the names at the head of the columns in the file. One extra column is
        added - time - which is the conversion of the GMT column DOY strings into Chandra
        seconds.
    
        The array is returned to the caller
    
        inputs: orp_file_dir - path to the ofls directory which contains the DO*.orp file
                              - e.g. /data/acis/LoadReviews/2022/FEB2122/ofls
    
        output: orp_data_array array containing the data within the orp file with the
                added 'time' column
    
    
        """
        # Search for the orp file in the given directory
        orp_file_path = glob.glob('/'.join((orp_file_dir, 'DO*.orp')))[0]

        # Open the ORP file
        orp_file = open(orp_file_path, 'r')
        orp_file_name = orp_file_path.split('/')[-1]

        # Capture all the "header" information lines that appear before the data
        # Most likely no needed with the possible exception of the START TIME
        # and END TIME values
        title = orp_file.readline()[:-1]
        version = orp_file.readline()[:-1]
        publish_date = orp_file.readline()[:-1]
        
        # Skip all blank lines until you get to a non-blank
        line = orp_file.readline()
        
        while line == '\n':
            line = orp_file.readline()
        
        self.ORBIT_EVENT_FILE_NAME = line[:-1].split()[-1]
        self.ORBIT_EVENT_START_TIME = orp_file.readline()[:-1].split()[-1]
        self.ORBIT_EVENT_START_secs = apt.secs(self.ORBIT_EVENT_START_TIME)
        self.ORBIT_EVENT_END_TIME = orp_file.readline()[:-1].split()[-1]
        self.ORBIT_EVENT_END_secs = apt.secs(self.ORBIT_EVENT_END_TIME)
        
        # Skip all blank lines until you get to a non-blank
        line = orp_file.readline()
        
        while line == '\n':
            line = orp_file.readline()
        
        # Capture the line containing the column headers
        header_line = line[:-1]
        
        # Skip the line of stars
        line = orp_file.readline()
        
        # You are now ready to read the data and form the array
        # Create an empty array
        self.orp_data_array = np.array([], dtype = self.orp_dtype)
        
        # Create an empty list
        orp_data_list = []
        
        for line in orp_file:
        
            # Split the line on spaces
            splitline = line.split()
        
            # Append the data to the list
            orp_data_list.append( [(splitline[0], apt.secs(splitline[0]), splitline[1], splitline[2], " ".join(splitline[3:]) )])
        
        # Once you have the list of data make the array
        self.orp_data_array = np.array(orp_data_list, dtype = self.orp_dtype)
        
        # Done with reading the input ORP file so close it.
        orp_file.close()

        # Return the Orp file data array
        return orp_file_name, self.orp_data_array
        

    
    #---------------------------------------------------------------------------
    #
    #  Method - Obtain_Rad_Entry_Time
    #
    #---------------------------------------------------------------------------
    def Obtain_Rad_Entry_Time(self, EQF013M_time, EEF1000_time):
        """
         Work out the Radzone Entry Date and Time used by MP in arriving at OORMPDS
    
         Algorithm used is the one laid out in the  Guideline: 
    
         https://occweb.cfa.harvard.edu/twiki/bin/view/Constraints/MPGuidelines/Development/GuidelineRadiationSafingWithoutHRC
    
         Inputs:  EQF013M_time - Time of the Proton Event
                  EEF1000_time  - Time of the Electron Event
    
         Outputs: Selected time of Rad Zone Entry (OORMPDS) in Chandra seconds and DOY format
    
         pad_time: Presently the 10ks backed off from EEF1000      

         The inputs are checked for type. They can be either Chandra seconds or DOY format.
         If they are DOY they are turned into Chandra seconds for calculation purposes
    
        """
        #Convert EQF013M_time into seconds if not already so
        # If the Proton event time is an integer make it a float
        if isinstance(EQF013M_time, int):
            EQF013M_time = float(EQF013M_time)
        # If it's a string then it must be DOY so convert into float seconds
        elif isinstance(EQF013M_time, str):
            EQF013M_time = apt.secs(EQF013M_time)
        
        #Convert EEF1000_time into seconds if not already so
        # If the Electron event time is an integer make it a float
        if isinstance(EEF1000_time, int):
            EEF1000_time = float(EEF1000_time)
        # If it's a string then it must be DOY so convert into float seconds
        elif isinstance(EEF1000_time, str):
            EEF1000_time = apt.secs(EEF1000_time)
    
        # EQF-----10kpad-----EEF Proton event before 10ks Pad -> 10ks Pad 
        if  EQF013M_time <= (EEF1000_time - self.pad_time):
            rad_entry_time = EEF1000_time - self.pad_time
    
        # 10kpad-----EQF-----EEF  Proton event after 10ks Pad but before Electron event -> Proton event 
        elif EQF013M_time >= (EEF1000_time - self.pad_time) and \
             (EQF013M_time <= EEF1000_time) :
            rad_entry_time =  EQF013M_time 
    
        # 10kpad-----EEF-----EQF  Proton event after Electron event -> Electron event 
        elif  EQF013M_time > EEF1000_time:
            rad_entry_time = EEF1000_time
    
        # Calculate the rad entry date from the time.
        rad_entry_date = apt.date(rad_entry_time)
    
        # Return the selected date and time for the rad entry ala RADMON DIS aka OORMPDS
        return (rad_entry_date, rad_entry_time)


    
    #---------------------------------------------------------------------------
    #
    #  Method - Obtain_Rad_Exit_Time
    #
    #---------------------------------------------------------------------------
    def Obtain_Rad_Exit_Time(self, XQF013M_time, XEF1000_time):
        """
         Work out the Radzone Exit Date and Time used by MP in arriving at OORMPEN
    
         Algorithm used is the one laid out in the  Guideline: 
    
         https://occweb.cfa.harvard.edu/twiki/bin/view/Constraints/MPGuidelines/Development/GuidelineRadiationSafingWithoutHRC
    
         Inputs:   XQF013M_time - Time of the Proton Event
                  XEF1000_time  - Time of the Electron Event
    
         Outputs: Selected time of Rad Zone Exit (OORMPEN) in Chandra seconds and DOY format
    
         pad_time: Presently the 10ks added after XEF1000

         The inputs are checked for type. They can be either Chandra seconds or DOY format.
         If they are DOY they are turned into Chandra seconds for calculation purposes
    
        """
        #Convert XQF013M_time into seconds if not already so
        # If the Proton event time is an integer make it a float
        if isinstance(XQF013M_time, int):
            XQF013M_time = float(XQF013M_time)
        # If it's a string then it must be DOY so convert into float seconds
        elif isinstance(XQF013M_time, str):
            XQF013M_time = apt.secs(XQF013M_time)
        
        #Convert XEF1000_time into seconds if not already so
        # If the Electron event time is an integer make it a float
        if isinstance(XEF1000_time, int):
            XEF1000_time = float(XEF1000_time)
        # If it's a string then it must be DOY so convert into float seconds
        elif isinstance(XEF1000_time, str):
            XEF1000_time = apt.secs(XEF1000_time)
    
        # XQF-----XEF-----10kpad Proton event before Electron event -> Electron event 
        if  XQF013M_time <= XEF1000_time:
            rad_exit_time = XEF1000_time
    
        # XEF-----XQF-----10kpad Proton event after Electron event but before 10kpad -> Proton event 
        elif (XQF013M_time >= XEF1000_time) and \
             (XQF013M_time <= (XEF1000_time + self.pad_time)) :
            rad_exit_time =  XQF013M_time 
    
        # XEF-----10kpad-----XQF  Proton event after 10kpad -> 10kpad 
        elif  XQF013M_time > (XEF1000_time + self.pad_time):
            rad_exit_time = XEF1000_time + self.pad_time
    
        # Calculate the rad entry date from the time.
        rad_exit_date = apt.date(rad_exit_time)
    
        # Return the selected date and time for the rad entry ala RADMON DIS aka OORMPDS
        return (rad_exit_date, rad_exit_time)


    #---------------------------------------------------------------------------
    #
    #  Method - Extract_Commands
    #
    #---------------------------------------------------------------------------
    def Extract_Commands(self, event_list):
        """
        This will extract any commands from an array obtained by the method Read_ORP_File.
           - It can only work with this data structure
    
        inputs: event_list - List of strings to search for within the EVENT column of the ORP command array
                               e.g. ['EQF013M',  'EEF1000'] 
    
        output: Array of located commands in time order                  
        """
        command_list = [each_cmd for each_cmd in self.orp_data_array for event in event_list if event in each_cmd['EVENT']]
            
        # Using the indices captured in the search, create an array of those rows
        command_array = np.array([], dtype = self.orp_dtype)
    
        for each_cmd in command_list:
            # Append the array row to events_array using the index found in position 0
            command_array = np.append(command_array, each_cmd, axis = 0)
    
        # Return the collected commands array
        return command_array

