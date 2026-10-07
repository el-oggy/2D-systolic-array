# Focused check that one DSP MAC maps to one DSP48E1.
set script_dir [file dirname [info script]]
set project_root [file join $script_dir ../..]
cd $project_root
set project_root .
set_param general.maxThreads 2
read_verilog -sv [file join $project_root src/pe_mac.sv]
synth_design -top pe_mac -part xc7z020clg400-1
set results_dir [file join $project_root results]
file mkdir $results_dir
report_utilization -file [file join $results_dir pe_mac_utilization.rpt]

