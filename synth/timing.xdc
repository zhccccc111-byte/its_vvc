# ===================================================================
# ITS VVC Inverse Transform - Timing Constraints
# Target: Artix-7 xc7a200tfbg484-3 (speed grade -3)
# Clock: 100MHz (10ns period)
# ===================================================================

# Clock definition
create_clock -period 10.000 -name clk [get_ports clk]

# Input delay
# it_data_out_req is an INPUT (backpressure from downstream), not covered by it_data_out* output pattern
set_input_delay -clock clk -max 0.300 [get_ports {it_info* it_data_in it_data_in_vld it_data_addr* it_data_end it_info_vld it_data_out_req}]
set_input_delay -clock clk -min 0.100 [get_ports {it_info* it_data_in it_data_in_vld it_data_addr* it_data_end it_info_vld it_data_out_req}]

# Output delay
# it_data_in_req is an OUTPUT (request to upstream), not covered by it_data_in* input pattern
set_output_delay -clock clk -max 0.300 [get_ports {it_data_out it_data_out_vld it_data_in_req it_done}]
set_output_delay -clock clk -min 0.100 [get_ports {it_data_out it_data_out_vld it_data_in_req it_done}]

# Asynchronous reset - false path
set_false_path -from [get_ports rst_n]

# Clock uncertainty
set_clock_uncertainty -setup 0.050 [get_clocks clk]
set_clock_uncertainty -hold 0.025 [get_clocks clk]

# ===================================================================
# IOB constraints - pack output registers into I/O Block
# Reduces output routing delay from ~2.9ns to ~0.5ns
# ===================================================================
set_property IOB TRUE [get_cells -hierarchical -filter {NAME =~ "*data_out_r_reg*"}]
set_property IOB TRUE [get_cells -hierarchical -filter {NAME =~ "*data_out_valid_reg*"}]

# ===================================================================
# Max Fanout constraint - reduce signal routing delay
# ===================================================================
set_property MAX_FANOUT 50 [get_nets -hierarchical -filter {NAME =~ "*out_cnt*"}]

# ===================================================================
# Block RAM output register inference
# ===================================================================
set_property RAM_STYLE block [get_cells -hierarchical -filter {NAME =~ "*out_mem*"}]
set_property RAM_STYLE block [get_cells -hierarchical -filter {NAME =~ "*in_mem*"}]
set_property RAM_STYLE block [get_cells -hierarchical -filter {NAME =~ "*tp_buf*"}]
