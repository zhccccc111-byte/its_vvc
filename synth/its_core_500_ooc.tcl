# ===================================================================
# ITS Core 500MHz OOC Synthesis Script
# Out-of-context synthesis to measure internal timing at 500MHz
# Usage: vivado -mode batch -source its_core_500_ooc.tcl
# ===================================================================

# Project setup (in-memory, no disk project)
create_project -in_memory -part xc7a200tfbg484-3 -force

# Read RTL sources
set rtl_dir [file dirname [file normalize [info script]]]/../rtl
read_verilog [file join $rtl_dir its_core_500.v]
read_verilog [file join $rtl_dir its_transform_engine.v]
read_verilog [file join $rtl_dir its_mac.v]
read_verilog [file join $rtl_dir its_rom.v]
read_verilog [file join $rtl_dir its_lfnst.v]
read_verilog [file join $rtl_dir its_lfnst_rom.v]

# Read constraints
set xdc_dir [file dirname [file normalize [info script]]]
read_xdc [file join $xdc_dir timing_core_500.xdc]

# OOC synthesis
puts "=========================================="
puts " Starting OOC synthesis: its_core_500"
puts " Target: 500MHz (2ns period)"
puts "=========================================="

synth_design -top its_core_500 -mode out_of_context -flatten_hierarchy rebuilt

# Post-synthesis timing
report_timing_summary -file [file join $xdc_dir core_500_timing_synth.rpt]
report_utilization -file [file join $xdc_dir core_500_utilization_synth.rpt]

# Optimization
puts "Running opt_design..."
opt_design

puts "Running place_design..."
place_design -directive Explore

puts "Running phys_opt_design..."
phys_opt_design -directive AggressiveExplore

puts "Running route_design..."
route_design -directive Explore

# Post-implementation reports
puts "Generating reports..."
report_timing_summary -file [file join $xdc_dir core_500_timing_impl.rpt]
report_timing -setup -nworst 20 -file [file join $xdc_dir core_500_timing_setup_paths.rpt]
report_timing -setup -nworst 20 -unique_pins -file [file join $xdc_dir core_500_timing_unique_paths.rpt]
write_checkpoint -force [file join $xdc_dir its_core_500_ooc.dcp]
report_timing -hold -nworst 10 -file [file join $xdc_dir core_500_timing_hold_paths.rpt]
report_utilization -file [file join $xdc_dir core_500_utilization_impl.rpt]
report_power -file [file join $xdc_dir core_500_power_impl.rpt]
report_methodology -file [file join $xdc_dir core_500_methodology.rpt]

puts "=========================================="
puts " OOC synthesis complete."
puts " Reports saved to synth/core_500_*.rpt"
puts "=========================================="
