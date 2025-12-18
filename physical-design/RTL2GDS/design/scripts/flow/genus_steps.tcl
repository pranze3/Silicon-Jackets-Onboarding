# Generated using: Flowkit 23.10-a010_1
#- genus_steps.tcl : defines Genus based flow_steps

#===========================================================================
# Flow: synth
#===========================================================================

##############################################################################
# STEP run_syn_generic
##############################################################################
create_flow_step -name run_syn_generic -owner cadence {
  #- Synthesize to generic gates
  syn_generic
}

##############################################################################
# STEP run_syn_map
##############################################################################
create_flow_step -name run_syn_map -owner cadence {
  #- Synthesize to target library gates
  syn_map
}

##############################################################################
# STEP run_syn_opt
##############################################################################
create_flow_step -name run_syn_opt -owner cadence {
  #- Synthesize to optimized gates
  syn_opt
}

##############################################################################
# STEP genus_to_innovus
##############################################################################
create_flow_step -name genus_to_innovus -owner cadence {
  #- Apply change_name rules
  update_names \
    [get_db current_design] \
    -force \
    -verilog \
    -module \
    -append_log \
    -log [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]design.change_names.rpt]
  
  write_design \
   -gzip_files \
   -basename [file normalize [file join [get_db flow_db_directory] [get_db flow_report_name] [get_db current_design .name]]]
}
#===========================================================================
# Flow: report_genus
#===========================================================================

##############################################################################
# STEP report_area_genus
##############################################################################
create_flow_step -name report_area_genus -owner cadence -exclude_time_metric -categories design {
  report_area -min_count 1000 > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]area.summary.rpt]
  report_dp                   > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]area.datapath.rpt]
}

##############################################################################
# STEP report_late_summary_genus
##############################################################################
create_flow_step -name report_late_summary_genus -owner cadence -exclude_time_metric -categories setup {
  report_timing_summary -checks {setup drv} > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]setup.analysis_summary.rpt]
  report_timing_summary -checks {setup drv} -expand_views > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]setup.view_summary.rpt]
  report_timing_summary -checks {setup drv} -expand_views -expand_clocks launch_capture  > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]setup.group_summary.rpt]
  set_metric -name timing.setup.type -value gba
  report_qor > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]qor.rpt]
}

##############################################################################
# STEP report_power_genus
##############################################################################
create_flow_step -name report_power_genus -owner cadence -exclude_time_metric -categories power {
  report_gates -power   > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]power.all.rpt]
  report_clock_gates    > [file join [get_db flow_report_directory]/[get_db flow_report_name] [get_db flow_report_prefix]power.clock_gating.rpt]
  report_power -by_category > [file join [get_db flow_report_directory]/[get_db flow_report_name] [get_db flow_report_prefix]power.design.rpt]
}
