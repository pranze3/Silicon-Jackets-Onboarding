# Minimum site dimensions: 0.46 units in X direction, 4.14 units in Y direction
set sitesx 0.46  ;# Set the site width (X dimension) to 0.46
set sitesy 4.14  ;# Set the site height (Y dimension) to 4.14

# Print a message indicating the start of the floorplan script
puts "RUNNING FLOORPLAN.TCL"

# Set the snapping of the floorplan to align with block grid instances
set_db floorplan_snap_block_grid inst

# Create the core area of the floorplan with dimensions based on site sizes
# Assuming we have approximately a 100x100 um box as the placeholder floorplan 
# The floorplan width is calculated as sitesx * 220 and height as sitesy * 25
create_floorplan -core_size [expr {$sitesx*2100}] [expr {$sitesy*300}] 30 30 30 30

# Initialize core rows for placement within the floorplan
init_core_rows

# Retrieve and store the design's bounding box dimensions (dx and dy)
set dx [get_db designs .bbox.dx]  ;# Get the design's X dimension (width)
set dy [get_db designs .bbox.dy]  ;# Get the design's Y dimension (height)

# REQUIRED: Macro Placement
# --------------------------------------------------------------------------
# SRAM dimensions: 0.683um x 0.416um
set sram_width 0.683
set sram_height 0.416

# Adjusted placement for better separation and symmetry
set x1 145.0
set y1 165.0
place_inst sram_A $x1 $y1 -fixed

set x2 145.0
set y2 695.0
place_inst sram_B $x2 $y2 -fixed
# --------------------------------------------------------------------------

# REQUIRED: Macro Protection
# --------------------------------------------------------------------------
# Create placement halo (keeps cells away)
create_place_halo -insts sram_A -halo_deltas 5 5 5 5
create_place_halo -insts sram_B -halo_deltas 5 5 5 5

# Create routing blockages around SRAMs (except met5 for power)
set halo 5.0

# Blockage for sram_A
set blk_x1 [expr {$x1 - $halo}]
set blk_y1 [expr {$y1 - $halo}]
set blk_x2 [expr {$x1 + $sram_width + $halo}]
set blk_y2 [expr {$y1 + $sram_height + $halo}]
create_route_blockage -rects [list [list $blk_x1 $blk_y1 $blk_x2 $blk_y2]] -layers {met1 met2 met3 met4}

# Blockage for sram_B
set blk_x1 [expr {$x2 - $halo}]
set blk_y1 [expr {$y2 - $halo}]
set blk_x2 [expr {$x2 + $sram_width + $halo}]
set blk_y2 [expr {$y2 + $sram_height + $halo}]
create_route_blockage -rects [list [list $blk_x1 $blk_y1 $blk_x2 $blk_y2]] -layers {met1 met2 met3 met4}
# --------------------------------------------------------------------------

## Add Power Grid
# Source an external script to add a power grid to the design
source ./scripts/add_power.tcl

## Add Pins
# Source an external script to add pins to the design
source ./scripts/add_pins.tcl

# Align all elements in the floorplan to the nearest grid point
snap_floorplan -all

# Conditional block for optional macro placement and optimization (currently disabled)
if {0} {
  # Perform detailed macro placement
  place_macro_detail
  
  # Disable global placement of IO pins during optimization
  set_db place_global_place_io_pins false
  
  # Set a seed for global placement optimization
  set_db place_opt_run_global_place seed
  
  # Run placement optimization on the design
  place_opt_design
}

# Print a message indicating the end of the floorplan script
puts "ENDING FLOORPLAN.TCL"
