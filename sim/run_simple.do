# ModelSim simulation script for ITS - Simple Test

vlib work

vlog -sv ../rtl/its_mac.v
vlog -sv ../rtl/its_rom.v
vlog -sv ../rtl/its_lfnst_rom.v
vlog -sv ../rtl/its_ctrl.v
vlog -sv ../rtl/its_input_buf.v
vlog -sv ../rtl/its_transpose.v
vlog -sv ../rtl/its_transform_engine.v
vlog -sv ../rtl/its_lfnst.v
vlog -sv ../rtl/its_output_ctrl.v
vlog -sv ../rtl/its_top.v

vlog -sv ../tb/its_tb_simple.v

vsim -t 1ps work.its_tb_simple

run -all
