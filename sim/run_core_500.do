# ModelSim simulation script for ITS Core 500MHz testbench

# Create work library
vlib work

# Compile RTL (same submodules as its_top)
vlog ../rtl/its_mac.v
vlog ../rtl/its_rom.v
vlog ../rtl/its_lfnst_rom.v
vlog ../rtl/its_transform_engine.v
vlog ../rtl/its_lfnst.v
vlog ../rtl/its_core_500.v

# Compile testbench
vlog ../tb/its_core_500_tb.v

# Simulate
vsim -t 1ps work.its_core_500_tb

# Run
run -all
