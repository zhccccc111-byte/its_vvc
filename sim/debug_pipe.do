# Debug output pipeline
add wave -radix decimal u_dut/state
add wave -radix decimal u_dut/out_cnt
add wave -radix decimal u_dut/total_points
add wave u_dut/out_vld_r
add wave u_dut/it_data_out_vld_r
add wave u_dut/it_data_out_vld_rr
add wave -radix decimal u_dut/it_data_out_r
add wave -radix decimal u_dut/it_data_out
add wave -radix decimal u_dut/out_flush_cnt
add wave u_dut/it_done

run 5000
quit -f
