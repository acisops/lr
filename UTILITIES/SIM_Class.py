################################################################################
#
# SIM_Class - Class that provides utilities for SIM
#
###############################################################################

"""

Class that provides some utilites for the SIM.

For example, given a SIM step position, one method returns the name of the
instrument in the focal plane  (e.g. "ACIS-I") as a string

"""
class SIM_utilities():
    def __init__(self, ):
        self.instrument = "UNKNOWN"

    #---------------------------------------------------------------------------
    #
    #  Method - Get_Instrument
    #
    #---------------------------------------------------------------------------
    def Get_Instrument(self, step):
        """
        Given a step value (e.g. -99166 for HRC-S), return the instrument
        which would be in the focal plane if the SIM was at that step position.

        """
        # Select the instrument depending upon the step value
        if (step >= 82109) and (step <= 104839):
            self.instrument = "ACIS-I"
        elif (step >= 70376.0) and (step < 83712.0):
            self.instrument = "ACIS-S"
        elif (step >= -86147.0) and (step < -20000.0):
            self.instrument = "HRC-I"
        elif (step >= -104362.0) and (step < -86148.0):
            self.instrument = "HRC-S"
        else:
            self.instrument = "UNKNOWN"
            
        return self.instrument
            
            

        
