# Generated using: Flowkit 23.10-a010_1
#- innovus_steps.tcl : defines Innovus based flow_steps

#=============================================================================
# Flow: floorplan
#=============================================================================

##############################################################################
# STEP add_tracks
##############################################################################
create_flow_step -name add_tracks -owner cadence {
  #- generate tracks after creating floorplan
  if {[llength [get_db current_design .track_patterns]] == 0} {
    add_tracks
  }
}
#===========================================================================
# Flow: prects
#===========================================================================

##############################################################################
# STEP add_clock_spec
##############################################################################
create_flow_step -name add_clock_spec -owner cadence {
  #- automatically create clock spec if one is not available
  if {[llength [get_db clock_trees]] == 0} {
    create_clock_tree_spec
  } else {
    puts "INFO: reusing existing clock tree spec"
    puts "        to reload a new one use 'reset_cts_config' and 'read_cts_config' commands"
  }
}

##############################################################################
# STEP commit_route_types
##############################################################################
create_flow_step -name commit_route_types -owner cadence {
  #- assign route_types to clock nets
  commit_clock_tree_route_attributes
}

##############################################################################
# STEP run_place_opt
##############################################################################
create_flow_step -name run_place_opt -owner cadence {
  #- perform global placement and ideal clock setup optimization
  place_opt_design -report_dir debug -report_prefix [get_db flow_report_name]
}
#=============================================================================
# Flow: cts
#=============================================================================

##############################################################################
# STEP add_clock_tree
##############################################################################
create_flow_step -name add_clock_tree -owner cadence {
  #- implement clock trees and propagated clock setup optimization
  if {[get_db opt_enable_podv2_clock_opt_flow]} {
    clock_opt_design -report_dir debug -report_prefix [get_db flow_report_name]
  } else {
    ccopt_design -report_dir debug -report_prefix [get_db flow_report_name]
  }
}

##############################################################################
# STEP add_tieoffs
##############################################################################
create_flow_step -name add_tieoffs -owner cadence {
  #- insert dedicated tieoff models
  if {[get_db add_tieoffs_cells] ne "" } {
    delete_tieoffs
    add_tieoffs -matching_power_domains true
  }
}
#=============================================================================
# Flow: postcts
#=============================================================================

##############################################################################
# STEP run_opt_postcts_hold
##############################################################################
create_flow_step -name run_opt_postcts_hold -owner cadence {
  #- perform postcts hold optimization
  opt_design -post_cts -hold -report_dir debug -report_prefix [get_db flow_report_name]
}
#=============================================================================
# Flow: route
#=============================================================================

##############################################################################
# STEP add_fillers
##############################################################################
create_flow_step -name add_fillers -owner cadence {
  #- insert filler cells before final routing
  if {[get_db add_fillers_cells] ne "" } {
    add_fillers
  }
}

##############################################################################
# STEP run_route
##############################################################################
create_flow_step -name run_route -owner cadence {
  #- perform detail routing and DRC cleanup
  route_design
}
#=============================================================================
# Flow: postroute
#=============================================================================

##############################################################################
# STEP run_opt_postroute
##############################################################################
create_flow_step -name run_opt_postroute -owner cadence {
  #- perform postroute and SI based setup optimization
  opt_design -post_route -setup -hold -report_dir debug -report_prefix [get_db flow_report_name]
}
  #=============================================================================
  # Flow: opt_signoff
  #=============================================================================
  
  ############################################################################
  # STEP run_opt_signoff
  ############################################################################
  create_flow_step -name run_opt_signoff -owner cadence {
    #- perform signoff based optimization
    opt_signoff -all -report_dir debug -report_prefix [get_db flow_report_name]
  }
#=============================================================================
# Flow: eco
#=============================================================================

##############################################################################
# STEP eco_start
##############################################################################
create_flow_step -name eco_start -owner cadence {
}

##############################################################################
# STEP run_place_eco
##############################################################################
create_flow_step -name run_place_eco -owner cadence {
  place_eco
}

##############################################################################
# STEP run_route_eco
##############################################################################
create_flow_step -name run_route_eco -owner cadence {
  route_eco
}

##############################################################################
# STEP eco_finish
##############################################################################
create_flow_step -name eco_finish -owner cadence -write_db {
  apply {{} {
    #- Make sure flow_report_name is reset from any reports executed during the flow
    set_db flow_report_name [get_db [lindex [get_db flow_hier_path] end] .name]
  
    #- Set value for SPEF output file generation
    if {[get_db flow_branch] ne ""} {
      set out_dir [file join [get_db flow_db_directory] [get_db flow_branch]_[get_db flow_report_name]]
    } else {
      set out_dir [file join [get_db flow_db_directory] [get_db flow_report_name]]
    }
    set_db flow_spef_directory $out_dir
  
    #- Store non-default root attributes to metrics
    catch {report_obj -tcl} flow_root_config
    if {[dict exists $flow_root_config root:/]} {
      set flow_root_config [dict get $flow_root_config root:/]
    } elseif {[dict exists $flow_root_config root:]} {
      set flow_root_config [dict get $flow_root_config root:]
    } else {
    }
    foreach key [dict keys $flow_root_config] {
      if {[string length [dict get $flow_root_config $key]] > 200} {
        dict set flow_root_config $key "\[long value truncated\]"
      }
    }
    set_metric -name flow.root_config -value $flow_root_config
  }}
}
#===========================================================================
# Flow: report_innovus
#===========================================================================
if {[get_feature report_lec]} {
  
  ############################################################################
  # STEP innovus_to_lec
  ############################################################################
  create_flow_step -name innovus_to_lec -owner flow {
    #- write dofile for LEC
    write_do_lec \
      -flat \
      -log_file [file join [get_db flow_log_directory] lec.[get_db flow_report_name].log] \
      lec.[get_db flow_report_name].do
    
    #- schedule the LEC flow
    #FlowtoolPredictHint ArgumentRandomise -branch
    schedule_flow \
      -flow lec \
      -branch [get_db flow_report_name] \
      -include_in_metrics \
      -no_db \
      -no_sync \
      -tool_options "-- -nogui -lp -do [file join [string map [list %s [get_db current_design .name]] [get_db write_lec_directory_naming_style]] lec.[get_db flow_report_name].do]"
  }
}

