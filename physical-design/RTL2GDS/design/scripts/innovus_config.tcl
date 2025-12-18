# Generated using: Flowkit 23.10-a010_1
################################################################################
# Innovus attributes
#
#  Attributes used to drive tool behavior.  Most typically these are root level
#  attributes.  All root attributes can be listed by using 'report_obj -all' or
#  by category using 'report_obj -all -verbose'
#
#  Further attribute help can be obtained by using the command 'help <ATTRIBUTE>'
#
#  The init_innovus_user flow_step is provided to specify tool level configs after a
#  design has been loaded via the init_design flow_step or specified as a
#  flow_starting_db from a subsequent flow (ie syn_opt).
#
################################################################################

##############################################################################
# STEP init_innovus_user
##############################################################################
create_flow_step -name init_innovus_user -owner design {
  # Timing attributes  [get_db -category timing && delaycalc]
  #-----------------------------------------------------------------------------
  
  # Extraction attributes  [get_db -category extract_rc]
  #-----------------------------------------------------------------------------
  
  # Floorplan attributes  [get_db -category floorplan]
  #-----------------------------------------------------------------------------
  set_db finish_floorplan_active_objs   [list macro soft_blockage core]
  
  # Placement attributes  [get_db -category place]
  #-----------------------------------------------------------------------------
  
  # Optimization attributes  [get_db -category opt]
  #-----------------------------------------------------------------------------
  
  # Clock attributes  [get_db -category cts]
  #-----------------------------------------------------------------------------
  
  # Routing attributes  [get_db -category route]
  #-----------------------------------------------------------------------------
}
