# Generated using: Flowkit 23.10-a010_1
#- voltus_steps.tcl : defines Voltus based flow_steps

#=============================================================================
# Flow: ir_static
#=============================================================================

##############################################################################
# STEP report_power
##############################################################################
create_flow_step -name report_power -owner cadence {
  report_power \
    -pg_pin \
    -out_dir [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db [lindex [get_db flow_hier_path] end] .name]]
}

##############################################################################
# STEP report_rail
##############################################################################
create_flow_step -name report_rail -owner cadence {
  report_rail  \
    -output_dir [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db [lindex [get_db flow_hier_path] end] .name]] \
      -type domain  \
      ALL
}
