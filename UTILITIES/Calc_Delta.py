###############################################################################
#
# Calc_Delta_Time - Calculate a delta between two times
#                
###############################################################################

import apt_date_secs as apt

def Calc_Delta_Time(start, stop):
    """
    Calculate the time between stop and start (stop - start)
    
     Inputs:  start - Start time either in Chandra Seconds (int or float) or  DOY
              stop - Stop time either in Chandra Seconds (int or float) or  DOY
    
    Outputs: The delta time (float) between start and stop in seconds, minutes and hours
    
    Identifies they type of the inputs and converts them to Chandra seconds if necessary.
    Then calculates the delta time in seconds (stop - start). divides by 60.0 for minutes 
    and 3600.0 to get hours
    
    
    """
    # Obtain float values if the inputs are either string or integer
    #
    #Convert start input to Chandra seconds
    if isinstance(start, int):
        start_float = float(start)
    elif isinstance(start, str):
        start_float = apt.secs(start)
    else:
        start_float = start
    
    #Convert stop input to Chandra seconds
    if isinstance(stop, int):
        stop_float = float(stop)
    elif isinstance(stop, str):
        stop_float = apt.secs(stop)
    else:
        stop_float = stop
    
    # Calculate the delta t between start and stop
    delta_secs = stop_float - start_float
    delta_minutes = delta_secs/60.0
    delta_hours = delta_secs/3600.0
    
    # Return results in seconds, minutes and hours
    return ( delta_secs, delta_minutes, delta_hours)
 


















