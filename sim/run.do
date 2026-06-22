# ModelSim simulation script for ITS

# Create work library
vlib work

# Compile RTL
vlog -sv ../rtl/its_mac.v
vlog -sv ../rtl/its_rom.v
vlog -sv ../rtl/its_lfnst_rom.v
vlog -sv ../rtl/its_transform_engine.v
vlog -sv ../rtl/its_lfnst.v
vlog -sv ../rtl/its_top.v

# Compile testbench
vlog -sv ../tb/its_tb.v

# Simulate
vsim -t 1ps work.its_tb

# Run
run -all