##############################################################################
# STEP report_check_design
##############################################################################
create_flow_step -name report_check_design -owner cadence -exclude_time_metric -categories design {
  apply {{} {
    set check_list [list timing place opt]
    if {[join [dict values [get_db init_power_intent_files]]] ne {}} {
      lappend check_list power_intent
    }
    if {[is_flow -inside flow:report_postroute]} {
      check_design -out_file [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]check.design.tcl] -type [lappend check_list cts route]
    } elseif {[is_flow -inside flow:report_postcts]} {
      check_design -out_file [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]check.design.tcl] -type [lappend check_list cts]
    } else {
      check_design -out_file [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]check.design.tcl] -type $check_list
    }
  }}
}

##############################################################################
# STEP report_area_innovus
##############################################################################
create_flow_step -name report_area_innovus -owner cadence -exclude_time_metric -categories design {
  report_summary -no_html -out_dir debug -out_file [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]qor.rpt]
  report_area -min_count 1000 -out_file [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]area.summary.rpt]
}

##############################################################################
# STEP report_late_summary_innovus
##############################################################################
create_flow_step -name report_late_summary_innovus -owner cadence -exclude_time_metric -categories setup {
  #- Update the timer for setup and write reports
  time_design -expanded_views -report_only -report_dir debug -report_prefix [get_db flow_report_name]
  
  #- Reports that describe timing health
  report_timing_summary -checks {setup drv} > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]setup.analysis_summary.rpt]
  report_timing_summary -checks {setup drv} -expand_views > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]setup.view_summary.rpt]
  report_timing_summary -checks {setup drv} -expand_views -expand_clocks launch_capture  > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]setup.group_summary.rpt]
  report_constraint -late -all_violators -drv_violation_type {max_capacitance max_transition max_fanout} > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]setup.all_violators.rpt]
  set_metric -name timing.setup.type -value gba
  set_metric -name timing.drv.report_file -value [file join [get_db flow_report_name] [get_db flow_report_prefix]setup.all_violators.rpt]
}

##############################################################################
# STEP report_early_summary_innovus
##############################################################################
create_flow_step -name report_early_summary_innovus -owner cadence -exclude_time_metric -categories hold {
  #- Update the timer for hold and write reports
  time_design -expanded_views -hold -report_only -report_dir debug -report_prefix [get_db flow_report_name]
  
  #- Reports that describe timing health
  report_timing_summary -checks {hold drv} > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]hold.analysis_summary.rpt]
  report_timing_summary -checks {hold drv} -expand_views > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]hold.view_summary.rpt]
  report_timing_summary -checks {hold drv} -expand_views -expand_clocks launch_capture  > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]hold.group_summary.rpt]
  report_constraint -early -all_violators -drv_violation_type {min_capacitance min_transition min_fanout} > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]hold.all_violators.rpt]
  set_metric -name timing.hold.type -value gba
}

##############################################################################
# STEP report_clock_timing
##############################################################################
create_flow_step -name report_clock_timing -owner cadence -exclude_time_metric -categories clock {
  #- Reports that check clock implementation
  report_clock_timing -type summary > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]clock.summary.rpt]
  report_clock_timing -type latency > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]clock.latency.rpt]
  report_clock_timing -type skew    > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]clock.skew.rpt]
}

##############################################################################
# STEP report_power_innovus
##############################################################################
create_flow_step -name report_power_innovus -owner cadence -exclude_time_metric -categories power {
  report_power -no_wrap -out_file [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]power.all.rpt]
}

##############################################################################
# STEP report_route_process
##############################################################################
create_flow_step -name report_route_process -owner cadence -exclude_time_metric {
  #- Reports that process rules
  check_process_antenna -out_file [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]route.antenna.rpt]
  check_filler -out_file [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]route.filler.rpt]
  set_metric -name check.drc.antenna.report_file -value [file join [get_db flow_report_name] [get_db flow_report_prefix]route.antenna.rpt]
}

##############################################################################
# STEP report_route_drc
##############################################################################
create_flow_step -name report_route_drc -owner cadence -exclude_time_metric -categories route {
  #- Reports that check signal routing
  if {[is_flow -inside flow:report_floorplan]} {
    check_drc -check_only special -ignore_trial_route -out_file [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]route.drc.rpt]
  } else {
    check_drc -out_file [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]route.drc.rpt]
    check_connectivity -out_file [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]route.open.rpt]
  }
  set_metric -name check.drc.report_file -value [file join [get_db flow_report_name] [get_db flow_report_prefix]route.drc.rpt]
}

##############################################################################
# STEP report_route_density
##############################################################################
create_flow_step -name report_route_density -owner cadence -exclude_time_metric {
  check_metal_density -report [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]route.metal_density.rpt]
  check_cut_density -out_file [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]route.cut_density.rpt]
}
