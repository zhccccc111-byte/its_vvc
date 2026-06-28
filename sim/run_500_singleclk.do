# ModelSim simulation script for ITS 500MHz single-clock submission top

vlib work

vlog -sv ../rtl/its_mac.v
vlog -sv ../rtl/its_rom.v
vlog -sv ../rtl/its_lfnst_rom.v
vlog -sv ../rtl/its_transform_engine.v
vlog -sv ../rtl/its_lfnst.v
vlog -sv ../rtl/its_core_500.v
vlog -sv ../rtl/rst_sync.v
vlog -sv ../rtl/async_fifo.v
vlog -sv ../rtl/fifo_fwft_reg_slice.v
vlog -sv ../rtl/its_top_500_wrapper.v
vlog -sv ../rtl/its_top_500_singleclk.v

vlog -sv +define+SINGLECLK_SUBMISSION ../tb/its_tb_500.v

vsim -t 1ps -novopt work.its_tb_500

run -all
