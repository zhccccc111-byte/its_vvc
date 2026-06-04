# ===================================================================
# ITS VVC Inverse Transform - Timing Constraints
# Target: 500MHz (2ns period)
# ===================================================================

# Clock definition
create_clock -period 2.000 -name clk [get_ports clk]

# Input delay (assuming registered inputs)
set_input_delay -clock clk -max 0.500 [get_ports {it_info* it_data_in* it_data_addr* it_data_in_vld it_info_vld}]
set_input_delay -clock clk -min 0.100 [get_ports {it_info* it_data_in* it_data_addr* it_data_in_vld it_info_vld}]

# Output delay
set_output_delay -clock clk -max 0.500 [get_ports {it_data_out* it_data_out_vld it_done}]
set_output_delay -clock clk -min 0.100 [get_ports {it_data_out* it_data_out_vld it_done}]

# Asynchronous reset
set_false_path -from [get_ports rst_n]

# Clock uncertainty
set_clock_uncertainty -setup 0.100 [get_clocks clk]
set_clock_uncertainty -hold 0.050 [get_clocks clk]
