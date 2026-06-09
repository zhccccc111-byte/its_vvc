set dcp_file "its_vvc_synth/its_vvc_synth.runs/impl_1/its_top_routed.dcp"
open_checkpoint $dcp_file
report_timing_summary -file timing_impl.rpt
report_utilization -file utilization_impl.rpt
report_power -file power_impl.rpt
report_methodology -file methodology_impl.rpt
puts "Reports generated successfully"
close_design
