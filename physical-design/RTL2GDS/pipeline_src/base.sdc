# Set the unit for time-related constraints to nanoseconds (ns)
set_units -time ns

# Define the clock period in nanoseconds
set CLOCK_PERIOD 1.29 ;# Clock period is set to 1ns sho

# Set the constraint mode to "func" (functional mode)
set_interactive_constraint_modes {func}

# Create a clock named "core_clock" with a period of $CLOCK_PERIOD
# The clock is associated with all ports matching the pattern "*clk*"
create_clock [get_ports *clk*] -name core_clock -period $CLOCK_PERIOD

# Set the maximum transition time (slew) for all ports to 1.5 ns
set_max_transition 1.5 [get_ports *]

# Retrieve all clocks defined in the database and store them in the variable `clocks`
set clocks [get_db clocks]

# Define the output capacitance load in femtofarads (fF)
set OUTPUT_CAP_LOAD 33.442  ;# Output load is set to 33.442 fF

# Convert the capacitance load from femtofarads to picofarads (pF)
set cap_load [expr $OUTPUT_CAP_LOAD / 1000.0]

# Print an informational message about the calculated load
puts "\[INFO] Setting load to: $cap_load"

# Apply the calculated capacitance load to all ports
set_load $cap_load [get_ports *]

# Define the IO delay constraint as a percentage of the clock period
set IO_DELAY_CONSTRAINT 20  ;# IO delay is set to 20% of the clock period

# Calculate input and output delay values based on the IO delay constraint
set input_delay_value [expr $CLOCK_PERIOD * $IO_DELAY_CONSTRAINT / 100]
set output_delay_value [expr $CLOCK_PERIOD * $IO_DELAY_CONSTRAINT / 100]

# Print informational messages about input and output delay values
puts "\[INFO] Setting output delay to: $output_delay_value"
puts "\[INFO] Setting input delay to: $input_delay_value"

# Define clock uncertainty (jitter) in nanoseconds
set CLOCK_UNCERTAINTY_CONSTRAINT 0.25  ;# Clock uncertainty is set to 0.25 ns

# Print an informational message about clock uncertainty
puts "\[INFO] Setting clock uncertainty to: $CLOCK_UNCERTAINTY_CONSTRAINT"

# Apply the clock uncertainty constraint to all clocks in the design
set_clock_uncertainty $CLOCK_UNCERTAINTY_CONSTRAINT $clocks

# Define maximum clock transition time in nanoseconds
set CLOCK_TRANSITION_CONSTRAINT .15  ;# Clock transition time is set to 0.15 ns

# Print an informational message about clock transition time
puts "\[INFO] Setting clock transition to: $CLOCK_TRANSITION_CONSTRAINT"

# Apply the clock transition constraint to all clocks in the design
set_clock_transition $CLOCK_TRANSITION_CONSTRAINT $clocks

# Define timing derating percentage for early and late paths
set TIME_DERATING_CONSTRAINT 5  ;# Timing derate is set to 5%

# Print an informational message about timing derating
puts "\[INFO] Setting timing derate to: $TIME_DERATING_CONSTRAINT%"

# Apply timing derate for early paths (reduce timing by 5%)
set_timing_derate -early [expr 1-[expr $TIME_DERATING_CONSTRAINT / 100]]

# Apply timing derate for late paths (increase timing by 5%)
set_timing_derate -late [expr 1+[expr $TIME_DERATING_CONSTRAINT / 100]]

# Set maximum fanout for any net in the design to 4
set_max_fanout 4

