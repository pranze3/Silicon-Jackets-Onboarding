# Generated using: Flowkit 23.10-a010_1

set_db flow_template_type {stylus}
set_db flow_template_version {1}
set_db flow_template_tools {genus innovus tempus quantus voltus}
set_db flow_template_feature_definition {flow_express 0 report_inline {} report_defer 0 report_none 0 report_clp 0 report_lec {} use_common_db 0 report_pba {} dft_simple 0 dft_compressor 0 synth_hybrid 0 synth_ispatial 0 synth_placev2 0 opt_early_cts 0 clock_design 0 clock_flexible_htree 0 opt_clock 0 opt_postcts_hold_disable 0 opt_postcts_split 0 route_filler_disable 0 route_track_opt 0 route_secondary_nets 0 opt_postroute_split 0 opt_route 0 opt_signoff {} opt_em 0 opt_eco 0 sta_use_setup_yaml 0 sta_dmmmc 0 sta_glitch 0 sta_eco 0 report_early_static_ir 0 report_early_dynamic_ir 0 report_grid_resistance 0 report_static_ir {} report_dynamic_ir {} report_rampup 0 report_signal_em 0 report_power_em 0 report_power_parallel 0 ff_setup 0}

#===============================================================================
# Common flow attributes
#===============================================================================

#- Specify qor html file to generate at the end of every flow
if {[is_attribute -obj_type root flowtool_metrics_qor_vivid]} {
  set_db flowtool_metrics_qor_vivid [file join [get_db flow_report_directory] qor.html]
  if {[file exists [file join [get_db init_flow_directory] metric_config.yaml]]} {
    read_metric_config -format vivid [file join [get_db init_flow_directory] metric_config.yaml]
  }
}

#- Define attribute for report name
if { ![is_attribute -obj_type root flow_report_name]} {
  define_attribute flow_report_name \
    -category flow \
    -data_type string \
    -default "" \
    -help_string "Name to use during report generation" \
    -obj_type root
}

#- Define attribute for report prefix
if { ![is_attribute -obj_type root flow_report_prefix]} {
  define_attribute flow_report_prefix \
    -category flow \
    -data_type string \
    -default "" \
    -help_string "File prefix to use during report generation" \
    -obj_type root
}

#- Define attribute for spef output location
if { ![is_attribute -obj_type root flow_spef_directory]} {
  define_attribute flow_spef_directory \
    -category flow \
    -data_type string \
    -default "" \
    -help_string "Location of SPEF files written by Quantus" \
    -obj_type root
}

#- Specify Flow Header (runs at the start of run_flow command)
set_db flow_header_tcl {
  #- extend flow report name based on context
  if {[is_flow -quiet -inside flow:sta] || [is_flow -quiet -inside flow:sta_dmmmc] || [is_flow -quiet -inside flow:sta_eco]} {
    if {![regexp {sta$} [get_db flow_report_name]]} {
      set_db flow_report_name [expr {[string is space [get_db flow_report_name]] ? "sta" : "[get_db flow_report_name].sta"}]
    }
  } elseif {[is_flow -quiet -inside flow:ir_early_static] || [is_flow -quiet -inside flow:ir_early_dynamic]} {
    if {![regexp {era$} [get_db flow_report_name]]} {
      set_db flow_report_name [expr {[string is space [get_db flow_report_name]] ? "era" : "[get_db flow_report_name].era"}]
    }
  } elseif {[is_flow -quiet -inside flow:ir_grid] || [is_flow -quiet -inside flow:ir_static] || [is_flow -quiet -inside flow:ir_dynamic] || [is_flow -quiet -inside flow:ir_rampup]} {
    if {![regexp {ir$} [get_db flow_report_name]]} {
      set_db flow_report_name [expr {[string is space [get_db flow_report_name]] ? "ir" : "[get_db flow_report_name].ir"}]
    }
  } elseif {[is_flow -quiet -inside flow:sta_subflows] && [get_db flow_branch] ne {}} {
    set_db flow_report_name [get_db flow_branch]
  } elseif {[regexp {block_start|hier_start|eco_start} [get_db flow_step_current]]} {
    set_db flow_report_name [get_db [lindex [get_db flow_hier_path] end] .name]
  } else {
  }

  #- Create report dir (if necessary)
  file mkdir [file normalize [file join [get_db flow_report_directory] [get_db flow_report_name]]]
}



#=============================================================================
# Flow: Implementation Flows
#=============================================================================

create_flow -name init_design -owner cadence -tool genus {read_mmmc read_physical read_hdl read_power_intent run_init_design}

create_flow -name init_genus -owner cadence -tool genus {init_genus_yaml init_genus_user}

