# Isolated LUT-only PE utilization check for the PYNQ tile configuration.
set script_dir [file dirname [info script]]
set project_root [file join $script_dir ../..]
cd $project_root
set project_root .
set_param general.maxThreads 1
read_verilog -sv [file join $project_root src/pe_mac.sv]
synth_design -top pe_mac -part xc7z020clg400-1 -mode out_of_context \
    -generic {DATA_WIDTH=8} -generic {ACC_WIDTH=20} -generic {MAC_IMPL=LUT}
set results_dir [file join $project_root results]
file mkdir $results_dir
report_utilization -file [file join $results_dir pe_mac_lut_utilization.rpt]
puts "LUT PE utilization report written to [file join $results_dir pe_mac_lut_utilization.rpt]"

