# Set the status of all partition pins to "unplaced"
# This ensures that all pins in the partition are marked as not yet placed in the design.
set_partition_pin_status -pins * -status unplaced

# Edit pin placement properties for all pins
# - `-fixed_pin`: Marks the pins as fixed, meaning their position will not change during optimization.
# - `-pin *`: Applies the changes to all pins in the design.
# - `-pattern fill_optimised`: Specifies a placement pattern for the pins, optimized for filling.
# - `-layer {2 3 4 5}`: Assigns the pins to metal layers 2, 3, 4, and 5 for routing purposes.
# - `-start {10 10}` and `-end {10 10}`: Sets both the start and end coordinates of pin placement to (10, 10), to spread pins over all edges of the rectangular floorplan.
edit_pin -fixed_pin -pin * -pattern fill_optimised -layer {2 3 4 5} -start {10 10} -end {10 10}

# Disable batch mode for pin assignment edits
# When `assign_pins_edit_in_batch` is set to false, pin edits are applied immediately rather than being queued for batch processing.
set_db assign_pins_edit_in_batch false

