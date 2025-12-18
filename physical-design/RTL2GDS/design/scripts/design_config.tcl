# Generated using: Flowkit 23.10-a010_1
################################################################################
# This file contains 'create_flow_step' content for steps which are required
# in an implementation flow, but whose contents are specific.  Review  all
# <PLACEHOLDER> content and replace with commands and options more appropriate
# for the design being implemented. Any new flowstep definitions should be done
# using the 'flow_config.tcl' file.
################################################################################

##############################################################################
# STEP set_dont_use
##############################################################################
create_flow_step -name set_dont_use -owner design {
  #- disable base_cell usage during optimization
  <%? {dont_use_cells} return "foreach base_cell_name [list [get_flow_config dont_use_cells]] {set_db \[get_db base_cells \$base_cell_name\] .dont_use true}" %>
}

##############################################################################
# STEP read_hdl

##############################################################################
create_flow_step -name read_hdl -owner design {
  set hdl_file_list [list ../pipeline_src/calculator_pkg.sv \
			  ../pipeline_src/full_adder.sv \
  			  ../pipeline_src/adder32.sv \
			  ../pipeline_src/result_buffer.sv \
  			  ../pipeline_src/controller.sv \
		          ../pipeline_src/top_lvl.sv \
			  ]
  read_hdl -sv $hdl_file_list
  elaborate top_lvl
}
#Example of reading in verilog file
#create_flow_step -name read_hdl -owner design {
#  #- read and elaborate design
#  read_hdl {../SiliconJackets/designs/spm.v}
#  elaborate spm
#}
#Example of reading in multiple systemverilog files 
#create_flow_step -name read_hdl -owner design {
#  set hdl_file_list [list ../../src/rtl/noInterfaces/top.sv \
#            ../../src/rtl/noInterfaces/topLevelControl.sv \
#            ../../src/rtl/noInterfaces/PE.sv ]
#  read_hdl -sv $hdl_file_list
#  elaborate top
#}

##############################################################################
# STEP init_floorplan
##############################################################################
create_flow_step -name init_floorplan -owner design {
  #- initialize floorplan object using DEF and/or floorplan files
  <%? {init_floorplan_file} return "read_floorplan [get_flow_config init_floorplan_file]" %>
  <%? {init_floorplan_tcl} return "source [get_flow_config init_floorplan_tcl]" %>
  <%? {init_def_files} return "foreach def_file [list [get_flow_config init_def_files]] { read_def \$def_file }" %>
} -check {
  foreach file [get_flow_config -quiet init_floorplan_file] {
    check "[file exists $file] && [file readable $file]" "The floorplan file: $file was not found or is not readable."
  }
  foreach file [get_flow_config -quiet init_floorplan_tcl] {
    check "[file exists $file] && [file readable $file]" "The floorplan tcl file: $file was not found or is not readable."
  }
  foreach file [get_flow_config -quiet init_def_files] {
    check "[file exists $file] && [file readable $file]" "The def file: $file was not found or is not readable."
  }
}

##############################################################################
# STEP add_clock_route_types
##############################################################################
create_flow_step -name add_clock_route_types -owner design {
  #- define route_types and/or route_rules
  #create_route_type -name cts_top   < PLACEHOLDER: CLOCK TOP ROUTE RULE >
  #create_route_type -name cts_trunk < PLACEHOLDER: CLOCK TRUNK ROUTE RULE >
  #create_route_type -name cts_leaf  < PLACEHOLDER: CLOCK LEAF ROUTE RULE >
  
  set_db cts_route_type_top  default
  set_db cts_route_type_trunk default
  set_db cts_route_type_leaf  default
}

if {[get_feature report_static_ir] || [get_feature report_dynamic_ir]} {
  ##############################################################################
  # STEP set_pg_nets
  ##############################################################################
  create_flow_step -name set_pg_nets -owner design {
    set_pg_nets                         "VDD VSS"
  }
  
  ############################################################################
  # STEP set_rail_analysis
  ############################################################################
  create_flow_step -name set_rail_analysis -owner design {
    if {[get_feature report_static_ir]} {
      if {[is_flow -inside flow:ir_static]} {
        set_rail_analysis_config \
          -report_power_in_parallel false \
          -accuracy hd \
          -eiv_pin_based_report true \
          -enable_manufacturing_effects true \
          -enable_rlrp_analysis true \
          -method static \
          -voltage_source_search_distance 50 \
          -work_directory_name work.ir_static \
          #< PLACEHOLDER: STATIC SET_RAIL_ANALYSIS_CONFIG OPTIONS >
      }
    }
    if {[get_feature report_dynamic_ir]} {
      if {[is_flow -inside flow:ir_dynamic]} {
        set_rail_analysis_config \
          -report_power_in_parallel false \
          -accuracy hd \
          -eiv_detail_report true \
          -eiv_pin_based_report true \
          -enable_manufacturing_effects true \
          -enable_rlrp_analysis true \
          -method dynamic \
          -voltage_source_search_distance 50 \
          -work_directory_name work.ir_dynamic \
          #< PLACEHOLDER: DYNAMIC SET_RAIL_ANALYSIS_CONFIG OPTIONS >
      }
    }
    
    set_rail_analysis_domain\  
	-ground_nets VSS \
    -power_nets VDD	
    
    #set_power_pads                      < PLACEHOLDER: SET_POWER_PADS OPTIONS >
  }
  
  ############################################################################
  # STEP set_power_data
  ############################################################################
  create_flow_step -name set_power_data -owner design {
    set_power_data -format current
  }
}
if {[get_feature report_static_ir] || [get_feature report_dynamic_ir]} {
  
  ############################################################################
  # STEP add_switching_activity
  ############################################################################
  create_flow_step -name add_switching_activity -owner design {
    set_default_switching_activity 0.5
    set_switching_activity -clock [get_clocks *CLK*]
    #read_activity_file                  < PLACEHOLDER: READ ACTIVITY FILE OPTIONS >
    
    propagate_activity
  }
}

##############################################################################
#STEP write_output_files
##############################################################################
create_flow_step -name write_output_files -owner design {
    write_stream -merge [get_flow_config std_cells]/gds/sky130_scl_9T.gds ./output/[get_db designs .name].gds
    write_lef_abstract ./output/[get_db designs .name].lef
    redirect -variable views {report_analysis_views}
    foreach {-> view} [regexp -all -inline {Analysis View:\s+(\S+)} $views] {
        set_analysis_view -dynamic $view -leakage $view -setup $view -hold $view
        write_timing_model ./output/[get_db designs .name]__${view}.lib -view $view -post_check
    }
}


##############################################################################
#STEP write_output_screenshot
##############################################################################
create_flow_step -name write_output_screenshot -owner design {
    set inputstring [get_db flow_starting_db]
    set stepname [lindex $inputstring [expr {[llength stepname]}]]
    set filename [file tail $stepname]
    set rootname [file rootname $filename]
    set outfile "./output/screenshots/${rootname}.gif"
    # Define the directory name
    set dirName "output/screenshots"

    # Check if the directory exists
    if {![file exists $dirName]} {
    # Create the directory if it doesn't exist
      file mkdir $dirName
      puts "Directory '$dirName' created."
    } else {
         puts "Directory '$dirName' already exists."
    }
    write_to_gif $outfile
}
