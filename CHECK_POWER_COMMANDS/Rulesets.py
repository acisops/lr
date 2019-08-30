################################################################################
#
#  Rulesets.py - sets of rules used to check power commands in weekly loads.
#
################################################################################
from Chandra.Time import DateTime

#-------------------------------------------------------------------------------
#
#    ACISPKT State Rule Set - rules to be evaluated when you see an ACISPKT 
#                             command type..first make any adjustements to
#                             the system state as a consequence of the command 
#                             you are processing.
#
#    input:  The command line  
#            The ACISPKT state dictionary
#            The system state
#            The backstop file class instance
#            
#   output:  Updated state dictionary
#            List of rules fired
#
# Update: June 26, 2019
#         VERSION 1.3
#          Gregg Germain
#          Fix the Rule #9 error in the DEC2418 load.
#             - The error is due to the fact that you really have to first
#               alter the state of the system when you process a command
#               before you check for timing errors.
#                  Files changed: Check_Power_Cmds.py
#                                 Rulesets.py
#                                 System_State_Class.py
#
#-------------------------------------------------------------------------------
def ACISPKT_State_rules(cmd_entry, ACISPKT_state, system_state, bfc):
    """
        Rules to be evaluated when you see an ACISPKT 
        command type..first make any adjustements to
        the system state as a consequence of the command 
        you are processing.
    """

    # Init an empty violations list
    violations_list = []

    rules_fired = []
    start_science_packets = ['XTZ0000005', 'XCZ0000005']
    stop_science_packet = 'AA00000000'
    cooling_power_commands = ['WSPOW00000', 'WSPOW0002A']

 # RULE 0 - STOP SCIENCE -And science run status is unknown
    if (cmd_entry['packet_or_cmd'] == stop_science_packet) and \
       (system_state.state['science_run_exec'] == 'unk'):
        # THEN - MAYBE this is one of the two stop sciences at the start of a RTS load
        # Disable the science run
        system_state.state['science_run_exec'] = 'unk'
        system_state.state['science_run_stop_time'] = cmd_entry['event_time']
        system_state.state['science_run_stop_date'] = cmd_entry['event_date']
        # Clear the indicators for the WSPOW00000
        system_state.state['post_sci_run_power_down'] = False
        system_state.state['post_sci_run_power_down_date'] = 'unk'
        system_state.state['post_sci_run_power_down_time'] = 0
        # Clear the indicators for the WSPOW0002A you ought to run if you are
        # down for more than an hour.
        system_state.state['three_FEPs_up'] = False
        system_state.state['three_FEPs_up_date'] = 'unk'
        system_state.state['three_FEPs_up_time'] = 0
        # Clear the indicator that says at least SOME FEPs are up
        system_state.state['some_FEPs_up'] = False
        system_state.state['some_FEPs_up_date'] = 'unk'
        system_state.state['some_FEPs_up_time'] = 0
        # Record that this Rule fired.
        rules_fired.append('STATE Rule 0 - First Stop_science at load start '+system_state.state['science_run_start_date'])

    # RULE 1 - START SCIENCE - Mark the start of a science run
    if (cmd_entry['packet_or_cmd'] in start_science_packets) and \
       (system_state.state['science_run_exec'] != 'Started'):
        # THEN - this is a start of a science run. Record that fact
        system_state.state['science_run_start_date'] = cmd_entry['event_date']
        system_state.state['science_run_start_time'] = cmd_entry['event_time']
        system_state.state['science_run_stop_time'] = 'unk'
        system_state.state['science_run_stop_date'] = 'unk'
        system_state.state['science_run_exec'] = 'Started'
        system_state.state['post_sci_run_power_down'] = False
        system_state.state['post_sci_run_power_down_date'] = 'unk'
        system_state.state['post_sci_run_power_down_time'] = 0
        rules_fired.append('STATE Rule 1 - Start_science '+system_state.state['science_run_start_date'])

    # RULE 2 - STOP SCIENCE - And you KNOW a science run was begun - Mark the end of the science run
    if (cmd_entry['packet_or_cmd'] == stop_science_packet) and \
       (system_state.state['science_run_exec'] == 'Started'):
        # THEN - this is the first stop science after the start science
        # Disable the science run
        system_state.state['science_run_exec'] = 'Stopped'
        system_state.state['science_run_stop_time'] = cmd_entry['event_time']
        system_state.state['science_run_stop_date'] = cmd_entry['event_date']
        # Clear the indicators for the WSPOW00000
        system_state.state['post_sci_run_power_down'] = False
        system_state.state['post_sci_run_power_down_date'] = 'unk'
        system_state.state['post_sci_run_power_down_time'] = 0
        # Clear the indicators for the WSPOW0002A you ought to run if you are
        # down for more than an hour.
        system_state.state['three_FEPs_up'] = False
        system_state.state['three_FEPs_up_date'] = 'unk'
        system_state.state['three_FEPs_up_time'] = 0
        # Clear the indicator that says at least SOME FEPs are up
        system_state.state['some_FEPs_up'] = False
        system_state.state['some_FEPs_up_date'] = 'unk'
        system_state.state['some_FEPs_up_time'] = 0
       # Record that this Rule fired.
        rules_fired.append('STATE Rule 2 - First Stop_science: '+system_state.state['science_run_stop_date'])

    # RULE 3 - Check to see if this is an WSPOW0002A command
    # IF   If You've stopped the science run, and
    #         You've shut all FEPS off, and 
    #        This command is a WSPOW0002A

    if (system_state.state['science_run_exec'] == 'Stopped') and \
       (system_state.state['post_sci_run_power_down'] == True) and \
       (cmd_entry['packet_or_cmd'] == 'WSPOW0002A'):
       # Then you have a WSPOW0002A and you should record the event
        # Record the fact that you actually did power down.
        system_state.state['three_FEPs_up'] = True
        system_state.state['three_FEPs_up_date'] = cmd_entry['event_date']
        system_state.state['three_FEPs_up_time'] = cmd_entry['event_time']

        # Record which rule fired
        rules_fired.append('STATE Rule #3 -WSPOW0002A executed at: '+ cmd_entry['event_date'])


    # RULE 4 - If a WSPOW command is issued, and
    #             it is NOT a WSPOW00000 or WSPOW0002A
    #           Then
    #              set some_FEPs_up To True.
    # 
    if (cmd_entry['packet_or_cmd'][:5] == 'WSPOW') and \
       (cmd_entry['packet_or_cmd'] not in cooling_power_commands):
        # THEN Record the violation
        system_state.state['some_FEPs_up'] = True
        system_state.state['some_FEPs_up_date'] = cmd_entry['event_date']
        system_state.state['some_FEPs_up_time'] = cmd_entry['event_time']
        # Record which rule fired
        rules_fired.append('STATE Rule #4 - A Power command has brought some FEPs up')
    # Return the state and the rules fired list
    return ( system_state, rules_fired, violations_list)


