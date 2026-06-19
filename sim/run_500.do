# ModelSim simulation script for ITS 500MHz Wrapper

# Create work library
vlib work

# Compile RTL (dependencies first)
vlog ../rtl/its_mac.v
vlog ../rtl/its_rom.v
vlog ../rtl/its_lfnst_rom.v
vlog ../rtl/its_transform_engine.v
vlog ../rtl/its_lfnst.v
vlog ../rtl/its_core_500.v
vlog ../rtl/rst_sync.v
vlog ../rtl/async_fifo.v
vlog ../rtl/its_top_500_wrapper.v

# Compile testbench
vlog ../tb/its_tb_500.v

# Simulate (novopt: disable optimization to preserve hierarchy for debug)
vsim -t 1ps -novopt work.its_tb_500

# Run
run -all
