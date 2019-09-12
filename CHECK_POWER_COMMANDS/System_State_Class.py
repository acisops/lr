################################################################################
#
#  System_State_Class - class defined to manage the state of the system.
#                       This will include whether or not the present point
#                       in the backstop file is within a perigee passage;
#                       whether or not a science run is underway - or 
#                       complete, and whether or not we have somce upon a
#                       power command was once the science run is complete.
#
#
#  Update: June 26, 2019
#          VERSION: 1.3
#          Gregg Germain
#          Fix the Rule #9 error in the DEC2418 load.
#             - The error is due to the fact that you really have to first
#               alter the state of the system when you process a command
#               before you check for timing errors.
#                  Files changed: Check_Power_Cmds.py
#                                 Rulesets.py
#                                 System_State_Class.py
#################################################################################

class System_State_Object:
    """
    Class defined to manage the state of the system.
    This will include whether or not the present point
    in the backstop file is within a perigee passage;
    whether or not a science run is underway - or 
    complete, and whether or not we have come upon a
    power command  once the science run is complete.

    The only method is print_system_state which is used for debugging.
    """
    def __init__(self, ):

        # System state dictionary
        self.state = {'date_cmd':  '',
                      'time_cmd': 0,
                      # Science Run status
                      'science_run_exec': 'unk',
                      # Start dates
                      'science_run_start_date': 'unk',
                      'science_run_start_time': 'unk',
                      # Stop Times
                      'science_run_stop_date': 'unk',
                      'science_run_stop_time': 'unk',
                      # In a perigee passage? if so what part?
                      'perigee_passage': 'unk',
                      # Have I run a WSPOW command after the first stop science?
                      'post_sci_run_power_down': False,
                      'post_sci_run_power_down_date': 'unk',
                      'post_sci_run_power_down_time': 0,
                      # The WSPOW0002A that should come if WSPOW00000 was
                      # issued an hour ago and no science run is active
                      'three_FEPs_up': False,
                      'three_FEPs_up_date': 'unk',
                      'three_FEPs_up_time': 0,
                      # Some FEPS could be up so make a note of that
                      'some_FEPs_up': False,
                      'some_FEPs_up_date': 'unk',
                      'some_FEPs_up_time': 0,
                       
}

 
    #---------------------------------------------------------------------------
    #
    # Method: Print System State: Print out the present values of the 
    #                             system state parameters
    #
    #---------------------------------------------------------------------------
    def print_system_state(self,):
        print('\n System State values as of now: ')
        print('    date_cmd: ',self.date_cmd)
        print('    time_cmd: ', self.time_cmd)
        print('    science_run_exec: ', self.science_run_exec)
        print('    science_run_stop_time: ', self.science_run_stop_time)
        print('    science_run_stop_date: ', self.science_run_stop_date)
        print('    perigee_passage: ', self.perigee_passage)
        print('    post_sci_run_power_down: ', self.post_sci_run_power_down)

