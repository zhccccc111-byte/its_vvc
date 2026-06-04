# ===================================================================
# ITS VVC Inverse Transform - Vivado Synthesis Script
# Target: Artix-7 xc7a200tfbg484-1 (WebPack license compatible)
# Clock: 500MHz (2ns period)
# ===================================================================

# Project settings
set project_name "its_vvc_synth"
set part "xc7a200tfbg484-1"
set top_module "its_top"
set rtl_dir "../rtl"
set sim_dir "../sim"
set constraint_dir "."

# Copy hex files to project directory
file copy -force "$sim_dir/rom_coeffs.hex" "./rom_coeffs.hex"
file copy -force "$sim_dir/lfnst_coeffs.hex" "./lfnst_coeffs.hex"

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

# Synthesis settings
# Use default strategy for initial synthesis run

# Run synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Open synthesized design
open_run synth_1

# Generate reports
report_utilization -file utilization_report.rpt
report_timing_summary -file timing_report.rpt
report_power -file power_report.rpt

# Print summary
puts "========================================"
puts "Synthesis Complete"
puts "========================================"
puts "Utilization report: utilization_report.rpt"
puts "Timing report: timing_report.rpt"
puts "Power report: power_report.rpt"

close_project