set syn_generic_steps {block_start init_elaborate init_design init_genus set_dont_use commit_power_intent run_syn_generic block_finish}
if {[get_feature report_inline]} { lappend syn_generic_steps report_synth }
if {![get_feature report_inline]} { lappend syn_generic_steps schedule_syn_generic_report_synth }
create_flow -name syn_generic -owner cadence -tool genus -tool_options -disable_user_startup $syn_generic_steps

set syn_map_steps {block_start init_genus run_syn_map block_finish}
if {[get_feature report_inline]} { lappend syn_map_steps report_synth }
if {![get_feature report_inline]} { lappend syn_map_steps schedule_syn_map_report_synth }
if {[get_feature report_lec]} { lappend syn_map_steps genus_to_lec }
create_flow -name syn_map -owner cadence -tool genus -tool_options -disable_user_startup $syn_map_steps

set syn_opt_steps {block_start init_genus run_syn_opt block_finish}
if {[get_feature report_inline]} { lappend syn_opt_steps report_synth }
if {![get_feature report_inline]} { lappend syn_opt_steps schedule_syn_opt_report_synth }
if {[get_feature report_lec]} { lappend syn_opt_steps genus_to_lec }
create_flow -name syn_opt -owner cadence -tool genus -tool_options -disable_user_startup $syn_opt_steps


create_flow -name init_innovus -owner cadence -tool innovus {init_innovus_yaml init_innovus_user}

set floorplan_steps {block_start init_innovus init_floorplan commit_power_intent add_tracks block_finish}
if {[get_feature report_inline]} { lappend floorplan_steps report_floorplan }
if {![get_feature report_inline]} { lappend floorplan_steps schedule_floorplan_report_floorplan }
if {[get_feature report_lec]} { lappend floorplan_steps innovus_to_lec }
create_flow -name floorplan -owner cadence -tool innovus -tool_options -disable_user_startup $floorplan_steps

set prects_steps {block_start init_innovus add_clock_spec add_clock_route_types commit_route_types run_place_opt block_finish}
if {[get_feature report_inline]} { lappend prects_steps report_prects }
if {![get_feature report_inline]} { lappend prects_steps schedule_prects_report_prects }
create_flow -name prects -owner cadence -tool innovus -tool_options -disable_user_startup $prects_steps

set cts_steps {block_start init_innovus add_clock_tree add_tieoffs block_finish}
if {[get_feature report_inline]} { lappend cts_steps report_postcts }
if {![get_feature report_inline]} { lappend cts_steps schedule_cts_report_postcts }
create_flow -name cts -owner cadence -tool innovus -tool_options -disable_user_startup $cts_steps

set postcts_steps {block_start init_innovus run_opt_postcts_hold block_finish}
if {[get_feature report_inline]} { lappend postcts_steps report_postcts }
if {![get_feature report_inline]} { lappend postcts_steps schedule_postcts_report_postcts }
create_flow -name postcts -owner cadence -tool innovus -tool_options -disable_user_startup $postcts_steps

set route_steps {block_start init_innovus add_fillers run_route block_finish}
if {[get_feature report_inline]} { lappend route_steps report_postroute }
if {![get_feature report_inline]} { lappend route_steps schedule_route_report_postroute }
create_flow -name route -owner cadence -tool innovus -tool_options -disable_user_startup $route_steps

set postroute_steps {block_start init_innovus run_opt_postroute block_finish}
if {[get_feature report_inline]} { lappend postroute_steps report_postroute }
if {![get_feature report_inline]} { lappend postroute_steps schedule_postroute_report_postroute }
if {[get_feature report_lec]} { lappend postroute_steps innovus_to_lec }
lappend postroute_steps innovus_to_tempus innovus_to_quantus schedule_postroute_postroute_signoff
create_flow -name postroute -owner cadence -tool innovus -tool_options -disable_user_startup $postroute_steps
if {[get_feature opt_signoff]} {
  
  set opt_signoff_steps {block_start init_innovus run_opt_signoff block_finish}
  if {[get_feature report_inline]} { lappend opt_signoff_steps report_postroute }
  if {![get_feature report_inline]} { lappend opt_signoff_steps schedule_opt_signoff_report_postroute }
  lappend opt_signoff_steps innovus_to_tempus innovus_to_quantus schedule_opt_signoff_opt_signoff_signoff
  create_flow -name opt_signoff -owner cadence -tool innovus -tool_options -disable_user_startup $opt_signoff_steps
}

set eco_steps {eco_start init_innovus init_eco run_place_eco run_route_eco eco_finish}
if {[get_feature report_inline]} { lappend eco_steps report_postroute }
if {![get_feature report_inline]} { lappend eco_steps schedule_eco_report_postroute }
lappend eco_steps innovus_to_tempus innovus_to_quantus schedule_eco_eco_signoff
create_flow -name eco -owner cadence -tool innovus -tool_options -disable_user_startup $eco_steps