#-------------------------------------------------------------------------------
#
#    ACISPKT Rule Set - rules to be evaluated when you see an ACISPKT 
#                       comand type
#
#    input:  The command line  
#            The ACISPKT state dictionary
#            
#   output:  Updated state dictionary
#            List of rules fired
#
#-------------------------------------------------------------------------------
def ACISPKT_rules(cmd_entry, ACISPKT_state, system_state, bfc):
    """
    You come here if the command you are presently processing is an ACISPKT command.

    You compare the type of command with the previous ACIPKT command and 
    determine if a timing rule has been violated. If so, record the error 
    in violations_list.

    When you are finished processing the command, it will be copied into 
    System_State_Class.previous_ACISPKT. That way you'll be able to calculate the time
    differential between two, consecutive ACISPKT commands.

    However the first ACISPKT command you see cannot have a "previous" 
    ACISPKT command. So Check_Power_Cmds creates a bogus ACISPKT command and sets
    "previous" to that one.
    """
    # Set the Rules fired list to EMPTY
    rules_fired = []
    start_science_packets = ['XTZ0000005', 'XCZ0000005']
    stop_science_packet = 'AA00000000'
    cooling_power_commands = ['WSPOW00000', 'WSPOW0002A']


    # Create the template dictionary that will be used for entries
    # in the error list should errors be found
    violation = { 'vio_date': '',
                  'vio_time': 0,
                  'vio_rule': ''}

    # Init an empty violations list
    violations_list = []

   
    # Ok now it's time to start checking things out. 

    # rule 0 - Do you at least have the 4 second delay between any two
    #          consecutive ACIPKT commands.
    if (cmd_entry['cmd_type'] == 'ACISPKT') and \
       (bfc.previous_ACISPKT_cmd['cmd_type'] == 'ACISPKT') and \
       cmd_entry['event_time'] - bfc.previous_ACISPKT_cmd['event_time'] < 4.0:
        # Less than 4 seconds between consecutive ACISPKTS
        # Append the vioolation
        violation['vio_date'] =  ACISPKT_state['date_cmd']
        violation['vio_time'] =  ACISPKT_state['time_cmd']
        violation['vio_rule'] = 'ACISPKT Rule #0 - ERROR Less than 4 second delay between consecutive ACISPKT commands'
        violations_list.append(violation)
        # Record which rule fired
        rules_fired.append('ACISPKT Rule 0 - 4 second delay: '+str(ACISPKT_state['date_cmd'])+str(cmd_entry['event_time'] - ACISPKT_state['time_cmd']))


    # Rule 1 - FAILED 3 minute Rule First WSPOW00000 (or 02A)after the stop science
    if (system_state.state['science_run_exec'] == 'Stopped') and \
       (system_state.state['post_sci_run_power_down'] == False) and \
       (cmd_entry['packet_or_cmd'] in cooling_power_commands) and \
       ((cmd_entry['event_time'] - system_state.state['science_run_stop_time']) < 180.0):

        # Then this is the first WSPOW0 after the first stop sci
        # and there wasn't a 3 minutes delay
        # Record the fact that you actually did power down.
        system_state.state['post_sci_run_power_down'] = True
        system_state.state['post_sci_run_power_down_date'] = cmd_entry['event_date']
        system_state.state['post_sci_run_power_down_time'] = cmd_entry['event_time']
        # Record the violation
        violation['vio_date'] = ACISPKT_state['date_cmd']
        violation['vio_time'] =  ACISPKT_state['time_cmd']
        violation['vio_rule'] = 'ACISPKT Rule #1 - ERROR LESS THAN 3 min delay between first AA00 and WSPOW'

        violations_list.append(violation) 
        # Record which rule fired
        rules_fired.append('ACISPKT Rule #1 - ERROR LESS THAN 3 min delay between first AA00 and WSPOW')
     
    # Rule 2 - SUCCEED 3 minute Rule First WSPOW00000 (or 02A)after the stop science
    if (system_state.state['science_run_exec'] == 'Stopped') and \
       (system_state.state['post_sci_run_power_down'] == False) and \
       (cmd_entry['packet_or_cmd'] in cooling_power_commands) and \
       ((cmd_entry['event_time'] - system_state.state['science_run_stop_time']) >= 180.0):
        # Record the fact that you actually did power down.
        system_state.state['post_sci_run_power_down'] = True
        system_state.state['post_sci_run_power_down_date'] = cmd_entry['event_date']
        system_state.state['post_sci_run_power_down_time'] = cmd_entry['event_time']
        # Record which rule fired
        rules_fired.append('ACISPKT Rule 2 - Verified 3 min delay between AA00 and WSPOW. PKT or CMD: '+str(cmd_entry['packet_or_cmd'])+' power_down_date is: '+cmd_entry['event_date']+ ' Delta T is: '+ str(cmd_entry['event_time'] - system_state.state['science_run_stop_time'])+ ' seconds. 180 seconds required')
 

    # RULE 3 - Check if there was at least 24 seconds between WSPOW00000 and any other ACIS command
    # 
    if (bfc.previous_ACISPKT_cmd['packet_or_cmd'] == 'WSPOW00000') and \
       ((cmd_entry['event_time'] - bfc.previous_ACISPKT_cmd['event_time']) < 24.0):
        # THEN Record the violation
        violation['vio_date'] =  str(ACISPKT_state['date_cmd'])
        violation['vio_time'] =  ACISPKT_state['time_cmd']
        violation['vio_rule'] = 'ACISPKT Rule #3 - ERROR  Less than 24 seconds between WSPOW0 and next ACISPKT'
        violations_list.append(violation)
        # Record which rule fired
        rules_fired.append('ACISPKT Rule #3 - ERROR Less than 24 seconds between WSPOW0 and next ACISPKT')



    # RULE 4 - WSVIDALLDN rule - has to be at least 18 seconds between WSVIDALLDN and any other ACIS command
    # 
    if (bfc.previous_ACISPKT_cmd['packet_or_cmd'] == 'WSVIDALLDN') and \
       ((cmd_entry['event_time'] - bfc.previous_ACISPKT_cmd['event_time']) < 18.0):
        # THEN Record the violation
        violation['vio_date'] = ACISPKT_state['date_cmd']
        violation['vio_time'] =  ACISPKT_state['time_cmd']
        violation['vio_rule'] = 'ACISPKT Rule #4 -  ERROR 18 sec required between WSVIDALLDN and the next ACIS Command.'
        # Append this violation to the list of all violations this pass
        violations_list.append(violation)
        # Record which rule fired
        rules_fired.append('ACISPKT Rule #4 - ERROR required between WSVIDALLDN and the next ACIS Command.')


    # RULE 5 - If there was at least 63 seconds between WSPOW-type POWER UP commands
    # 
    if (bfc.previous_ACISPKT_cmd['packet_or_cmd'][:5] == 'WSPOW') and \
       (bfc.previous_ACISPKT_cmd['packet_or_cmd'] != 'WSPOW00000') and \
       (cmd_entry['cmd_type'] == 'ACISPKT') and \
       ((cmd_entry['event_time'] - bfc.previous_ACISPKT_cmd['event_time']) < 63.0):
        # THEN Record the violation
        violation['vio_date'] = ACISPKT_state['date_cmd']
        violation['vio_time'] =  ACISPKT_state['time_cmd']
        violation['vio_rule'] = 'ACISPKT Rule #5 - ERROR Less than 63 seconds between WSPOW power-up and next ACIS command'
        violations_list.append(violation)

        # Record which rule fired
        rules_fired.append('ACISPKT Rule #5 - ERROR Less than 63 seconds between WSPOW power-up and next ACIS command')


    # RULE 6 - Check to see if a WSPOW0002A was issued one hour after the WSPOW00000 that was
    #          executed at the end of the inbound CTI run
    # IF   If You've stopped the science run, and
    #         You've shut all FEPS off, and 
    #         You have not issued a WSPOW0002A
    #         More than 1 hour has passed, and
    if (system_state.state['science_run_exec'] == 'Stopped') and \
       (system_state.state['post_sci_run_power_down'] == True) and \
       (system_state.state['three_FEPs_up'] == False) and \
       (system_state.state['some_FEPs_up'] == False) and \
       (cmd_entry['event_time'] - system_state.state['post_sci_run_power_down_time']) > 3600.0:
        # THEN Record the violation
        violation['vio_date'] =  ACISPKT_state['date_cmd']
        violation['vio_time'] =  ACISPKT_state['time_cmd']
        violation['vio_rule'] = 'ACISPKT Rule #6 - ERROR: ALL FEPS still off and it is 1 hour past WSPOW00000 time.'
        violations_list.append(violation)

        # Record which rule fired
        rules_fired.append('ACISPKT Rule #6 - ERROR 3 FEPS off and it is  1 hour past WSPOW00000 time\n Post sci run power down date: '+ DateTime(system_state.state['post_sci_run_power_down_time']).date)

    # Return the state and the rules fired list
    return ( system_state, rules_fired, violations_list)



