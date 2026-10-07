# Isolated OOC screening. Args: source_root output_dir DSPs_per_engine MHz
lassign $argv source_root output_dir dsp_limit clock_mhz
if {$source_root eq "" || $output_dir eq ""} { error "Expected source_root output_dir DSPs_per_engine MHz" }
if {$dsp_limit eq ""} { set dsp_limit 110 }
if {$clock_mhz eq ""} { set clock_mhz 100 }
set source_root [file normalize $source_root]
set output_dir [file normalize $output_dir]
file mkdir $output_dir
set_param general.maxThreads 4
foreach f [glob [file join $source_root src *.sv]] { read_verilog -sv $f }
read_verilog [file join $source_root src accel_top_wrapper.v]
synth_design -top accel_top_wrapper -part xc7z020clg400-1 -mode out_of_context \
    -generic DSP_PE_LIMIT_0=$dsp_limit -generic DSP_PE_LIMIT_1=$dsp_limit
create_clock -name clk_fpga_0 -period [expr {1000.0 / $clock_mhz}] [get_ports clk]
report_utilization -file [file join $output_dir utilization_synth.rpt]
report_utilization -hierarchical -file [file join $output_dir utilization_hier.rpt]
report_timing_summary -file [file join $output_dir timing_synth.rpt]
write_checkpoint -force [file join $output_dir synthesized.dcp]
set fp [open [file join $output_dir configuration.txt] w]
puts $fp "Tool: [version -short]\nSource: $source_root\nDSPs per engine: $dsp_limit\nClock MHz: $clock_mhz\nScope: accelerator-only OOC screening, not board signoff"
close $fp
exit 0
