# Isolate the 16x16 AXI-engine controller to compare its contribution to LUT use.
set script_dir [file dirname [info script]]
set project_root [file join $script_dir ../..]
cd $project_root
set project_root .
set_param general.maxThreads 1
read_verilog -sv [file join $project_root src/single_tile_controller.sv]
synth_design -top single_tile_controller -part xc7z020clg400-1 -mode out_of_context
set results_dir [file join $project_root results]
file mkdir $results_dir
report_utilization -file [file join $results_dir single_tile_controller_utilization.rpt]
puts "Controller utilization report written to [file join $results_dir single_tile_controller_utilization.rpt]"

