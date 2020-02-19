################################################################################
#
# SI_Mode_Class - Methods and attributes to read in ratcfg output for
#                 an SI mode and store it in a useful data structure
#
################################################################################
class SI_Mode_Info:

    def __init__(self,):
        self.SI_mode = None
        self.si_mode_dat_dir = None
        self.loadblock_types = ['loadTeBlock', 'loadCcBlock']
        self.chips = [ 'I0', 'I1', 'I2', 'I3', 'S0', 'S1', 'S2', 'S3', 'S4', 'S5']
        self.mode_type = None
        self.in_lines = None
        self.single_lines = None

        self.exposure_mode = None
        self.block_root = None
        self.parameter_block = None
        self.parameter_block_list = None
        self.fepCcdSelect = None
        self.recomputeBias = None
        self.trickleBias = None
        self.windowSlotIndex = None

        self.loadblocks_1d_keys = []
        self.loadblocks_2d_keys = []

        self.window_blocks_list_1d = []
        self.window_blocks_list_2d = []

        self.ccdID_list = []
        self.window_block_list = []

        # This is where RunRat will store the Si mode ascii packets
        # after it has run ratcfg/lcmd
        self.rat_dest = None


    #-------------------------------------------------------------------------------
    #
    #        Window block wipeout test
    #
    #-------------------------------------------------------------------------------    
    def Wipeout_check(self, block, dimension):
        """
        Given a window block for a chip and its dimension (1d or 2d), test to see if that
        block is a total wipeout of any event that hits the chip.

        The two different block types have different dictionary keys to be tested

        Write any error into an error list and return the list

        inputs: block - dict which contains information from either a 1d or 2d
                        window block

            dimension - integer - 1 or 2. If nto a 1 it will be considered a 2

        output: error_list - list containing any error messages, or an empty list

        """
        error_list = []

        # If this is a 1D block....
        if dimension == 1:
            if (int(block['ccdColumn'][0]) == 0) and \
               (int(block['width'][0]) == 1023) and \
               (int(block['sampleCycle'][0]) == 0):
                error_list.append('>>>ERROR: SI Mode: '+self.si_mode_dict['SI_MODE']+ ' ccdId: '+block['ccdId'][0]+' This window eliminates ALL events')
        else:  # Else this must be a 2D block
            if (int(block['ccdRow'][0]) == 0) and \
               (int(block['ccdColumn'][0]) == 0) and \
               (int(block['width'][0]) == 1023) and \
               (int(block['height'][0]) == 1023) and \
               (int(block['sampleCycle'][0]) == 0):
                error_list.append('>>>ERROR: SI Mode: '+self.si_mode_dict['SI_MODE']+ ' ccdId: '+block['ccdId'][0]+' This  window eliminates ALL events')
               

        # Return the error list
        return error_list

    #-------------------------------------------------------------------------------
    #
    #        Window block partial wipeout test
    #
    #-------------------------------------------------------------------------------    
    def Partial_wipeout_check(self, block, dimension):
        """
        Given a window block for a chip and its dimension (1d or 2d), test to see if
        part of that block is windowed out.

        The two different block types have different dictionary keys to be tested

        Write any error into an error list and return the list

        inputs: block - dict which contains information from either a 1d or 2d
                        window block

            dimension - integer - 1 or 2. If not a 1 it will be considered a 2

        output: error_list - list containing any error messges, or an empty list

        """
        warning_list = []

        # If this is a 1D block....
        if dimension == 1:
            # If the row, column and width values cover PART of the chip, and
            # the sampleCycle is one (x,x,x,1) , set a warning.
            if (((int(block['ccdColumn'][0]) != 0) or \
                 (int(block['width'][0]) != 1023)) and \
                 (int(block['sampleCycle'][0]) == 1)):
                 warning_list.append('>>>WARNING: SI Mode: '+self.si_mode_dict['SI_MODE']+ ' Check OBSCAT')
                 
        else: # Assume it's a 2D block
            # If the row, column and width values cover PART of the chip, and
            # the sampleCycle is one (x,x,x,1) , set a warning.
            if (((int(block['ccdRow'][0]) != 0) or \
                (int(block['ccdColumn'][0]) != 0) or \
                (int(block['width'][0]) != 1023) or \
                (int(block['height'][0]) != 1023)) and \
                (int(block['sampleCycle'][0]) == 1)):
                 warning_list.append('>>>WARNING:   SI Mode: '+self.si_mode_dict['SI_MODE']+ ' ccdId: '+block['ccdId'][0]+' Partially blanked but sampleCycle = 1. Check OBSCAT')
        # Return the error list
        return warning_list

    #---------------------------------------------------------------------------
    #
    #   make_si_mode_dict
    #
    #---------------------------------------------------------------------------
    def make_si_mode_dict(self, si_mode, mode_lines):
        # Calculate the number of lines in the list of strings
        num_mode_lines = len(mode_lines)
      
        # You start by creating the top level of the dictionary using the SI mode name
        # Initialize the output dictionary
        self.si_mode_dict = {'SI_MODE': si_mode}
        
        # Start with the first line in mode_lines
        line_num = 0
    
        # Process the lines until you've handled all lines
        while line_num < num_mode_lines:
    
            # You are sitting on the LHSIDE = { line
            if '{' in mode_lines[line_num]: 
                # You found the start of a block....process that block
                line_num, new_key, block_dict = si_mode_info.Create_Block_Dict(mode_lines, line_num)
    
                # Update the dictionary with what was returned from Process_Blocks
                self.si_mode_dict.update({new_key: block_dict})
        
                # You need to increment the line number because Process Block
                # doesn't move you ahead once it's finished. So look at
                # the next available line
    
                line_num += 1
    

    #---------------------------------------------------------------------------
    #
    #   Extract_info - Run the SI mode dictionary thrugh this method in order
    #                  extract pertinent info
    #
    #---------------------------------------------------------------------------
    def Extract_info(self,):


        # Clear out some attributes
        self.loadblocks_1d_keys = []
        self.loadblocks_2d_keys = []

        self.window_blocks_list_1d = []
        self.window_blocks_list_2d = []

        self.ccdID_list = []
        self.window_block_list = []

        self.exposure_mode = self.si_mode_dict['SI_MODE'][:2].upper()

        # Initialize the window flag to false - no windows used
        window_flag = False
    
        # Collect all parameter blocks in this SI mode
        # What is the root of the block type you are trying to collect?
        if self.exposure_mode == 'TE':
            self.block_root = 'loadTeBlock'
        elif  self.exposure_mode == 'CC':
            self.block_root = 'loadCcBlock'
        elif self.exposure_mode == 'TN':
            self.block_root = 'loadTeBlock'
        else:
            self.block_root = None

        # Collect all blocks of type load<TE/CC>Block. Realistically there
        # will be only 1 paramter block per SI mode.....
        self.parameter_block_list = si_mode_info.collect_blocks(self.si_mode_dict, self.block_root)
    
        # ....so alert the user if there is more than one
        if len(self.parameter_block_list) > 1:
            print('\nWARNING: This SI mode has more than one Parameter Block.')
            print(' and that is REALLY STRANGE.')
            one_BP = False
    
            # And if NO parameter block are returned that's pretty odd too
        elif len(self.parameter_block_list) == 0:
            print('WARNING!!!!! No parameter blocks of type" '+self.block_root+' in this SI mode')
            one_PB = False
        # Else you have one and only one parameter block so carry on
        else:
            one_PB = True

        # So if you have but one PB extract some useful info from it
        if one_PB == True:
    
            # Values in the dict are lists of strings so convert as appropriate
            self.parameter_block = self.parameter_block_list[0]
        
            # Get the FEP count and assignments; convert to integers
            self.fepCcdSelect = [int(i) for i in self.parameter_block['fepCcdSelect']]
        
            # Get recompute boas and trickle bias values; convert to ints
            self.recomputeBias = int(self.parameter_block['recomputeBias'][0])
            self.trickleBias = int(self.parameter_block['trickleBias'][0])
        
            # Now fetch the all-important windowSlotIndex; convert to int
            # windowSlotIndex appears in the Parameter Block. 
            self.windowSlotIndex = int(self.parameter_block['windowSlotIndex'][0])
            
            # If you have window blocks extract the info from them
            if self.windowSlotIndex == 4:
                # Capture any 1 and 2d load block keys
                self.loadblocks_1d_keys = self.collect_keys(self.si_mode_dict, 'load1dBlock')
                self.loadblocks_2d_keys = self.collect_keys(self.si_mode_dict, 'load2dBlock')

    #-------------------------------------------------------------------------------
    #
    #        Test_1d_window_blocks
    #
    #-------------------------------------------------------------------------------    
    def Test_1d_window_blocks(self):
        """

        Assumes Extract_info has been run and all pertinent information about the
        SI mode has been collected and stored in attributes of this class.

        If there are one or more load1dBlocks, process and check the 
        windows in each of those blocks.

       A 1D window block looks like this:
    
          windows[0] = { ccdId                    = 5
                         ccdColumn                = 0
                         width                    = 1023
                         sampleCycle              = 0
                         lowerEventAmplitude      = 1645
                         eventAmplitudeRange      = 1305
                        }
    

        Window checks determine if there is a window arrangement that precludes ANY
        events from getting through. 

        Examples:

            If there is only one window for a chip, and if that window has a
            sampleCycle of zero, and includes the full chip, that's an 
            error which is flagged.

            If a chip has multiple windows and any window except the last one 
            has a sampleCycle of zero, and includes the full chip, that's an 
            error which is flagged.

        Check any windows in the SI mode for the following faults:
 
          1) If the first window block has a sample cycle of 0 and covers the 
             entire CCD, an ERROR should be produced. 
 
          2) If the the first window has a sample cycle of one and covers part of
             the CCD, a warning should be produced that no events will be accepted from 
             this region of the CCD and the load reviewer should check the OBSCAT 
             and perhaps check with USINT if this is what is desired.

          3) If there are more than 2 blocks, and more than one are from the same chip,
             only the last block of that chip group can be a sampleCycle 0, full 
             chip block.

        Plots are made which show any portions of the chip which will not pass
        events.
        """
        # Initialize an empty error and warning list
        ccd_error = []
        ccd_error_list = []

        ccd_warning = []
        ccd_warning_list = []

        # If there are any load1dblocks, check any window sets within the block for
        # errors
        if self.loadblocks_1d_keys:

            # For any existing 1d window blocks, get all the window blocks
            for eachkey in self.loadblocks_1d_keys:
                # Find all the window keys
                window_keys = self.collect_keys(self.si_mode_dict[eachkey], 'windows')
                self.window_blocks_list_1d = [self.si_mode_dict[eachkey][eachwindowkey] for eachwindowkey in window_keys]

            # If you have any windows in the window blocks list, capture the CCD ID's
            self.ccdID_list = [eachwindow['ccdId'][0] for eachwindow in self.window_blocks_list_1d]

        # initialize the list of chips that have been processed
        processed_chips = []
        
        ccd_window_list = []
        
        for eachccd in self.ccdID_list:
        
            # Zero out the list of windows collected for this chip
            ccd_window_list = []
        
            # If you have not processed this ccd already.....
            if eachccd not in processed_chips:
                # Get the indices of all chip id values that are the same as the first
                # one in the list
                indices = list(np.where(np.array(self.ccdID_list)== eachccd))
                # Add this to the processed chip list so that you don't
                # process this chip again if there are more windows downstream 
                # for this chip
                processed_chips.append(eachccd)
        
                # Now append the associated window blocks to the ccd window list
                for eachindex in indices:
                    # Append the index of the window to the list
                    ccd_window_list.append(self.window_blocks_list_1d[int(eachindex)])
                
                # Ok so now you have your list of all windows for 1 ccd to check
                # Check to see if there is only one window in the window list.
                # If so, then just check to be sure it isn't a wipeout
                if len(ccd_window_list) == 1:
                    # pull the dictionary block out of the list
                    check_window = ccd_window_list[0]
                    # Now test for full wipeout
                    ccd_error = si_mode_info.Wipeout_check(check_window, 1)
                    # If there is an error - append it to the list for this si_mode
                    if ccd_error:
                        ccd_error_list.append(ccd_error)
               
                    # If no errors check for partial blanking 
                    if ccd_error == []:
                        ccd_warning = si_mode_info.Partial_wipeout_check(check_window, 1)
                        # if there is a warning append it to the warning list
                        if ccd_warning:
                            ccd_warning_list.append(ccd_warning)

                else:  # If there is more than one window for this chip
                    # Check all but the last window
                    for eachwindow in ccd_window_list[:-1]:
                        ccd_error = si_mode_info.Wipeout_check(eachwindow, 1)
                        if ccd_error:
                            ccd_error_list.append(ccd_error)
               
                        # If no errors check for partial blanking 
                        if ccd_error == []:
                            ccd_warning = si_mode_info.Partial_wipeout_check(eachwindow, 1)
                            if ccd_warning:
                                ccd_warning_list.append(ccd_warning)

        return(ccd_error_list, ccd_warning_list)


    #-------------------------------------------------------------------------------
    #
    #        Test_2d_window_blocks
    #
    #-------------------------------------------------------------------------------    
    def Test_2d_window_blocks(self):
        """

        Assumes Extract_info has been run and all pertinent information about the
        SI mode has been collected and stored in attributes of this class.

        If there are one or more load2dBlocks, process and check the 
        windows in each of those blocks.

       A 2D window block looks like this:
    
          windows[0] = { ccdId                    = 5
                         ccdColumn                = 0
                         width                    = 1023
                         sampleCycle              = 0
                         lowerEventAmplitude      = 1645
                         eventAmplitudeRange      = 1305
                        }
    

        Window checks determine if there is a window arrangement that precludes ANY
        events from getting through. 

        Examples:

            If there is only one window for a chip, and if that window has a
            sampleCycle of zero, and includes the full chip, that's an 
            error which is flagged.

            If a chip has multiple windows and any window except the last one 
            has a sampleCycle of zero, and includes the full chip, that's an 
            error which is flagged.

        Check any windows in the SI mode for the following faults:
 
          1) If the first window block has a sample cycle of 0 and covers the 
             entire CCD, an ERROR should be produced. 
 
          2) If the the first window has a sample cycle of one and covers part of
             the CCD, a warning should be produced that no events will be accepted from 
             this region of the CCD and the load reviewer should check the OBSCAT 
             and perhaps check with USINT if this is what is desired.

          3) If there are more than 2 blocks, and more than one are from the same chip,
             only the last block of that chip group can be a sampleCycle 0, full 
             chip block.

        Plots are made which show any portions of the chip which will not pass
        events.
        """
        # Initialize an empty error and warning list
        ccd_error = []
        ccd_error_list = []

        ccd_warning = []
        ccd_warning_list = []
 

        # If there are any load2dblocks, check any window sets within the block for
        # errors
        if self.loadblocks_2d_keys:
            # For any existing 2d window blocks, get all the window blocks
            for eachkey in self.loadblocks_2d_keys:
                # Find all the window keys
                window_keys = self.collect_keys(self.si_mode_dict[eachkey], 'windows')
                self.window_blocks_list_2d = [self.si_mode_dict[eachkey][eachwindowkey] for eachwindowkey in window_keys]

            # If you have any windows in the window blocks list, capture the CCD ID's
            self.ccdID_list = [eachwindow['ccdId'][0] for eachwindow in self.window_blocks_list_2d]
 
        # initialize the list of chips that have been processed
        processed_chips = []
        
        ccd_window_list = []
        
        for eachccd in self.ccdID_list:
        
            # Zero out the list of windows collected for this chip
            ccd_window_list = []
        
            # If you have not processed this ccd already.....
            if eachccd not in processed_chips:
                # Get the indices of all chip id values that are the same as the first
                # one in the list
                indices = list(np.where(np.array(self.ccdID_list)== eachccd))

                # Add this to the processed chip list so that you don't
                # process this chip again if there are more windows downstream 
                # for this chip
                processed_chips.append(eachccd)
        
                # Now append the associated window blocks to the ccd window list
                for eachindex in indices[0]:
                    # Append the index of the window to the list
                    ccd_window_list.append(self.window_blocks_list_2d[int(eachindex)])
                
                # Ok so now you have your list of all windows for 1 ccd to check
                # Check to see if there is only one window in the window list.
                # If so, then just check to be sure it isn't a wipeout
                if len(ccd_window_list) == 1:
                    # pull the dictionary block out of the list
                    check_window = ccd_window_list[0]
                    # Now test for full wipeout
                    ccd_error = si_mode_info.Wipeout_check(check_window, 2)
                    # If there is an error - append it to the list for this si_mode
                    if ccd_error:
                        ccd_error_list.append(ccd_error)
               
                    # If no errors check for partial blanking 
                    if ccd_error == []:
                        ccd_warning = si_mode_info.Partial_wipeout_check(check_window, 2)
                        # if there is a warning append it to the warning list
                        if ccd_warning:
                            ccd_warning_list.append(ccd_warning)

                else:  # If there is more than one window for this chip
                    # Check all but the last window
                    for eachwindow in ccd_window_list[:-1]:
                        ccd_error = si_mode_info.Wipeout_check(eachwindow, 2)
                        if ccd_error:
                            ccd_error_list.append(ccd_error)
               
                        # If no errors check for partial blanking 
                        if ccd_error == []:
                            ccd_warning = si_mode_info.Partial_wipeout_check(eachwindow, 2)
                            if ccd_warning:
                                ccd_warning_list.append(ccd_warning)

        return(ccd_error_list, ccd_warning_list)




    #-------------------------------------------------------------------------------
    #
    #        Window
    #
    #-------------------------------------------------------------------------------    
    def Get_Window_List(self, block, dimension):
        """
        Obtain the collection of windows which can then be checked
        Given a list of load1dBlocks, process and check the 
        windows in each of those blocks.

       A 1D window block looks like this:
    
          windows[0] = { ccdId                    = 5
                         ccdColumn                = 0
                         width                    = 1023
                         sampleCycle              = 0
                         lowerEventAmplitude      = 1645
                         eventAmplitudeRange      = 1305
                        }
    

        Window checks determine if there is a window arrangement that precludes ANY
        events from getting through. 
        """
        


    #---------------------------------------------------------------------------
    #
    #   RunRat - run ratcfg to get the ascii text for an SI mode
    #
    #---------------------------------------------------------------------------
    def RunRat(self, si_mode, dest_path = '/home/gregg/SI_MODES/MODES-DAT/'):
        # build the fixed part of the ratcfg command which never changes
        cmd_start = '/data/acis/sacgs/bin/ratcfg -d /data/acis/sacgs/odb/current.dat -c /data/acis/sacgs/odb/current.cfg  '

        # Build the destination
        self.rat_dest = dest_path + si_mode + '.dat'

        # build the ratcfg/lcmd command and pipe the output to "si_mode".dat
        rat_cmd = cmd_start + si_mode + ' | /data/acis/sacgs/bin/lcmd -r -v > ' + self.rat_dest

        # Execute the rtcfg/lcmd commands.
        # This is a BLOCKING call - you do not want to proceed until the
        # file is fully written
        rat_stat = subprocess.call(rat_cmd, shell = True)

        
    #---------------------------------------------------------------------------
    #
    #    ReadSIcfg - given the name of the SI mode, open the .dat file
    #                read it and do some light processing
    #
    #---------------------------------------------------------------------------
    def ReadSIcfg(self, si_mode_dat_dir, si_mode):
        ''''
        This method reads in the ratcfg output when it was run on an SI mode
        
            inputs: si_mode - name of the SI mode (e.g. 'TE_00B26B')
                    si_mode_dat_dir - Directory containing the <si_mode>.dat file
                        - e.g. /data/acis/LoadReviews/2019/FEB1819.ofls/SI_MODES
        
            output: List of strings - each string a line in the file. 
        
        It does, some, but very little processing on the strings that are read in:
        
            1) Remove '\n' from the end of the lines
        
            2) Remove any comments
           
            3) If it sees lines like this:
        
        gradeSelections = 0xffffffff 0xffffffff 0xffffffff 0xffffffff 
                          0xffffffff 0xffffffff 0xffffffff 0x7fffffff 
        
               it will turn it into a single line:
        
        gradeSelections = 0xffffffff 0xffffffff 0xffffffff 0xffffffff 0xffffffff 0xffffffff 0xffffffff 0x7fffffff 
        
        That's it. Otherwise you have a list of strings where each item is one
        line from the file.
    
        Created March 9, 2019
    
        '''
        # Inits
        sacgs_dir = '/data/acis/cmdgen/sacgs'
        script_dir = '/data/acis/LoadReviews/scripts'

        # Capture the directory where the ratcfg/lcmd output resides
        self.si_mode_dat_dir = si_mode_dat_dir

        # Figure out if this is a CC or TE mode si mode
        self.mode_type = si_mode[:2].upper()
        
        # Create the file spec given the SI mode 
        filespec = os.path.join(self.si_mode_dat_dir, si_mode+'.dat')

        # Open the file, returned by ratcfg, for reading
        mode_file = open(filespec, 'r')
        
        self.in_lines = mode_file.readlines()
        
        # Done with the file - close it
        mode_file.close()
        
        # Ok now the only processing on these lines is to combine 
        # multiple lines of values which are associated with one keyword
        # so as to make one line
        
        # Indexer into the list
        line_num = 0
        
        # Number of lines of strings in the list
        num_lines = len(self.in_lines)
        
         # Processing Step 1 - Remove the '\n's from the lines
        lines_no_CR = [eachline[:-1] for eachline in self.in_lines]
         
        # Processing Step 2 - Remove any comment portions in the strings
        lines_no_comments = [eachline if '#' not in eachline else eachline[:eachline.index('#')] for eachline in lines_no_CR]
        no_comments_num_lines = len(lines_no_comments)
        
        # Processing Step 3 - replace entries with multiple lines with one line
        self.single_lines = []
        
        # Starting with the first line......
        line_index = 0
        
        # ...process the lines doing any combination where necessary
        while line_index < no_comments_num_lines:
            # If the line has either an '{', '}', or '=' hold it
            if ('{' in lines_no_comments[line_index]) or \
               ('}' in lines_no_comments[line_index]) or \
               ('=' in lines_no_comments[line_index]):
                # Then it's not a "secondary" line for one left hand side
                # So hold it.....
                hold_line = lines_no_comments[line_index]
                # look at the next line.....IF there is another line
                line_index += 1
                if line_index < no_comments_num_lines:
                    # ....and if there are no {, } or ='s in the line it's
                    # part of the hold_line right hand side (RHside)
                    while  ('{' not in lines_no_comments[line_index]) and \
                           ('}' not in lines_no_comments[line_index]) and \
                           ('=' not in lines_no_comments[line_index]):
                        # It's an extension of the line so concatenate it.
                        hold_line = hold_line+lines_no_comments[line_index]
                        # Eliminate multiple spaces - but add two at the beginning
                        # (i.e. the lh side) for conformity to the original file
                        # This is for human readbility only in case you want to
                        # view the output from this method.
                        hold_line = '  '+' '.join(hold_line.split())
                        line_index += 1
            
                # Coming out of the while you have a complete line so append
                # it to single_lines
                self.single_lines.append(hold_line)
        
                # line_index is now pointing to the next line to be processed
                # (or is past the end of the list)
        
        # Ok you are done processing the input file.
        # return it
        return self.single_lines


    #-------------------------------------------------------------------------------
    #
    #   Create_block_dict
    #
    #-------------------------------------------------------------------------------
    
    def Create_Block_Dict(self, mode_lines, line_num):
        """
            Given the previously read-in and processed output of ratcfg, process
            each "block" to  create a multi-level Ordered Dictionary so that
            subsequent users have a convenient way to use the data.
        
            A single level block looks like this:
        
             stopScience[0] = {
               commandLength              = 3
               commandIdentifier          = 1539
               commandOpcode              = 19 
             }
        
            A two level block looks like this:
        
             changeConfigSetting[1] = {
               commandLength              = 7
               commandIdentifier          = 6855
               commandOpcode              = 32 
               entries[0] = {
                 itemId                   = 0 
                 itemValue                = 480
               }
               entries[1] = {
                 itemId                   = 1 
                 itemValue                = 30
               }
             }
        
            This will result in a 2 level dictionary looking something like this:
        
             {'changeConfigSetting[1]': {'commandLength': ['7']}
                                        {'commandIdentifier': ['6855']}
                                        {'commandOpcode': ['32']}
                                        {'entries[0]': {'itemId': ['0'] }
                                                       {'itemValue': ['480']} }
                                        {'entries[1]': {'itemId': ['1'] }
                                                       {'itemValue': ['30']} } }
        
            NOTE: The data values on the right hand side of an input line are NOT
                  processed. They are merely a list of strings. So if you see an
                  input line that looks like this:
        
                    commandLength              = 7
        
                       or this:
        
                    fepCcdSelect               =   10    7    5    6    8   10 
        
                  The resultant dict entry will look like this:
        
                  {'commandLength': ['7']}
        
                       or this:
        
                  {'fepCcdSelect': ['10', '7',  '5', '6', '8', '10']}
        
                  It is up to the user to know how to interpret and use the data values.
        
                  Note that some of the values are hex:
        
                          parameterBlockId           = 0x00170014
        
                  So the output dict entry will look like this:
        
                         {'parameterBlockId':  ['0x00170014']}
        
                 input: List of strings - each string a line in the file created ny ratcfg
                        output
        
                output: Multi-level dictionary containing the lhside of the input as keywords
                         and the right hand side becomes a list of strings
        
            Created March 9, 2019
        """
     
        # Inits
        block_found = False
        
        # You entered here because the line you are on signifies the beginning of a block.
        #   e.g.:  stopScience[1] = {
        # line_num is pointing to that line so begin your processing there
        #
        # Split the line on spaces
        split_line = mode_lines[line_num].split()
        
        # Use the lhside value for the block keyword
        command = split_line[0]
    
        # Create an empty block dictionary
        block_d = {}
    
        # ...and if there IS a next line
        while (line_num < len(mode_lines)) and (block_found == False):
            # Now look at the next line AFTER the "LHSIDE = {" line
            line_num +=1
    
            # Continue with the block processing
            # if there is an equal sign but no '{', then it's
            # a line of the form lhside = value so make a dict
            # out of that an dappend it to the block_d
            if ('=' in mode_lines[line_num]) and \
               ('{' not in mode_lines[line_num]):
                # Split the line on spaces
                split_line = mode_lines[line_num].split()
                # The key for the new dict entry is on the left of the = sign
                new_key = split_line[0]
                # The value for the new dict entry is the entirety of the string
                # to the right of the = sign
                rhside = mode_lines[line_num][mode_lines[line_num].index('=')+1:].split()
                # Form the dict entry and update the block_d
                block_d.update({new_key: rhside})
    
            elif '{' in mode_lines[line_num]:
    
    
                # You've found a new sub_block to the block you are processing
                # Recurse into Process_blocks
                line_num, sub_command, sub_block_d = self.Create_Block_Dict(mode_lines, line_num)
                # When you finally return, add the new block
                block_d.update({sub_command: sub_block_d})
    
            elif '}' in  mode_lines[line_num]:
                # You found the end of the block, so increment the line index and
                # return that plus the block dict you just formed
                
                block_found = True
    
        # Return the line number, the command, and the dict
        return(line_num,  command, block_d)
        
        
    #-------------------------------------------------------------------------------
    #
    #  collect_blocks - collect whatever list of blocks that exist by type
    #
    #-------------------------------------------------------------------------------
    def collect_blocks(self, input_dict, block_root):
        """
        Given the root of a block that exists in the SI mode Dictionary, return all
        the blocks with that root starting at the level of dictionary specified by
        si_mode_dict.
        
        For example, to collect all window blocks that exist in a load1dBlock[0] 
        block the input argument input_dict should be:
        
                entire_si_mode_dictionary['load1dBlock[0]']
        
        and block_root should be:
        
                'windows'
        
        If you want all stop science block then send in the entire SI mode
        dictionary and block_root should be 'stopScience'
        
        
        """
        # Get all of the keys
        top_keys = input_dict.keys()
        
        # Now search the key list to find all those which begin with block_root
        root_key_list = [eachkey for eachkey in top_keys if block_root in eachkey]
        
        # Now get all the blocks that have those keys
        block_list = [input_dict[eachkey]  for eachkey in root_key_list]
    
        # Return the list of blocks
        return block_list

    #-------------------------------------------------------------------------------
    #
    #  collect_keys - collect whatever list of keys that exist by type
    #
    #-------------------------------------------------------------------------------
    def collect_keys(self, input_dict, key_root):
        """
        Given the root of a key that exists in the SI mode Dictionary, return all
        the keys with that root starting at the level of dictionary specified by
        si_mode_dict.
        
        For example, to collect all window keys that exist in a load1dBlock[0] 
        key the input argument input_dict should be:
        
                entire_si_mode_dictionary['load1dBlock[0]']
        
        and key_root should be:
        
                'windows'
        
        If you want all stop science key then send in the entire SI mode
        dictionary and key_root should be 'stopScience'
        
        
        """
        # Get all of the keys
        top_keys = input_dict.keys()
        
        # Now search the key list to find all those which begin with key_root
        root_key_list = [eachkey for eachkey in top_keys if key_root in eachkey]

        # Return the list of keys
        return root_key_list
