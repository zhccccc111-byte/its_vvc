vlib work
vlog -sv ../rtl/its_mac.v
vlog -sv ../rtl/its_rom.v
vlog -sv ../rtl/its_lfnst_rom.v
vlog -sv ../rtl/its_transform_engine.v
vlog -sv ../rtl/its_lfnst.v
vlog -sv ../rtl/its_top.v
vlog -sv ../tb/its_tb.v
vsim -t 1ps work.its_tb
run 500000
