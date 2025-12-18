# Generated using: Flowkit 23.10-a010_1
################################################################################
# Tempus attributes
#
#  Attributes used to drive tool behavior.  Most typically these are root level
#  attributes.  All root attributes can be listed by using 'report_obj -all' or
#  by category using 'report_obj -all -verbose'
#
#  Further attribute help can be obtained by using the command 'help <ATTRIBUTE>'
#
#  The init_tempus flow_step is provided to specify tool level configs after a
#  design has been loaded via the init_design flow_step or specified as a
#  flow_starting_db from a subsequent flow (ie postroute).
#
################################################################################

##############################################################################
# STEP init_tempus_user
##############################################################################
create_flow_step -name init_tempus_user -owner design {
  # Design attributes  [get_db -category design]
  #-----------------------------------------------------------------------------
  
  # Timing attributes  [get_db -category timing]
  #-----------------------------------------------------------------------------
  
  # Delaycal attributes  [get_db -category delaycal]
  #-----------------------------------------------------------------------------
  
  # SI attributes  [get_db -category si]
  #-----------------------------------------------------------------------------
  
  # Opt Signoff attributes  [get_db -category opt_signoff]
  #-----------------------------------------------------------------------------
}
