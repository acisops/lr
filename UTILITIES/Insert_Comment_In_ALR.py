import os
import re
import shutil

import apt_date_secs as apt

def Insert_Comment_In_ALR( comment_list, ALR_path, extension = "COMMENTS"):
    
    """
    Given a list of comments to be inserted into an ACIS-LoadReview.txt file,
    Open a new file with .extension added to the name. Insert each comment
    into the ACIS-LoadReview.txt file whose path is given in the second argument
    to the subroutine.
    
    input: comment_list
                - A list of comment lists. The structure of the comment list is:
                   [insert_date, insert_time, comment string]
    
                  If the list is empty, the subroutine exits.
                  For each item in the list, the start time is read, and the comment string
                  is inserted into the ACIS-LoadReview.txt file just before the first dated
                  line, in the file, whose date is greater than the insert date.
    
             ALR_path 
                 - Directory where the ACIS-LoadReview.txt file, to be modified, will be found
    
             extension - Extension to be added to the file name ACIS-LoadReview.txt.
    
    output: updated_ALR_file 
                 - An updated file located in ALR_path with the inserted comments
    
    """
    # Path to the ACIS-LoadReview.txt file to be modified.
    ALR_file_path = os.path.join(ALR_path, "ACIS-LoadReview.txt")
    
    # Open the load review text file
    infile = open(ALR_file_path, 'r')
    
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
    # This is the position of the time stamped line in the ALR file.
    # Not all lines in the file begin with time stamps
    time_stamped_line_indices = [index for index, eachline in enumerate(ALR_lines) if time_stamp.match(eachline)]
    
    # Next, get a list of the times in seconds for those lines which have a
    # DOY time in them.  This is a one for one pairing of time_stamped_line_indices
    event_times = [apt.secs(ALR_lines[eachindex].split()[0])  for eachindex in time_stamped_line_indices]
    
    # Now for each comment in the comments list, find the two indices
    # between which the comment must fall based on time stamp
    for each_comment in comment_list:
        # Find the indices of all the times in the event_times list that are LEQ  the
        # comment time in question
        leq_times = [index for index, etime in enumerate(event_times) if etime <= each_comment[1]]
        
        # Now the last value in the leq_times list is the index into
        # time_stamped_line_indices where you will obtain the location
        # in the ALR list of where you want to insert the comment text
        insert_loc = time_stamped_line_indices[leq_times[-1]] +1
        
        # At long last you now know where to insert the comment text
        # It's before insert_loc
        # Write the date (DOY) and the comment statement
        ALR_lines.insert(insert_loc, "".join(("\n",  each_comment[2], "\n\n")) )

        # Since you've added lines, you have to re-calculate the indices of all those
        # lines which begin with a DOY time stamp again.
        # This is the position of the stamped line in the ALR file.
        time_stamped_line_indices = [index for index, eachline in enumerate(ALR_lines) if time_stamp.match(eachline)]
    
    # So now you've updated the list of ALR lines to include any errors or
    # comments that exist.
    # Write the list out to a new file
    outfile = open(ALR_file_path+"."+extension, 'w')
    outfile.writelines(ALR_lines)
    outfile.close()
    
