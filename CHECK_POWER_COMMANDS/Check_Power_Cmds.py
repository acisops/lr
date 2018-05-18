import pprint
import re
import glob

from Chandra.Time import DateTime

# bring in the system state class
import System_State_Class
#execfile('System_State_Class.py')

# Bring in the Backstop File Class
import Backstop_File_Class

# Bring in rule set which handles ACISPKT commands
import Rulesets as rules

# =======================  MAIN ==========================================
#      Processing the command array
# ========================================================================
"""
Check Power Commands - Check the sequence of power commands and report any 
                       instances where the delays between power commands
                       and other ACIS commands are incorrect.

                       Also, make sure that if you are finished with the
                       inbound ECS run and you have executed the WSPOW00000,
                       that the WSPOW0002A command was issued one hour later.

     The Rules:

    1)  4 seconds (at least) between ANY two ACIS Commands
          

    2)  24 seconds between WSPOW00000 (Power *DOWN*) 
        and ANY ACIS command (built in SI mode)


    3)  63 seconds between any POWER *UP* command and ANY ACIS command
        (in SI mode)
           - Power up commands are WSPOW commands that has non-zero
	     hex values

    4)  3 minutes between the AA00000000 and the WSPOW00000 or WSPOW0002A


    5) Must be 18 seconds after a WSVIDALLDN
     There seems to be 18 seconds between WSVIDALLDN's and the next
     power up command when you are re-using an SI mode.

    6)  If WSPOW00000 issued and an hour goes by without any power
       command,, issue a WSPOW0002A

    If a violation of these rules is detected, the number of the rule 
    in the above list is included in  the violation message.

"""
pp = pprint.PrettyPrinter(indent=4)

# Now create an instance of the the System State Class.
system_state = System_State_Class.System_State_Object()

# Create an instance of the Backstop_File_class
bfc = Backstop_File_Class.BackstopFileObject()

# Capture the important commands from the Backstop file
# First find the backstop file:
backstop_file = glob.glob('CR*.backstop')[0]

# The packets that we care about are stripped out here
system_packets = bfc.strip_out_ACISPKTs(backstop_file)

# Now that you have the array of ACIS Packets, and Perigee Passage indicators
# start working your way through the array. Note the time difference 
# between any adjacent ACISPKT type entries. Update the State when you 
# have sufficient information to do so.
#
# Create an empty list for rules firing history
all_rules_fired = []

# List of all violations found.  If populated, this is a list of dictionaries
violations_list = []

# Grab the first item in the array
present_cmd = system_packets[0]
# Which is, of course, at row zero
array_row_number = 0

# Now what you do is process each entry until you hit your
# first ACISPKT.  Then you process that first one.  This will set up
# the system state for processing the next ACISPKT you see
while present_cmd['cmd_type'] != 'ACISPKT':
    # Record the date of this command in system_state.state
    system_state.state['date_cmd'] = present_cmd['event_date']
    system_state.state['time_cmd'] = present_cmd['event_time']

    # Save the present system state in another variable
    last_state = dict(system_state.state)
    # Fire off the ORB/CMD rules REMEMBER - rules can have an impact on State.
    rules_fired = rules.ORB_CMD_SW_rule_set(present_cmd, system_state.state, violations_list)
    # If any rules fired append them to the rules_fired list
    if len(rules_fired) > 0:
        all_rules_fired.append(list(rules_fired))

    # Keep  running these rules until the system state doesn't change
    while last_state != system_state.state:
        # Save the present system state in another variable
        last_state = dict(system_state.state)
        # Fire off the ORB/CMD rules
        rules_fired = rules.ORB_CMD_SW_rule_set(present_cmd, system_state.state, violations_list)
        # If any rules fired append them to the rules_filred list
        if len(rules_fired) > 0:
            all_rules_fired.append(list(rules_fired))

    # You will be looking at the next row
    array_row_number += 1
    present_cmd = system_packets[array_row_number]

# So you've captured the information from the first ACISPKT so now
# you have something against which to compare the times of the next
# ACISPKT that you see.  
#
# Save it so that any number of commands that are NOT ACISPKT commands
# that lie between this command and the next ACISPKT command do not
# interfere with checking the command timing. For example:
#
# ACISPKT command
# OORMPEN
# ACISPKT command
bfc.write_previous_ACISPKT_cmd(present_cmd)
# Record the date of this command in system_state.state
system_state.state['date_cmd'] = present_cmd['event_date']
system_state.state['time_cmd'] = present_cmd['event_time']

# And since this is going to be "previous" then set last_state 
last_state = dict(system_state.state)

#
# Continue processing set the present packet to the NEXT one
# for eachpacket in system_packets[array_row_number+1:125]:
for eachpacket in system_packets[array_row_number+1:]:
    rules_fired = []
    # Record the date of this command in system_state.state
    system_state.state['date_cmd'] = eachpacket['event_date']
    system_state.state['time_cmd'] = eachpacket['event_time']

    if eachpacket['cmd_type'] == 'ACISPKT':
        # Save the present system state in another variable
        last_state = dict(system_state.state)
        # Run the ACISPKT ruleset once
        new_rules_fired, violations_list = rules.ACISPKT_rules(eachpacket,
                                                               last_state,
                                                               system_state,
                                                               bfc,
                                                               violations_list)
        # Append all the rules that may have fired
        if len(new_rules_fired) > 0:
            all_rules_fired.append(list(new_rules_fired))

        # Keep on running the ACISPKT rules until the state does not change
        while last_state != system_state.state:
            # Set the last state to the present state
            last_state = dict(system_state.state)
            # Run the ACISPKT ruleset again
            new_rules_fired, violations_list = rules.ACISPKT_rules(eachpacket,
                                                                   last_state,
                                                                   system_state,
                                                                   bfc,
                                                                   violations_list)
            # Append all the rules that may have fired
            if len(new_rules_fired) > 0:
                all_rules_fired.append(list(new_rules_fired))

        # Store the command you are assessing as the previous command
        bfc.write_previous_ACISPKT_cmd(eachpacket)
                
    else:
        # Else it's not an acis packet so run the CMD/ORB rule set
        rules_fired = rules.ORB_CMD_SW_rule_set(eachpacket, system_state.state, violations_list)
        # If any rules fired, append them to the list
        if len(rules_fired) > 0:
            all_rules_fired.append(list(rules_fired))

        # Keep running until the system state doesn't change
        while last_state != system_state.state:
            # Save the present system state in another variable
            last_state = dict(system_state.state)
            # Fire off the ORB/CMD rules
            rules_fired = rules.ORB_CMD_SW_rule_set(present_cmd, system_state.state, violations_list)
            # If any rules fired append them to the rules_filred list
            if len(rules_fired) > 0:
                all_rules_fired.append(list(rules_fired))


# Write out the error
bfc.insert_errors('ACIS-LoadReview.txt', violations_list)

