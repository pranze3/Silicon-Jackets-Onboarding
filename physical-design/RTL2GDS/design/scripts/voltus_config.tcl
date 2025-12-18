# Generated using: Flowkit 23.10-a010_1
################################################################################
# Voltus attributes (design & library not required)
#
#  Attributes used to drive tool behavior.  Most typically these are root level
#  attributes.  All root attributes can be listed by using 'report_obj -all' or
#  by category using 'report_obj -all -verbose'
#
#  Further attribute help can be obtained by using the command 'help <ATTRIBUTE>'
#
#  The init_voltus flow_step is provided to specify tool level configs after a
#  design has been loaded via the init_design flow_step or specified as a
#  flow_starting_db from a subsequent flow (ie postroute).
#
################################################################################

##############################################################################
# STEP init_voltus_user
##############################################################################
create_flow_step -name init_voltus_user -owner design {
  # Design attributes  [get_db -category design]
  #-----------------------------------------------------------------------------
  
  # Delaycal attributes  [get_db -category delaycal]
  #-----------------------------------------------------------------------------
  
  # Power attributes  [get_db -category power]
  #-----------------------------------------------------------------------------
  if {[get_feature report_dynamic_ir]} {
    if {[is_flow -inside flow:ir_dynamic]} {
      set_db power_method                 < PLACEHOLDER: DYNAMIC POWER METHOD >
    }
  }
}
