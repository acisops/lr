################################################################################
#
#  Check_Power_Cmds - Check the power command spacing in the load to see if the
#                     rules ahve been adhered to. Any errors are inserted into a
#                     new ACIS-LoadReviews.dat file.
#
#                     For the time being, this new file is kept separate from
#                     ACIS-LoadREviews.dat file and is called:
#                            ACIS-LoadReview.dat.ERROR
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
#
################################################################################
import re
import glob

from Chandra.Time import DateTime

# bring in the system state class
import System_State_Class

# Bring in the Backstop File Class
import Backstop_File_Class

# Bring in rule set which handles ACISPKT commands
import Rulesets

#-------------------------------------------------------------------------------
#  Function: run_one_command - Run one command though the specified  rule set
#                              until the system state does not change
#
#       Inputs:         cmd - the backstop command to be processed
#              system_state - the present state of the system (class)
#                   ruleset - the rule set functionto be used
#
#      Outputs: Final State
#               violations list

#-------------------------------------------------------------------------------
def run_one_command(cmd, system_state, bfc, rule_set):

    # Init the empty list of rules fired in this call
    all_rules_fired = []

    # Init an empty violations list
    violations_list = []

    # Record the date of this command in system_state.state
    system_state.state['date_cmd'] = cmd['event_date']
    system_state.state['time_cmd'] = cmd['event_time']

    # Save the present system state in last state.
    last_state = dict(system_state.state)

    # Now run the rule set once and then check to see if the state changed.
    # REMEMBER - rules can have an impact on State.

    system_state, new_rules_fired, vio_list = rule_set(cmd,
                                                       last_state,
                                                       system_state,
                                                       bfc)
    # Append all the rules that may have fired
    if new_rules_fired:
         all_rules_fired += new_rules_fired
       
    # Append any violations that were dete4cted to the master list
    if vio_list:
        violations_list.append(vio_list)

    # Keep on running the ACISPKT rules until the state does not change
    while last_state != system_state.state:
        # Set the last state to the present state
        last_state = dict(system_state.state)
        # Run the ACISPKT ruleset again
        system_state, new_rules_fired, vio_list = rule_set(cmd,
                                                           last_state,
                                                           system_state,
                                                           bfc)
    # Append all the rules that may have fired
    if new_rules_fired:
         all_rules_fired += new_rules_fired
       
    # Append any violations, that were detected, to the master list
    if vio_list:
        violations_list.append(vio_list)
              
    # Return the important values
    return (system_state, all_rules_fired, violations_list)
    


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

    If a violation of these rules is detected, the number of the rule 
    in the above list is included in  the violation message.

    Last state is used to determine if it's fruitless to keep running a
    rule set. Set it equal to the presetn state and then run some rules. 
    Then you check to see if the state changed. If it did, keep running the rules.
    If it did not, then stop.
"""
# Now create an instance of the the System State Class.
#system_state = System_State_Class.System_State_Object()
system_state = System_State_Class.System_State_Object()

# Create an instance of the Backstop_File_class
bfc = Backstop_File_Class.Backstop_File_Object()

# Capture the important commands from the Backstop file
# First find the backstop file:
backstop_file = glob.glob('CR*.backstop')[0]

# The packets that we care about are stripped out of the backstop file
# here.  These are the entities that will be analyzed
system_packets = bfc.strip_out_pertinent_packets(backstop_file)

# Create an empty list for rules firing history
all_rules_fired = []

# List of all violations found.  If populated, this is a list of dictionaries
all_violations = []
violations_list = []

# Which is, of course, at row zero
array_row_number = 0

# Grab the first item in the array
present_cmd = system_packets[array_row_number]

# Now  process each entry until you hit your
# first ACISPKT.  Then you process that first one.  This will set up
# the system state for processing the next ACISPKT that you encounter
while present_cmd['cmd_type'] != 'ACISPKT':

    # Run the ORB rules on the present state
    system_state, new_rules_fired, violations_list = run_one_command(present_cmd,
                                                                     system_state,
                                                                     bfc,
                                                                     Rulesets.ORB_CMD_SW_rule_set)
  
    # Append all the rules that may have fired to the master rule list
    if new_rules_fired:
        all_rules_fired.append(list(new_rules_fired))
 
    # Append any violations you found to the master violations list
    if violations_list:
        all_violations.append(violations_list[0])

    # You want to increment the system_packets index so that you can look
    # at the next command.
    # You will be looking at the next row
    array_row_number += 1

    # Now look at the next command in the backstop file.
    present_cmd = system_packets[array_row_number]


# Ok so this next command you are looking at is an ACISPKT command.
# The first one you've ever seen. And you have not processed it yet.
#
# Save it so that any number of commands that are NOT ACISPKT commands
# that lie between this command and the next ACISPKT command do not
# interfere with checking the command timing. For example:
#
# ACISPKT command
# OORMPEN
# ACISPKT command

# Create a bogus first ACISPKT command so that the REAL first
# ACISPKT command rules can modify the state but not test any
# back to back ACISPKT command rules.
bfc.write_bogus_previous_ACISPKT_cmd(present_cmd)

# Start processing all the rest of the commands
# The first one will be an ACISPKT command because the loop
# above set that up.
# for eachpacket in system_packets[array_row_number+1:125]:
for eachpacket in system_packets[array_row_number:]:
    new_rules_fired = []

    # If this command is an ACISPKT command, run those rules
    if eachpacket['cmd_type'] == 'ACISPKT':

        # June 2019 change - first run the state rules...
        system_state, new_rules_fired, violations_list = run_one_command(eachpacket,
                                                                         system_state,
                                                                         bfc,
                                                                         Rulesets.ACISPKT_State_rules)
   
        # ...now run the timing check rules.

        system_state, new_rules_fired, violations_list = run_one_command(eachpacket,
                                                                         system_state,
                                                                         bfc,
                                                                         Rulesets.ACISPKT_rules)

        # Store the command you are assessing as the previous command
        bfc.write_previous_ACISPKT_cmd(eachpacket)
                    
    else: 
        # Else it's not an ACISPKT so run the CMD/ORB rule set
        system_state, new_rules_fired, violations_list = run_one_command(eachpacket,
                                                                         system_state,
                                                                         bfc,
                                                                         Rulesets.ORB_CMD_SW_rule_set)
  


    # Append all the rules that may have fired
    if new_rules_fired:
        all_rules_fired.append(list(new_rules_fired))
 
    # Append any violations you found to the master violations list
    if violations_list:
        all_violations += violations_list[0]

# Write out the error
bfc.insert_errors('ACIS-LoadReview.txt', all_violations)
