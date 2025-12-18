# Generated using: Flowkit 23.10-a010_1
################################################################################
# Genus attributes
#
#  Flow_steps used to drive tool behavior.  Most typically these are root level
#  attributes.  All root attributes can be listed by using 'report_obj -all' or
#  by category using 'report_obj -all -verbose'
#
#  Further attribute help can be obtained by using the command 'help <ATTRIBUTE>'
#
#  Two flow_steps are provided to allow users to specify tool level configs.
#  Users may add additional flow_steps to the file which also direct tool behaviour.
#
#    init_elaborate:  specify tool settings before a design has been loaded.  These are
#                      typically attributes in the 'hdl' and 'lib_*' categories.
#
#    init_genus_user: specify tool settings after a design has been loaded via init_design
#
################################################################################

##############################################################################
# STEP init_elaborate
##############################################################################
create_flow_step -name init_elaborate -owner design {
  # HDL attributes [get_db -category hdl]
  #-----------------------------------------------------------------------------
  
  # Low Power attributes [get_db -category lp_cg]
  #-----------------------------------------------------------------------------
  <%? {lp_insert_clock_gating} return [list set_db lp_insert_clock_gating [get_flow_config lp_insert_clock_gating]] %>
}

##############################################################################
# STEP init_genus_user
##############################################################################
create_flow_step -name init_genus_user -owner design {
  set_db heartbeat 300
  set_db max_cpus_per_server 16
  # Timing attributes  [get_db -category tim]
  #-----------------------------------------------------------------------------
  set_db timing_apply_default_primary_input_assertion true
  set_db timing_analysis_async_checks     async
  
  # Optimization attributes  [get_db -category netlist]
  #-----------------------------------------------------------------------------
  
  # Datapath attributes  [get_db -category dp]
  #-----------------------------------------------------------------------------
  
  # Leakage Power attributes  [get_db -category lp_opt lib_ui]
  #-----------------------------------------------------------------------------
  
}
