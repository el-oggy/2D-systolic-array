# Full-top out-of-context synthesis for the Option 2 unified dual-engine accelerator.
# Target: Xilinx Zynq-7000 (XC7Z020CLG400-1)
# Symmetrical 110/110 DSP partition, Unified BRAM Feeder, 512 MAC lanes.
# Run with:
#   vivado -mode batch -source board_implementation/vivado/synth_accel.tcl

set script_dir [file dirname [file normalize [info script]]]
if {$script_dir eq "" || $script_dir eq "."} {
    set script_dir [file normalize [file join [pwd] "board_implementation/vivado"]]
}
set project_root [file normalize [file join $script_dir ../..]]
set_param general.maxThreads 4

foreach source_file [list \
    src/pe_mac.sv \
    src/skew_buffers.sv \
    src/systolic_array.sv \
    src/dual_systolic_array.sv \
    src/tile_addr_gen.sv \
    src/tile_controller.sv \
    src/single_tile_controller.sv \
    src/accel_dual_tile_core.sv \
    src/ping_pong_bram.sv \
    src/c_buf.sv \
    src/unified_bram_feeder.sv \
    src/axis_out_dual_adapter.sv \
    src/axi_lite_regs.sv \
    src/accel_dual_engine_top.sv] {
    read_verilog -sv [file join $project_root $source_file]
}

read_verilog [file join $project_root src/accel_top_wrapper.v]

read_xdc [file join $project_root board_implementation/constraints/accel_dual_axi_top_ooc.xdc]

puts "=================================================================="
puts " Starting OOC synthesis for accel_top_wrapper on xc7z020clg400-1..."
puts " Plan B: 110 DSPs / 110 DSPs symmetrical balance"
puts " Plan C: Single DMA Stream Feeder with Unified Dual-Bank BRAM"
puts " Plan A: BRAM primitives for all tile memory and skew buffers"
puts "=================================================================="

synth_design -top accel_top_wrapper -part xc7z020clg400-1 -mode out_of_context

set results_dir [file join $project_root results]
file mkdir $results_dir
write_checkpoint -force [file join $results_dir accel_option2_synth.dcp]
report_utilization -file [file join $results_dir vivado_utilization_option2.rpt]
report_utilization -hierarchical -file [file join $results_dir vivado_utilization_option2_hier.rpt]
report_timing_summary -file [file join $results_dir vivado_timing_option2.rpt]
report_methodology -file [file join $results_dir vivado_methodology_option2.rpt]

puts "=================================================================="
puts " Option 2 Synthesis completed! Reports written to $results_dir."
puts "=================================================================="
