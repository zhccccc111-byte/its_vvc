vlib work
vlog ../rtl/its_mac.v
vlog ../rtl/its_rom.v
vlog ../rtl/its_lfnst_rom.v
vlog ../rtl/its_ctrl.v
vlog ../rtl/its_input_buf.v
vlog ../rtl/its_transpose.v
vlog ../rtl/its_transform_engine.v
vlog ../rtl/its_lfnst.v
vlog ../rtl/its_output_ctrl.v
vlog ../rtl/its_top.v
vlog ../tb/its_tb.v
vsim -t 1ps work.its_tb
run -all
