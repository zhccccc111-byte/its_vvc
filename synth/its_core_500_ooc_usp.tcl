# ===================================================================
# ITS Core 500MHz OOC Synthesis — UltraScale+ target
# Part: Kintex UltraScale+ xcku5p-ffvb676-2-e
# Usage: vivado -mode batch -source its_core_500_ooc_usp.tcl
# ===================================================================

create_project -in_memory -part xcku5p-ffvb676-2-e -force

set rtl_dir [file dirname [file normalize [info script]]]/../rtl
read_verilog [file join $rtl_dir its_core_500.v]
read_verilog [file join $rtl_dir its_transform_engine.v]
read_verilog [file join $rtl_dir its_mac.v]
read_verilog [file join $rtl_dir its_rom.v]
read_verilog [file join $rtl_dir its_lfnst.v]
read_verilog [file join $rtl_dir its_lfnst_rom.v]

set_property verilog_define {SYNTHESIS} [current_fileset]
set_property include_dirs [list $rtl_dir] [current_fileset]

set xdc_dir [file dirname [file normalize [info script]]]
read_xdc [file join $xdc_dir timing_core_500.xdc]

puts "=========================================="
puts " OOC synthesis: UltraScale+ (xcku5p-2)"
puts " Target: 500MHz (2ns period)"
puts "=========================================="

synth_design -top its_core_500 -mode out_of_context -flatten_hierarchy rebuilt

report_timing_summary -file [file join $xdc_dir core_500_timing_synth_usp.rpt]
report_utilization -file [file join $xdc_dir core_500_utilization_synth_usp.rpt]

puts "Running opt_design..."
opt_design

puts "Running place_design..."
place_design -directive Explore

puts "Running phys_opt_design..."
phys_opt_design -directive AggressiveExplore

puts "Running route_design..."
route_design -directive Explore

puts "Generating reports..."
report_timing_summary -file [file join $xdc_dir core_500_timing_impl_usp.rpt]
report_timing -setup -nworst 20 -file [file join $xdc_dir core_500_timing_setup_paths_usp.rpt]
write_checkpoint -force [file join $xdc_dir its_core_500_ooc_usp.dcp]
report_utilization -file [file join $xdc_dir core_500_utilization_impl_usp.rpt]
report_power -file [file join $xdc_dir core_500_power_impl_usp.rpt]

# Check DSP/RAM inference
puts "=========================================="
puts " Checking primitive inference..."
puts "=========================================="
set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME =~ DSP48E2*}]]
set bram_count [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB36E2*}]]
set uram_count [llength [get_cells -hierarchical -filter {REF_NAME =~ URAM289*}]]
puts "DSP48E2: $dsp_count"
puts "RAMB36E2: $bram_count"
puts "URAM289: $uram_count"

puts "=========================================="
puts " UltraScale+ OOC synthesis complete."
puts "=========================================="
