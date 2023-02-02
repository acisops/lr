################################################################################
#
# Backstop_File_Processing - Class to read and store the contents of a
#                                            CR*.backstop and VR*.backstop files
#                                            for use by other programs
#
################################################################################

import numpy as np

import apt_date_secs as apt
import SIM_Class as sim_class

class Backstop_File_Class:
    """
    Class defined to read a specified backstop file for processing, and store
    the contents in a numpy array.  A time column is added to the array
    which contains the time of each command in Chandra seconds. 

    Backstop file commands are roughly divided into 4 sections using a "|" for
    a delimiter.  The last section is a comma-separated string of variable length.
    So the entire string will be stored in the array and its contents can be further
    extracted by a program which needs a particular item or items in the string.

    """
    def __init__(self, ):
        self.backstop_file_path = None
        self.backstop_commands_array = None
        self.ACISPKT_array = None
        self.type_array = None

        self.sim_class_instance = sim_class.SIM_utilities()
        
        self.backstop_dtype = [("date", "|U21"), ("time", "<f8"), ("vcdu", "<i4"), ("vcdu2", "<i4"),  ("command_type", "|U13"),     ("tlmsid_string", "|U3000")]
        
    #---------------------------------------------------------------------------
    #  Method:  Read_BS_File - Read the input backstop file and store the contents
    #                                   in a class atribute
    #---------------------------------------------------------------------------
    def Read_BS_File(self, backstop_file_path):
        """
        Given a full path to the backstop file, read the file, calculate the
        Chandra Time, in seconds,  of each command and store the
        contents in the self.backstop_commands attribute which is a numpy
        array.
        """
        # Store the full path to the backstop file in an attribute
        self.backstop_file_path = backstop_file_path

        # Create an empty numpy array
        self.backstop_commands_array = np.array([], dtype = self.backstop_dtype)

        
        # Open the backstop file for reading
        bsfile = open(self.backstop_file_path, "r")

        # Read and process each line
        for eachline in bsfile:
            # Split the line on "|"
            split_line = eachline.split("|")

            # Populate the new row for the array
            new_row = np.array( [ (split_line[0].strip(),
                              apt.secs(split_line[0].rstrip()),
                              int(split_line[1].split()[0]),
                              int(split_line[1].split()[1]),
                              split_line[2].rstrip().lstrip(),
                              split_line[3][:-1]) ], dtype = self.backstop_dtype)

            # Append this new row to  self.backstop_commands_array
            self.backstop_commands_array = np.append(self.backstop_commands_array,
                                                                                      new_row, axis = 0)
            
        # Done reading the file - close it
        bsfile.close()

        # Return the populated numpy array of backstop commands
        return self.backstop_commands_array

       
    #---------------------------------------------------------------------------
    #  Method:  Process_BSH_Array
    #---------------------------------------------------------------------------
    def Process_BSH_Array(self, bsh_array):
        """
        Given an  array of backstop commands obtained from a Backstop
        History command assembly, process each command and store the
        contents in the self.backstop_commands attribute which is a numpy
        array. Backstop_History has already calculated the Chandra time
        in seconds of each command so this routine doesn't have to do that.
        """
        
        # Create an empty numpy array
        self.backstop_commands_array = np.array([], dtype = self.backstop_dtype)

        # Process each command
        for each_cmd in bsh_array:
            # Split the command column entry on "|"
            split_line = each_cmd["commands"].split("|")

            # Populate the new row for the array
            new_row = np.array( [ (each_cmd["date"],
                                               each_cmd["time"],
                                               int(split_line[1].split()[0]),
                                               int(split_line[1].split()[1]),
                                               split_line[2].rstrip().lstrip(),
                                               split_line[3][:-1]) ], dtype = self.backstop_dtype)

            # Append this new row to  self.backstop_commands_array
            self.backstop_commands_array = np.append(self.backstop_commands_array,
                                                                                      new_row, axis = 0)
            


        # Return the populated numpy array of backstop commands
        return self.backstop_commands_array
        
    #---------------------------------------------------------------------------
    #
    #  Method: Extract_TLMSID_Value
    #
    #---------------------------------------------------------------------------
    def Extract_TLMSID_Value(self, command):
        """
        Given a command of the data structure self.backstop_commands_array
        extract and return the value that TLMSID is equal to in the "tlmsid_string"
        """
        # Split the string on spaces
        split_string = command["tlmsid_string"].split()

        # Extract the value that "TLMSID is set equal to, being sure to remove
        # the comma at the end and strip out all spaces
        extracted_tlmsid_val = split_string[1][:-1].strip()

        return extracted_tlmsid_val
    
    #---------------------------------------------------------------------------
    #
    #  Method:  Extract_ACISPKTS - Extract all commands whose command type
    #                                                 is "ACISPKTS"
    #---------------------------------------------------------------------------
    def Extract_ACISPKTS(self, commands = []):
        """"
        Given the contents of a CR* or VR* backstop file have been read in,
        this method extracts all those commands whose command_type 
        is "ACISPKT", and places them in the attribute: self.ACISPKT_array

        If commands are not specified in the call the method defaults to
        self.backstop_commands_array.

        Returns an array containing just those commands.
        """

        # If the user did not specify a source of commands from which to extract
        # then default to self.backstop_commands_array
        if len(commands) == 0:
            commands = self.backstop_commands_array

        # Create an empty ACISPKT_array
        self.ACISPKT_array = np.array([], dtype = self.backstop_dtype)


        
        # Scan the commands array and look for the commands which are
        # of type "ACISPKT"
        for each_row in commands:
            if each_row["command_type"] == "ACISPKT":
                # Populate  the new row
                new_row = np.array([(each_row["date"],
                                                    each_row["time"],
                                                   each_row["vcdu"],
                                                   each_row["vcdu2"],
                                                   each_row["command_type"],
                                                   each_row["tlmsid_string"],
                                                    )], dtype = self.backstop_dtype)

                # Append the new row to  the ACISPKT array
                self.ACISPKT_array = np.append(self.ACISPKT_array, new_row, axis = 0)

        # Return the ACISPKT array
        return self.ACISPKT_array




    #---------------------------------------------------------------------------
    #
    #  Method:  Extract_Command_Types
    #                                                
    #---------------------------------------------------------------------------
    def Extract_Command_Types(self, type_list, commands = []):
        """"
        Given the contents of a CR* or VR* backstop file have been read in,
        and stored in the attribute: self.backstop_commands_array, extract
        all those commands whose command_type appears in the input list:
        type_list.   

        If commands are not specified in the call the method defaults to
        self.backstop_commands_array.

        Results are placed in the attribute: self.type_array

        Returns an array containing just those commands.
        """
        # If the user did not specify a source of commands from which to extract
        # then default to self.backstop_commands_array
        if len(commands) == 0:
            commands = self.backstop_commands_array

        # Create an empty type_array
        self.type_array = np.array([], dtype = self.backstop_dtype)

        # Scan the commands array and look for the commands which are of any
        # of the types in the list
        for each_row in commands:
            if each_row["command_type"] in type_list:
                # Populate  the new row
                new_row = np.array([(each_row["date"],
                                                    each_row["time"],
                                                   each_row["vcdu"],
                                                   each_row["vcdu2"],
                                                   each_row["command_type"],
                                                   each_row["tlmsid_string"],
                                                    )], dtype = self.backstop_dtype)

                # Append the new row to  the type array
                self.type_array = np.append(self.type_array, new_row, axis = 0)

        # Return the collected array
        return self.type_array
    

    #---------------------------------------------------------------------------
    #
    #  Method:  Extract_Type_and_TLMSID
    #                                                
    #---------------------------------------------------------------------------
    def Extract_Type_and_TLMSID(self, string_list, commands = []):
        """"
        Given the contents of a CR* or VR* backstop file have been read in,
        and stored in the attribute: self.backstop_commands_array, extract
        all those commands which contains any value in the input list in either
        the command type or the TLMSID string. 

        If commands are not specified in the call the method defaults to
        self.backstop_commands_array.

        Results are placed in the attribute: self.type_array

        Returns an array containing just those commands.
        """
        # If the user did not specify a source of commands from which to extract
        # then default to self.backstop_commands_array
        if len(commands) == 0:
            commands = self.backstop_commands_array

        # Create an empty command_array
        self.extracted_command_array = np.array([], dtype = self.backstop_dtype)

        # Scan the commands array and look for each string in either the command
        # type or the TLMSID string
        for each_cmd in commands:
            for each_string in string_list:
                if (each_string in each_cmd["command_type"]) or \
                   (each_string in each_cmd["tlmsid_string"]):
                    # Populate  the new row
                    new_row = np.array([(each_cmd["date"],
                                                        each_cmd["time"],
                                                       each_cmd["vcdu"],
                                                       each_cmd["vcdu2"],
                                                       each_cmd["command_type"],
                                                       each_cmd["tlmsid_string"],
                                                        )], dtype = self.backstop_dtype)
    
                    # Append the new row to  the extracted commands array
                    self.extracted_command_array = np.append(self.extracted_command_array, new_row, axis = 0)
    
        # Return the extracted commands array
        return self.extracted_command_array
    


    #---------------------------------------------------------------------------
    #
    #  Method: Get_Instrument - Given a backstop SIMTRANS tlmsid_string
    #                                            Return which instrument is in the focal plane
    #                                            as a string.
    #---------------------------------------------------------------------------
    def Get_Instrument(self, tlmsid_string):
        """
        The arrays that result from reading in a backstop file or extracting
        certain type of comands, e.g.:

            self.backstop_commands_array
            self.ACISPKT_array
            self.type_array

        have, as a column name, "tlmsid_string".  

        This method takes the tlmsid_string which MUST be from a SIMTRANS
        command, as an input, extracts the POS argument and calculates
        from that which instrument is in the focal plane. A string is returned
        whose values can be: ACIS-I
                                           ACIS-S
                                           HRC-I
                                           HRC-S
                                           UNKNOWN

        input: tlmsid_string element from a command array in this class

        output: A string indicating which instrument is in the focal plane

        """
        # tlmsid_string is a comma separated string containing several
        # data items. First split the string on commas.
        comma_split = tlmsid_string.split(",")

        # The first element in the list contains the sim position. Spit that
        # element on spaces.
        space_split = comma_split[0].split()
        
        # The second element in the resulting list is the SIM step position.
        # Extract that and turn it into an integer.
        step = int(space_split[1])

        # Call the Get_Instrument method in the SIM_class to obtain the
        # string specifying the instrument at that step position
        instrument = self.sim_class_instance.Get_Instrument(step)
        
        return instrument
    
        
