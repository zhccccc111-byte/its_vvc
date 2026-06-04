vlib work
vmap work work
vlog ../rtl/its_mac.v
vlog ../rtl/its_rom.v
vlog ../rtl/its_lfnst_rom.v
vlog ../rtl/its_transform_engine.v
vlog ../rtl/its_lfnst.v
vlog ../rtl/its_top.v
vlog ../tb/its_tb.v
vsim -t 1ps work.its_tb
# Check ROM contents at key addresses
log -r /*
run 100
# Print ROM contents
examine -radix decimal u_dut.u_row_rom.rom[1360]
examine -radix decimal u_dut.u_row_rom.rom[1361]
examine -radix decimal u_dut.u_row_rom.rom[1423]
examine -radix decimal u_dut.u_row_rom.rom[1424]
examine -radix decimal u_dut.u_row_rom.rom[5455]
run 100
quit -f
