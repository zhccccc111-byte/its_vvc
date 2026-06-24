# ===================================================================
# ITS Core 500MHz Physical Optimization Comparison
# Tests different place/phys_opt directives to improve timing
# Usage: vivado -mode batch -source its_core_500_phys_opt.tcl
# ===================================================================

create_project -in_memory -part xc7a200tfbg484-3 -force

set rtl_dir [file dirname [file normalize [info script]]]/../rtl

# Set include path and defines BEFORE adding files
set_property include_dirs [list [file normalize $rtl_dir]] [current_fileset]
set_property verilog_define {SYNTHESIS} [current_fileset]

set sv_files [list \
    [file join $rtl_dir its_pkg.v] \
    [file join $rtl_dir its_core_500.v] \
    [file join $rtl_dir its_transform_engine.v] \
    [file join $rtl_dir its_mac.v] \
    [file join $rtl_dir its_rom.v] \
    [file join $rtl_dir its_lfnst.v] \
    [file join $rtl_dir its_lfnst_rom.v] \
]
add_files -fileset sources_1 $sv_files
set_property file_type {SystemVerilog} [get_files $sv_files]

set xdc_dir [file dirname [file normalize [info script]]]
read_xdc [file join $xdc_dir timing_core_500.xdc]

puts "=========================================="
puts " Starting OOC synthesis: its_core_500"
puts "=========================================="

synth_design -top its_core_500 -mode out_of_context -flatten_hierarchy rebuilt
opt_design

# Save post-synth checkpoint
write_checkpoint -force [file join $xdc_dir cp_synth.dcp]

# ============================================================
# Strategy A: Explore (baseline)
# ============================================================
puts "\n=== Strategy A: Explore (baseline) ==="
open_checkpoint [file join $xdc_dir cp_synth.dcp]
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
report_timing_summary -file [file join $xdc_dir timing_A_explore.rpt]
report_utilization -file [file join $xdc_dir util_A_explore.rpt]
write_checkpoint -force [file join $xdc_dir cp_A.dcp]
close_design

# ============================================================
# Strategy B: ExtraNetDelay_high + AggressiveExplore
# ============================================================
puts "\n=== Strategy B: ExtraNetDelay_high + AggressiveExplore ==="
open_checkpoint [file join $xdc_dir cp_synth.dcp]
place_design -directive ExtraNetDelay_high
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
report_timing_summary -file [file join $xdc_dir timing_B_extradelay.rpt]
write_checkpoint -force [file join $xdc_dir cp_B.dcp]
close_design

# ============================================================
# Strategy C: SSI_SpreadLogic_high + AggressiveExplore
# ============================================================
puts "\n=== Strategy C: SSI_SpreadLogic_high + AggressiveExplore ==="
open_checkpoint [file join $xdc_dir cp_synth.dcp]
place_design -directive SSI_SpreadLogic_high
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
report_timing_summary -file [file join $xdc_dir timing_C_spreadlogic.rpt]
write_checkpoint -force [file join $xdc_dir cp_C.dcp]
close_design

# ============================================================
# Strategy D: Explore + AggressiveFanoutOpt
# ============================================================
puts "\n=== Strategy D: Explore + AggressiveFanoutOpt ==="
open_checkpoint [file join $xdc_dir cp_synth.dcp]
place_design -directive Explore
phys_opt_design -directive AggressiveFanoutOpt
route_design -directive Explore
report_timing_summary -file [file join $xdc_dir timing_D_fanoutopt.rpt]
write_checkpoint -force [file join $xdc_dir cp_D.dcp]
close_design

# ============================================================
# Strategy E: Explore + AggressiveExplore x2
# ============================================================
puts "\n=== Strategy E: Explore + AggressiveExplore x2 ==="
open_checkpoint [file join $xdc_dir cp_synth.dcp]
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
report_timing_summary -file [file join $xdc_dir timing_E_double_physopt.rpt]
write_checkpoint -force [file join $xdc_dir cp_E.dcp]
close_design

# ============================================================
# Strategy F: Explore + AlternateFlowWithRetiming
# ============================================================
puts "\n=== Strategy F: Explore + AlternateFlowWithRetiming ==="
open_checkpoint [file join $xdc_dir cp_synth.dcp]
place_design -directive Explore
phys_opt_design -directive AlternateFlowWithRetiming
route_design -directive Explore
report_timing_summary -file [file join $xdc_dir timing_F_retiming.rpt]
write_checkpoint -force [file join $xdc_dir cp_F.dcp]
close_design

# ============================================================
# Summary
# ============================================================
puts "\n=========================================="
puts " All strategies complete."
puts " Reports: timing_[A-F]_*.rpt"
puts "=========================================="

# Cleanup intermediate checkpoints
file delete -force [file join $xdc_dir cp_synth.dcp]
file delete -force [file join $xdc_dir cp_A.dcp]
file delete -force [file join $xdc_dir cp_B.dcp]
file delete -force [file join $xdc_dir cp_C.dcp]
file delete -force [file join $xdc_dir cp_D.dcp]
file delete -force [file join $xdc_dir cp_E.dcp]
file delete -force [file join $xdc_dir cp_F.dcp]
