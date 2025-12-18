# Generated using: Flowkit 23.10-a010_1
################################################################################
# This file contains content which is used to customize the refererence flow
# process.  Commands such as 'create_flow', 'create_flow_step' and 'edit_flow'
# would be most prevalent.  For example:
#
# create_flow_step -name write_sdf -owner user -write_db {
#   write_sdf [get_db flow_report_directory]/[get_db flow_report_name].sdf
# }
#
# edit_flow -after flow_step:innovus_report_late_timing -append flow_step:write_sdf
#
################################################################################

################################################################################
# FLOW METRIC HEADER SETTINGS
################################################################################
set_metric_header -name run_name -value [get_db flow_run_tag]
set_metric_header -name run_remark -value [get_db flow_remark]

################################################################################
# FLOW CPU AND HOST SETTINGS
################################################################################
create_flow_step -name init_mcpu -owner flow {
  apply {{} {
    # Multi host/cpu attributes
    #-----------------------------------------------------------------------------
    # The FLOWTOOL_NUM_CPUS is an environment variable which should be exported by
    # the specified dist script.  This connects the number of CPUs being reserved
    # for batch jobs with the current flow scripts.  The LSB_MAX_NUM_PROCESSORS is
    # a typical environment variable exported by distribution platforms and is
    # useful for ensuring all interactive jobs are using the reserved amount of CPUs.
    if {[info exists ::env(FLOWTOOL_NUM_CPUS)]} {
      set max_cpus $::env(FLOWTOOL_NUM_CPUS)
    } elseif {[info exists ::env(LSB_MAX_NUM_PROCESSORS)]} {
      set max_cpus $::env(LSB_MAX_NUM_PROCESSORS)
    } else {
      set max_cpus 1
    }
    switch -glob [get_db program_short_name] {
      default       {}
      joules*       -
      genus*        -
      innovus*      -
      tempus*       -
      voltus*       { set_multi_cpu_usage -verbose -local_cpu $max_cpus }
    }
if {[get_feature opt_signoff]} {
      if {[is_flow -inside flow:opt_signoff]} {
        set_multi_cpu_usage -verbose -remote_host 1
        set_multi_cpu_usage -verbose -cpu_per_remote_host 16
        set_distributed_hosts -local
      }
}
  }}
}
edit_flow -after Cadence.plugin.flowkit.read_db.pre -append flow_step:init_mcpu
edit_flow -after Cadence.plugin.flowkit.read_db.post -append flow_step:init_mcpu

################################################################################
# FLOW CUSTOMIZATIONS / FLOW STEP ADDITIONS
################################################################################

##############################################################################
# STEP report_late_paths
##############################################################################
create_flow_step -name report_late_paths -owner flow -exclude_time_metric {
  #- Reports that show detailed timing with Graph Based Analysis (GBA)
  report_timing -max_paths 5   -nworst 1 -path_type endpoint        > [file join [get_db flow_report_directory] [get_db flow_report_name] setup.endpoint.rpt]
  report_timing -max_paths 1   -nworst 1 -path_type full_clock -net > [file join [get_db flow_report_directory] [get_db flow_report_name] setup.worst.rpt]
  report_timing -max_paths 500 -nworst 1 -path_type full_clock      > [file join [get_db flow_report_directory] [get_db flow_report_name] setup.gba.rpt]
  if {![get_feature report_pba]} {
    
    #- Reports that show detailed timing with Path Based Analysis (PBA)
    if {[is_flow -quiet -inside flow:sta]} {
      report_timing -max_paths 50 -nworst 1 -path_type full_clock -retime path_slew_propagation > [file join [get_db flow_report_directory] [get_db flow_report_name] setup.pba.rpt]
    }
  }
}