#=============================================================================
# Flow: Reporting Flows
#=============================================================================

create_flow -name report_synth -owner cadence -tool genus -tool_options -disable_user_startup {report_start init_genus report_area_genus report_late_summary_genus report_late_paths report_power_genus report_finish}
if {[get_feature report_lec]} {
  if {[get_feature report_lec]} { create_flow -name fv_genus -owner cadence -tool genus {genus_to_lec} }
  if {[get_feature report_lec]} { create_flow -name lec -owner cadence -tool flowtool {run_lec} }
}

create_flow -name report_floorplan -owner cadence -tool innovus -tool_options -disable_user_startup {report_start init_innovus report_check_design report_area_innovus report_route_drc report_finish}

create_flow -name report_prects -owner cadence -tool innovus -tool_options -disable_user_startup {report_start init_innovus report_check_design report_area_innovus report_late_summary_innovus report_late_paths report_power_innovus report_finish}

create_flow -name report_postcts -owner cadence -tool innovus -tool_options -disable_user_startup {report_start init_innovus report_check_design report_area_innovus report_early_summary_innovus report_early_paths report_late_summary_innovus report_late_paths report_clock_timing report_power_innovus report_finish}

set report_postroute_steps {report_start init_innovus report_check_design report_area_innovus report_early_summary_innovus report_early_paths}
if {[get_feature report_pba]} { lappend report_postroute_steps report_early_summary_pba }
if {[get_feature report_pba]} { lappend report_postroute_steps report_early_paths_pba }
lappend report_postroute_steps report_late_summary_innovus report_late_paths
if {[get_feature report_pba]} { lappend report_postroute_steps report_late_summary_pba }
if {[get_feature report_pba]} { lappend report_postroute_steps report_late_paths_pba }
lappend report_postroute_steps report_clock_timing report_power_innovus report_route_drc report_route_density report_finish
create_flow -name report_postroute -owner cadence -tool innovus -tool_options -disable_user_startup $report_postroute_steps
if {[get_feature report_lec]} {
  if {[get_feature report_lec]} { create_flow -name fv_innovus -owner cadence -tool innovus {innovus_to_lec} }
}
create_flow -name extract -owner cadence -tool flowtool {run_quantus}


create_flow -name init_tempus -owner cadence -tool tempus {init_tempus_yaml init_tempus_user}

set sta_steps {signoff_start init_tempus read_parasitics set_propagated_clocks update_timing check_timing report_late_summary report_late_paths}
if {[get_feature report_pba]} { lappend sta_steps report_late_summary_pba }
if {[get_feature report_pba]} { lappend sta_steps report_late_paths_pba }
lappend sta_steps report_early_summary report_early_paths
if {[get_feature report_pba]} { lappend sta_steps report_early_summary_pba }
if {[get_feature report_pba]} { lappend sta_steps report_early_paths_pba }
lappend sta_steps signoff_finish
create_flow -name sta -owner cadence -tool tempus -tool_options -disable_user_startup $sta_steps


create_flow -name init_voltus -owner cadence -tool voltus {init_voltus_yaml init_voltus_user}

if {[get_feature report_static_ir]} {
  if {[get_feature report_static_ir]} { create_flow -name ir_static -owner cadence -tool voltus -tool_options -disable_user_startup {signoff_start init_voltus read_parasitics add_switching_activity set_pg_nets report_power set_power_data set_rail_analysis report_rail signoff_finish} }
  
}
if {[get_feature report_dynamic_ir]} {
  if {[get_feature report_dynamic_ir]} { create_flow -name ir_dynamic -owner cadence -tool voltus -tool_options -disable_user_startup {signoff_start init_voltus read_parasitics add_switching_activity set_pg_nets report_power set_power_data set_rail_analysis report_rail signoff_finish} }
  
}
create_flow -name signoff -owner cadence -tool innovus {schedule_signoff_subflows}

#=============================================================================
# Flow: Toplevel Flows
#=============================================================================
create_flow -name synthesis -tool genus -owner cadence -skip_metric -tool_options -disable_user_startup {syn_generic syn_map syn_opt}
set implementation_steps {floorplan prects cts postcts route postroute}
if {[get_feature opt_signoff]} { lappend implementation_steps opt_signoff }

create_flow -name implementation -tool innovus -owner cadence -skip_metric -tool_options -disable_user_startup $implementation_steps

create_flow -name block -owner cadence -skip_metric {synthesis implementation}
set_db flow_top flow:block
