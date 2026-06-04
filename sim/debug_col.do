# Debug column engine - waveform approach
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

# Add key signals
add wave -radix decimal /its_tb/u_dut/state
add wave -radix decimal /its_tb/u_dut/u_col_engine/state
add wave -radix decimal /its_tb/u_dut/col_idx
add wave -radix decimal /its_tb/u_dut/tp_rd_base
add wave /its_tb/u_dut/col_done
add wave /its_tb/u_dut/col_out_vld
add wave -radix decimal /its_tb/u_dut/col_out_data
add wave -radix decimal /its_tb/u_dut/out_mem_wr_cnt

run 50000ns