##############################################################################
# STEP report_early_paths
##############################################################################
create_flow_step -name report_early_paths -owner flow -exclude_time_metric {
  #- Reports that show detailed early timing with Graph Based Analysis (GBA)
  report_timing -early -max_paths 5   -nworst 1 -path_type endpoint        > [file join [get_db flow_report_directory] [get_db flow_report_name] hold.endpoint.rpt]
  report_timing -early -max_paths 1   -nworst 1 -path_type full_clock -net > [file join [get_db flow_report_directory] [get_db flow_report_name] hold.worst.rpt]
  report_timing -early -max_paths 500 -nworst 1 -path_type full_clock      > [file join [get_db flow_report_directory] [get_db flow_report_name] hold.gba.rpt]
  if {![get_feature report_pba]} {
    
    #- Reports that show detailed timing with Path Based Analysis (PBA)
    if {[is_flow -quiet -inside flow:sta]} {
      report_timing -early -max_paths 50 -nworst 1 -path_type full_clock -retime path_slew_propagation > [file join [get_db flow_report_directory] [get_db flow_report_name] hold.pba.rpt]
    }
  }
}
if {[get_feature report_pba]} {
  
  ############################################################################
  # STEP report_late_summary_pba
  ############################################################################
  create_flow_step -name report_late_summary_pba -owner flow -exclude_time_metric -categories setup {
    report_timing_summary -checks {setup} -retime path_slew_propagation -retime_mode exhaustive > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]setup.pba.analysis_summary.rpt]
    report_timing_summary -checks {setup} -retime path_slew_propagation -retime_mode exhaustive -expand_views > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]setup.pba.view_summary.rpt]
  }
  
  ############################################################################
  # STEP report_late_paths_pba
  ############################################################################
  create_flow_step -name report_late_paths_pba -owner flow -exclude_time_metric {
    #- Reports that show detailed early timing with Path Based Analysis (PBA)
    report_timing -max_paths 50 -nworst 1 -path_type full_clock -retime path_slew_propagation -retime_mode exhaustive > [file join [get_db flow_report_directory] [get_db flow_report_name] setup.pba.rpt]
  }
  
  ############################################################################
  # STEP report_early_summary_pba
  ############################################################################
  create_flow_step -name report_early_summary_pba -owner flow -exclude_time_metric -categories hold {
    report_timing_summary -checks {hold} -retime path_slew_propagation -retime_mode exhaustive > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]hold.pba.analysis_summary.rpt]
    report_timing_summary -checks {hold} -retime path_slew_propagation -retime_mode exhaustive -expand_views > [file join [get_db flow_report_directory] [get_db flow_report_name] [get_db flow_report_prefix]hold.pba.view_summary.rpt]
  }
  
  ############################################################################
  # STEP report_early_paths_pba
  ############################################################################
  create_flow_step -name report_early_paths_pba -owner flow -exclude_time_metric {
    #- Reports that show detailed early timing with Path Based Analysis (PBA)
    report_timing -early -max_paths 50 -nworst 1 -path_type full_clock -retime path_slew_propagation -retime_mode exhaustive > [file join [get_db flow_report_directory] [get_db flow_report_name] hold.pba.rpt]
  }
}
if {[get_feature report_lec]} {
  
  ############################################################################
  # STEP genus_to_lec
  ############################################################################
  create_flow_step -name genus_to_lec -owner flow {
    apply {{} {
      #- create output location
      set design  [get_db current_design .name]
    
      #- write dofile for LEC
      if {[is_flow -inside flow:syn_map]} {
        write_do_lec \
          -top $design \
          -golden_design rtl \
          -revised_design fv_map \
          -logfile [file join [get_db flow_log_directory] lec.[get_db flow_report_name].log] \
          -checkpoint [file join [get_db current_design .verification_directory] lec.[get_db flow_report_name].ckpt] \
          < PLACEHOLDER: LEC SYN_MAP SCRIPT OPTIONS > \
          > [file join [get_db current_design .verification_directory] lec.[get_db flow_report_name].do]
      } else {
        set out_dir [file join [get_db flow_db_directory] [get_db flow_report_name]]
        file mkdir $out_dir
        write_do_lec \
          -top $design \
          -golden_design fv_map \
          -revised_design [file join ${out_dir}.cdb cmn $design.v.gz] \
          -logfile [file join [get_db flow_log_directory] lec.[get_db flow_report_name].log] \
          -checkpoint [file join [get_db current_design .verification_directory] lec.[get_db flow_report_name].ckpt] \
          < PLACEHOLDER: LEC SYN_OPT SCRIPT OPTIONS > \
          > [file join [get_db current_design .verification_directory] lec.[get_db flow_report_name].do]
      }
    }}
    #- schedule the LEC flow
    #FlowtoolPredictHint ArgumentRandomise -branch
    schedule_flow \
      -flow lec \
      -branch [get_db flow_report_name] \
      -include_in_metrics \
      -no_db \
      -no_sync \
      -tool_options "-- -nogui -lp -do [file join [get_db current_design .verification_directory] lec.[get_db flow_report_name].do]"
  }
}
