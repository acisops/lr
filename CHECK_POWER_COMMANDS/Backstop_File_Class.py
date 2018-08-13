################################################################################
#
#  Backstop_File_Class - Class defined to read a specified backstop file
#                        But also provides methods to write out a new
#                        backstop file complete with any error messages
#                        generated by the Check_Power_cmds program. 
#
################################################################################
import pprint
import re
import numpy as np

from Chandra.Time import DateTime

class Backstop_File_Object:
    """
    Class defined to read a specified backstop file for processing,
    maintain the data of the previous ACISPKT command that was processed,
    and provides a method to write out a new ACIS-LoadReview.txt file 
    complete with any error messages generated by the Check_Power_cmds program. 

    Methods:  strip_out_ACISPKTs 
              write_previous_ACISPKT_cmd
              insert_errors

    """
    def __init__(self, ):
        self.backstop_file_name =  ''
        self.error_list = []
        self.system_packets = None
        # Dtype definition for the ACISPKT lines in the Backstop file
        self.ACISPKT_dtype = [('event_date', '|S20'), ('event_time', '<i8'), ('cmd_type', '|S20'),('packet_or_cmd', '|S80')]
        # Create the empty array using the self.ACISPKT_dtype
        self.system_packets = np.array( [], dtype = self.ACISPKT_dtype)
        # Previous ACISPKT command used for timing calcs
        self.previous_ACISPKT_cmd =  np.array( [], dtype = self.ACISPKT_dtype)

        # Define regular expressions to be used in backstop file line searches
        self.time_stamp = re.compile('\d\d\d\d:\d\d\d:\d\d:\d\d:\d\d.\d\d\d')
        self.stop_sci = re.compile('AA00000000')
        self.radmon_dis = re.compile('OORMPDS')
        self.eef = re.compile(' EEF1000')
        self.wspow_000 = re.compile('WSPOW00000')
        self.wspow_02A = re.compile('WSPOW0002A')
        self.ACISPKT = re.compile('ACISPKT')

    #---------------------------------------------------------------------------
    #  Method:  strip_out_ACISPKTS - Read the input backstop file and strip
    #                                out packets useful to the power command
    #                                checker. These would be ACISPKTS and some
    #                                ORBPOINTS
    #---------------------------------------------------------------------------
    def strip_out_pertinent_packets(self, backstop_file):
        """
        Opens the specified backstop file, reads in 
        every line, strips out all ACISPKT lines plus
        lines that contain perigee passage information,
        and writes the collection of stripped-out lines
        to a file names <backstop_file.ACISPKTs
        """

        # These are the perigee passage indicators we want to recognize
        pp_indicators = ['OORMPDS', 'EEF1000', 'EPERIGEE', 'XEF1000', 'OORMPEN']
        
        # create file name for the output file by adding an '.ACISPKTs' extension
        ACISPKT_file = backstop_file+'.ACISPKTs'
        
        # Open the output file
        outfile = open(ACISPKT_file, 'w')
        
        # Open the load review text file
        infile = open(backstop_file, 'r')
        # Read in each line. If the line contains 'ACISPKT" then
        # write it to the output file
        for eachline in infile:
            # If it's an ACISPKT line grab it without question
            if ('ACISPKT' in eachline):
                # Save it in the output file
                outfile.write(eachline)
                # Now extract the date and TLMSID values
                # Start by splitting the line on vertical bars
                split_line = eachline.split('|')
                # Extract and clean up the date entry - remove any spaces
                packet_time = split_line[0].strip()
                cmd = split_line[3].split(',')[0].split()[-1]
                # Load up an array line.  You need only grab
                # the date, time, insert the word ACISPKT, and the mnemonic
                self.system_packets = np.r_[self.system_packets,
                                     np.array( [ ( split_line[0],
                                                   DateTime(packet_time).secs,
                                                   'ACISPKT',
                                                   cmd) ],
                                               dtype = self.ACISPKT_dtype) ]
        
            # Next check if the line is one of the perigee Passage indicators
            if [True for pp_ind in pp_indicators if (pp_ind in eachline)]:
                # You have stumbled upon a perigee passage indicator
                # Save it in the output file
                outfile.write(eachline)
                # Now extract the date and TLMSID values
                # Start by splitting the line on vertical bars
                split_line = eachline.split('|')
                # Extract and clean up the date entry - remove any spaces
                packet_time = split_line[0].strip()
                cmd = split_line[3].split(',')[0].split()[-1]
                cmd_type = split_line[2].strip()
                # Load up an array line.  You need only grab
                # the date, time, insert the word ACISPKT, and the mnemonic
                self.system_packets = np.r_[self.system_packets,
                                     np.array( [ ( split_line[0],
                                                   DateTime(packet_time).secs,
                                                   cmd_type,
                                                   cmd) ],
                                               dtype = self.ACISPKT_dtype) ]
                 
        
        
        # Done with the input file - close it.
        infile.close()
        
        # Done with the output file
        outfile.close()
        
        # Return the extracted packets
        return self.system_packets
    
    #---------------------------------------------------------------------------
    #
    # Method: write_previous_ACISPKT_cmd - Given one line out of 
    #                                      system_packets, record the values
    #                                      in self.previous_ACISPKT_cmd
    #
    #---------------------------------------------------------------------------
    def write_previous_ACISPKT_cmd(self, system_packet_line):
        """
        Given one line out of 
        system_packets, record the values
        in self.previous_ACISPKT_cmd
        """
        self.previous_ACISPKT_cmd = system_packet_line
    
    #---------------------------------------------------------------------------
    #
    # Method: write_bogus previous_ACISPKT_cmd - Given one line out of 
    #                                            system_packets, record the values
    #                                            in self.previous_ACISPKT_cmd
    #
    #---------------------------------------------------------------------------
    def write_bogus_previous_ACISPKT_cmd(self, system_packet_line):
        """
        You want to create a bogus previous ACISPKT for the time when 
        you are processing the first acis packet that you saw in the backstop file.
        This will allow the system state to be updated with the info from the first
        packet without any violation rules firing.
        """
        # First init the prev packet command with the date and time of the first packet info.....
        self.previous_ACISPKT_cmd['event_date'] = system_packet_line['event_date']
        self.previous_ACISPKT_cmd['event_time'] = system_packet_line['event_time']

        # ...BUT you want to set both the cmd_type and the packet_or_cmd to None
        self.previous_ACISPKT_cmd['cmd_type'] = None
        self.previous_ACISPKT_cmd['packet_or_cmd'] = None



    #---------------------------------------------------------------------------
    #
    # insert_errors - Given a list of errors, insert a time stamped line
    #                 for each error at the earliest possible
    #                 point in the ACIS-LoadReview.txt file.
    #
    #      Inputs: lr_file Name of the resultant output file
    #        
    #              list of errors to be inserted. 
    #
    #              Each error is a string of the form:
    #
    #                DOY-form time stamp <string>
    #                e.g.
    #               '2018:064:20:11:59.529 Should be a WSPOW0 here'
    #---------------------------------------------------------------------------
    def insert_errors( self, lr_file, violations_list):
        """
        insert_errors - Given the ACIS_LoadReview.txt file created by LR, and
                        a list of errors, insert a time stamped line, in a new
                        ACIS-LoadReview.txt file, for each error in between 
                        the two lines between which the error was found.
    
          Inputs: lr_file Name of the input ACIS-LoadReview.txt file (ALR.txt)
                  list of errors to be inserted
                     - list of dicts
                     - time ordered

                     - example: {'vio_date': '2018:065:21:40:36.53',
                                 'vio_time': 636759705,
                                  'vio_rule': 'Rule 3 - Less than 4 second delay'}
    
                  Each error is a string of the form:
    
                    DOY-form time stamp <string>
                    e.g.
                   '2018:064:20:11:59.529 Should be a WSPOW0 here'

        """
        # Open the load review text file
        infile = open(lr_file, 'r')
                
        # Read all of the ALR.txt lines
        ALR_lines = infile.readlines()
                
        # Done with the input file - close it.
        infile.close()
          
        #
        # Now find the indices of all those lines which have a time stamp at
        # the start
        #
        # Define regular expressions to be used in backstop file line searches
        time_stamp = re.compile('\d\d\d\d:\d\d\d:\d\d:\d\d:\d\d.\d\d\d')
        
        # Get the indices of all those lines which begin with a DOY time stamp
        # This is the position of the stamped line in the ALR file.
        time_stamped_line_indices = [index for index,eachline in enumerate(ALR_lines) if time_stamp.match(eachline)]
        
        # Next, get a list of the times in seconds for those lines which have a 
        # DOY time in them.  This is a one for one pairing of time_stamped_line_indices
        event_times = [DateTime(ALR_lines[eachindex].split()[0]).secs  for eachindex in time_stamped_line_indices]
        
        # Look at the start of the time stamped indices list
        previous_stamp = 0
        
        # Now for each violation in the violations list, find the two indices
        # between wich the violation must fall
        for each_violation in violations_list:
            # Find all the times in the event_times list that are LESS THAN OR
            # EQUAL TO the violation time in question
            leq_times = [index for index,etime in enumerate(event_times) if int(etime) <= each_violation['vio_time']]
            # Now the last value in the leq_times list is the index into
            # time_stamped_line_indices where you will obtain the location
            # in the ALR list of where you want to indert the violation text
            insert_loc = time_stamped_line_indices[leq_times[-1]]
        
            # At long last you now know where to insert the violation text
            # It's AFTER insert_loc
            ALR_lines.insert(insert_loc, '\n')
            ALR_lines.insert(insert_loc, 'ACISPKT AND/OR POWER COMMAND ERROR:\n')
            ALR_lines.insert(insert_loc+1, each_violation['vio_date']+' '+each_violation['vio_rule']+'\n')
#            ALR_lines.insert(insert_loc+2, '\n')

            # Since you've added lines, you have to re-calculate the indices of all those 
            # lines which begin with a DOY time stamp again.
            # This is the position of the stamped line in the ALR file.
            time_stamped_line_indices = [index for index,eachline in enumerate(ALR_lines) if time_stamp.match(eachline)]

        # So now you've updated the list of ALR lines to include any errors that exist.
        # Write the list out to a new file
        outfile = open(lr_file+'.ERRORS', 'w')
        outfile.writelines(ALR_lines)
        outfile.close()