#-------------------------------------------------------------------------------
#
#   ORB_CMD_SW  Rule Set - rules to be evaluated when you see an ORBPOINT 
#                          or COMMAND_SW comand type
#
#    input:  The command line
#            The state dictionary
#
#   output:  Updated state dictionary
#            List of rules fired
#
#-------------------------------------------------------------------------------
def ORB_CMD_SW_rule_set(cmd_entry, last_state, present_state, bfc):
    """
    There are several commands of interest in the backstop file which are not
    ACISPKT commands. ORBPOINT commands are one set - they tell you if you
    are within a perigee passage zone.

    There are a few COMMAND_SW commands of interest as well: OORMPDS and
    OORMPEN - which also indicate whether or not you are within the RAD Zone.

    These rules are used to process these commands and set the relevant 
    system state parameters.

    No comparison is done with the previous command. 

    No violation searches.

    """
    # Create some handy lists
    inbound = [ 'OORMPDS', 'EEF1000']
    outbound = ['EPERIGEE', 'XEF1000']
    
    # Set the Rules fired list to EMPTY
    rules_fired = []

    # Init an empty violations list
    violations_list = []

    # Might as well record the times no matter what the command type is
    present_state.state['date_cmd'] = cmd_entry['event_date']
    present_state.state['time_cmd'] = cmd_entry['event_time']

    # Rule 1 - Check to see if this entry tells you that
    # you are in the inbound portion of the perigee passage
    if cmd_entry['packet_or_cmd'] in inbound:
        # You are in the inbound portion of the perigee passage - 
        # the part prior to Perigee.  Record that system_state
        present_state.state['perigee_passage'] = 'inbound'
        rules_fired.append('ORB/CMD Rule 1 - INBOUND OORMPDS or EEF1000'+ cmd_entry['event_date'])

    # Rule 2 - Check to see if this entry tells you that
    # you are in the inbound portion of the perigee passage
    if cmd_entry['packet_or_cmd'] in outbound:
        # You are in the outbound portion of the perigee passage - 
        # the part after Perigee.  Record that system_state
        present_state.state['science_run_exec'] = False
        present_state.state['perigee_passage'] = 'outbound'
        rules_fired.append('ORB/CMD Rule 2 - OUTBOUND '+ cmd_entry['event_date'])
  
    # Rule 3 - If this command is a RADMON ENABLE then
    # you are EXITING the perigee passage
    if cmd_entry['packet_or_cmd'] == 'OORMPEN':
        # You are done with the perigee passage - 
        # Record that system_state
        present_state.state['science_run_exec'] = False
        present_state.state['perigee_passage'] = False
        rules_fired.append('ORB/CMD_SW Rule 3 - Exiting Perigee Passage'+ cmd_entry['event_date'])
 

    # Return the system_state and the rules fired list
    return (  present_state, rules_fired, violations_list)
