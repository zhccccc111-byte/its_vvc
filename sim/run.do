# ModelSim simulation script for ITS

# Create work library
vlib work

# Compile RTL
vlog ../rtl/its_mac.v
vlog ../rtl/its_rom.v
vlog ../rtl/its_lfnst_rom.v
vlog ../rtl/its_transform_engine.v
vlog ../rtl/its_lfnst.v
vlog ../rtl/its_top.v

# Compile testbench
vlog ../tb/its_tb.v

# Simulate
vsim -t 1ps work.its_tb

# Run
run -all
