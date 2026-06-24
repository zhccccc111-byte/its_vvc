# ===================================================================
# ITS 500MHz Wrapper OOC Synthesis — UltraScale+ target
# Part: Kintex UltraScale+ xcku5p-ffvb676-2-e
# Usage: vivado -mode batch -source its_wrapper_500_ooc_usp.tcl
# ===================================================================

create_project -in_memory -part xcku5p-ffvb676-2-e -force

set rtl_dir [file dirname [file normalize [info script]]]/../rtl

# Set include path and defines BEFORE adding files
set_property include_dirs [list [file normalize $rtl_dir]] [current_fileset]
set_property verilog_define {SYNTHESIS} [current_fileset]

# Add all RTL files as SystemVerilog (import/package syntax requires -sv)
set sv_files [glob -nocomplain [file join $rtl_dir *.v]]
add_files -fileset sources_1 $sv_files
set_property file_type {SystemVerilog} [get_files $sv_files]

set xdc_dir [file dirname [file normalize [info script]]]
read_xdc [file join $xdc_dir timing_wrapper_500.xdc]

puts "=========================================="
puts " OOC synthesis: its_top_500_wrapper"
puts " Part: UltraScale+ (xcku5p-2)"
puts " clk_if = 100MHz, clk_core = 500MHz"
puts "=========================================="

synth_design -top its_top_500_wrapper -mode out_of_context -flatten_hierarchy rebuilt

report_timing_summary -file [file join $xdc_dir wrapper_500_timing_synth_usp.rpt]
report_utilization -file [file join $xdc_dir wrapper_500_utilization_synth_usp.rpt]

puts "Running opt_design..."
opt_design

puts "Running place_design..."
place_design -directive Explore

puts "Running phys_opt_design..."
phys_opt_design -directive AggressiveExplore

puts "Running route_design..."
route_design -directive Explore

puts "Running post-route phys_opt..."
phys_opt_design -directive AggressiveExplore
phys_opt_design -directive AlternateFlowWithRetiming
# Hold fix: set min input delay to ensure hold margin
# Input ports arrive at pad, clock arrives at FF with skew.
# Increasing min input delay from 0.100 to 0.200 adds hold margin.

puts "Generating post-impl reports..."
report_timing_summary -file [file join $xdc_dir wrapper_500_timing_impl_usp.rpt]
report_timing -setup -nworst 20 -file [file join $xdc_dir wrapper_500_timing_setup_paths_usp.rpt]
report_timing -hold  -nworst 20 -file [file join $xdc_dir wrapper_500_timing_hold_paths_usp.rpt]
write_checkpoint -force [file join $xdc_dir its_wrapper_500_ooc_usp.dcp]
report_utilization -file [file join $xdc_dir wrapper_500_utilization_impl_usp.rpt]
report_power -file [file join $xdc_dir wrapper_500_power_impl_usp.rpt]

# Check primitive inference
puts "=========================================="
puts " Checking primitive inference..."
puts "=========================================="
set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME =~ DSP48E2*}]]
set bram_count [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB36E2*}]]
set uram_count [llength [get_cells -hierarchical -filter {REF_NAME =~ URAM289*}]]
puts "DSP48E2: $dsp_count"
puts "RAMB36E2: $bram_count"
puts "URAM289: $uram_count"

# Check for CDC timing violations (should be zero with clock_groups)
puts "=========================================="
puts " Checking cross-domain paths..."
puts "=========================================="
set cross_paths [get_timing_paths -from [get_clocks clk_if] -to [get_clocks clk_core] -quiet]
if {[llength $cross_paths] > 0} {
    puts "WARNING: [llength $cross_paths] cross-domain paths found (should be 0)"
    report_timing -from [get_clocks clk_if] -to [get_clocks clk_core] -nworst 5 \
        -file [file join $xdc_dir wrapper_500_cross_domain_violations.rpt]
} else {
    puts "OK: No cross-domain timing paths (clock_groups isolation working)"
}

puts "=========================================="
puts " Wrapper OOC synthesis complete."
puts "=========================================="
