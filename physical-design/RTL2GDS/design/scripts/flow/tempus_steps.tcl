# Generated using: Flowkit 23.10-a010_1
#- tempus_steps.tcl : defines Tempus based flow_steps

#=============================================================================
# Flow: sta
#=============================================================================

##############################################################################
# STEP set_propagated_clocks
##############################################################################
create_flow_step -name set_propagated_clocks -owner cadence {
  #- propagate clock sources
  set_interactive_constraint_mode [get_db constraint_modes -if {.is_setup || .is_hold}]
  set_propagated_clock [get_db clocks .sources]
  set_interactive_constraint_mode {}
}

##############################################################################
# STEP update_timing
##############################################################################
create_flow_step -name update_timing -owner cadence -write_db {
  #- update timer for signoff timing reports
  update_timing -full
}

##############################################################################
# STEP check_timing
##############################################################################
create_flow_step -name check_timing -owner cadence -exclude_time_metric -categories design {
  #- Reports that check design health
  check_netlist -out_file        [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]check.netlist.rpt]
  check_timing                 > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]check.timing.rpt]
  report_analysis_coverage     > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]check.coverage.rpt]
  report_annotated_parasitics  > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]check.annotation.rpt]
  
  #- Reports that describe constraints
  report_clocks                > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]report.clocks.rpt]
  report_case_analysis         > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]report.case_analysis.rpt]
  report_inactive_arcs         > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]report.inactive_arcs.rpt]
}

##############################################################################
# STEP report_late_summary
##############################################################################
create_flow_step -name report_late_summary -owner cadence -exclude_time_metric -categories setup {
  #- Reports that describe timing health
  report_timing_summary -checks {setup drv} > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]setup.analysis_summary.rpt]
  report_timing_summary -checks {setup drv} -expand_views > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]setup.view_summary.rpt]
  report_timing_summary -checks {setup drv} -expand_views -expand_clocks launch_capture  > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]setup.group_summary.rpt]
  report_constraint -late -all_violators -drv_violation_type {max_capacitance max_transition max_fanout} > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]setup.all_violators.rpt]
  set_metric -name timing.setup.type -value gba
  set_metric -name timing.drv.report_file -value [file join [get_db flow_report_name] [get_db flow_report_prefix]setup.all_violators.rpt]
}

##############################################################################
# STEP report_early_summary
##############################################################################
create_flow_step -name report_early_summary -owner cadence -exclude_time_metric -categories hold {
  #- Reports that describe early timing health
  report_timing_summary -checks {hold drv} > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]hold.analysis_summary.rpt]
  report_timing_summary -checks {hold drv} -expand_views > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]hold.view_summary.rpt]
  report_timing_summary -checks {hold drv} -expand_views -expand_clocks launch_capture  > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]hold.group_summary.rpt]
  set_metric -name timing.hold.type -value gba
  report_constraint -early -all_violators -drv_violation_type {min_capacitance min_transition min_fanout} > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]hold.all_violators.rpt]
}

