# ===================================================================
# ITS 500MHz Wrapper OOC Timing Constraints
# Two clock domains: clk_if (100MHz) and clk_core (500MHz)
# CDC handled by set_clock_groups -asynchronous
# ===================================================================

# -------------------------------------------------------------------
# Clock definitions
# -------------------------------------------------------------------
# Interface clock: 100MHz (competition interface)
create_clock -period 10.000 -name clk_if [get_ports clk_if]

# Core clock: 500MHz (compute engine)
create_clock -period 2.000 -name clk_core [get_ports clk_core]

# -------------------------------------------------------------------
# CDC isolation — the key constraint
# All paths between clk_if and clk_core are handled by async FIFOs
# with Gray-code pointers + 2-FF synchronizers.
# No multicycle or false-path on individual FIFO pointers needed;
# the clock group declaration tells Vivado to ignore all cross-domain
# timing checks entirely.
# -------------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks clk_if] \
    -group [get_clocks clk_core]

# -------------------------------------------------------------------
# Async reset: deassertion is synchronized by rst_sync (3-FF).
# Treat rst_n assertion as false path (async assert is immediate).
# -------------------------------------------------------------------
set_false_path -from [get_ports rst_n]

# -------------------------------------------------------------------
# I/O delays on competition interface (clk_if domain)
# Assume ~0.5ns max external delay from I/O pad or upstream logic.
# -------------------------------------------------------------------

# Inputs (clk_if domain)
set_input_delay -clock clk_if -max 0.500 [get_ports {it_info[*]}]
set_input_delay -clock clk_if -min 0.100 [get_ports {it_info[*]}]
set_input_delay -clock clk_if -max 0.500 [get_ports {it_info_vld}]
set_input_delay -clock clk_if -min 0.100 [get_ports {it_info_vld}]
set_input_delay -clock clk_if -max 0.500 [get_ports {it_data_in[*]}]
set_input_delay -clock clk_if -min 0.100 [get_ports {it_data_in[*]}]
set_input_delay -clock clk_if -max 0.500 [get_ports {it_data_addr[*]}]
set_input_delay -clock clk_if -min 0.100 [get_ports {it_data_addr[*]}]
set_input_delay -clock clk_if -max 0.500 [get_ports {it_data_in_vld}]
set_input_delay -clock clk_if -min 0.100 [get_ports {it_data_in_vld}]
set_input_delay -clock clk_if -max 0.500 [get_ports {it_data_end}]
set_input_delay -clock clk_if -min 0.100 [get_ports {it_data_end}]
set_input_delay -clock clk_if -max 0.500 [get_ports {it_data_out_req}]
set_input_delay -clock clk_if -min 0.100 [get_ports {it_data_out_req}]

# Outputs (clk_if domain)
set_output_delay -clock clk_if -max 0.500 [get_ports {it_data_in_req}]
set_output_delay -clock clk_if -min 0.100 [get_ports {it_data_in_req}]
set_output_delay -clock clk_if -max 0.500 [get_ports {it_data_out[*]}]
set_output_delay -clock clk_if -min 0.100 [get_ports {it_data_out[*]}]
set_output_delay -clock clk_if -max 0.500 [get_ports {it_data_out_vld}]
set_output_delay -clock clk_if -min 0.100 [get_ports {it_data_out_vld}]
set_output_delay -clock clk_if -max 0.500 [get_ports {it_done}]
set_output_delay -clock clk_if -min 0.100 [get_ports {it_done}]
