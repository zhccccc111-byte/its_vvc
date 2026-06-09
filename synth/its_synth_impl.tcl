# ===================================================================
# ITS VVC Inverse Transform - Full Implementation Script
# Target: Artix-7 xc7a200tfbg484-3 (speed grade -3)
# Clock: 100MHz (10ns period) - baseline
# Strategy: Performance_ExplorePostRoutePhysOpt
# ===================================================================

# Project settings
set project_name "its_vvc_synth"
set part "xc7a200tfbg484-3"
set top_module "its_top"
set rtl_dir "../rtl"
set constraint_dir "."

# Copy hex files to project directory
file copy -force "$rtl_dir/rom_coeffs.hex" "./rom_coeffs.hex"
file copy -force "$rtl_dir/lfnst_coeffs.hex" "./lfnst_coeffs.hex"

# Create project
create_project $project_name ./$project_name -part $part -force

# Add RTL source files
set rtl_files [list \
    "$rtl_dir/its_mac.v" \
    "$rtl_dir/its_rom.v" \
    "$rtl_dir/its_lfnst_rom.v" \
    "$rtl_dir/its_transform_engine.v" \
    "$rtl_dir/its_lfnst.v" \
    "$rtl_dir/its_top.v" \
]

add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse "$constraint_dir/timing.xdc"

# Set top module
set_property top $top_module [current_fileset]

# Use aggressive timing optimization strategy
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

# Run synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check synthesis results
open_run synth_1
report_timing_summary -file timing_synth.rpt
report_utilization -file utilization_synth.rpt

# Run implementation (place & route)
launch_runs impl_1 -jobs 4 -to_step route_design
wait_on_run impl_1

# Open implemented design
open_run impl_1

# Generate reports
report_utilization -file utilization_impl.rpt
report_timing_summary -file timing_impl.rpt
report_power -file power_impl.rpt

# Print summary
puts "========================================"
puts "Implementation Complete"
puts "Target: $part"
puts "========================================"
puts "Utilization report: utilization_impl.rpt"
puts "Timing report: timing_impl.rpt"
puts "Power report: power_impl.rpt"

close_project
