connect_global_net VDD -type pg_pin -pin_base_name vccd1
connect_global_net VSS -type pg_pin -pin_base_name vssd1
connect_global_net VDD -type pg_pin -pin_base_name VDD
connect_global_net VSS -type pg_pin -pin_base_name VSS

connect_global_net VDD -type tie_hi -all
connect_global_net VSS -type tie_lo -all

# connect SRAM power to Chip power
set mem_blocks [get_db [get_db insts *sram*] .name]
foreach i $mem_blocks {
    puts $i
    connect_global_net VDD -type pgpin -pin vccd1 -sinst $i -override
    connect_global_net VSS -type pgpin -pin vssd1 -sinst $i -override
}
add_rings -nets {VDD VSS} -layer {top met5 bottom met5 left met4 right met4} -width {top 4.8 bottom 4.8 left 4.8 right 4.8} -spacing {top 4.8 bottom 4.8 left 4.8 right 4.8} -offset {top 2 bottom 2 left 2 right 2} -center 0 -threshold 0.4 -jog_distance 0.4 -snap_wire_center_to_grid none

route_special -connect { core_pin } -block_pin_target { nearest_target } -core_pin_target { first_after_row_end } -core_pin_layer { met1 } -block_pin_layer_range { met3 met4 } -delete_existing_routes -nets { VDD VSS }

add_stripes -nets {VDD VSS} -layer met5 -direction horizontal -width 3 -spacing 20 -set_to_set_distance 50 -start_from bottom -start_offset 5 -switch_layer_over_obs false -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit met5 -pad_core_ring_bottom_layer_limit met1 -block_ring_top_layer_limit met5 -block_ring_bottom_layer_limit met4 -use_wire_group 0 -snap_wire_center_to_grid none

add_stripes -nets {VDD VSS} -layer met4 -direction vertical -width 3 -spacing 20 -set_to_set_distance 50 -start_from left -start_offset 5 -switch_layer_over_obs false -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit met5 -pad_core_ring_bottom_layer_limit met1 -block_ring_top_layer_limit met5 -block_ring_bottom_layer_limit met4 -use_wire_group 0 -snap_wire_center_to_grid none


#delete_route_halos -all_blocks