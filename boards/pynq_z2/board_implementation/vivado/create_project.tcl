# Create a Vivado project for the dual-engine accelerator wrapper and sims.
# Run from any working directory with:
#   vivado -mode batch -source board_implementation/vivado/create_project.tcl

set script_dir [file dirname [file normalize [info script]]]
if {$script_dir eq "" || $script_dir eq "."} {
    set script_dir [file normalize [file join [pwd] "board_implementation/vivado"]]
}
set project_root [file normalize [file join $script_dir ../..]]

set part "xc7z020clg400-1"

if {[current_project -quiet] eq ""} {
    set proj_name "pynq_gemm"
    set proj_dir [file join $project_root "prj"]
    puts "Creating project $proj_name at $proj_dir..."
    create_project $proj_name $proj_dir -part $part -force
} else {
    set proj_name [get_property NAME [current_project]]
    set proj_dir [get_property DIRECTORY [current_project]]
    puts "Using active project: $proj_name at $proj_dir"
    set_property part $part [current_project]
}
set_property target_language Verilog [current_project]
set_property default_lib work [current_project]

# Synthesizable accelerator modules from the flattened src/ tree.
add_files -norecurse [list \
    [file join $project_root src/pe_mac.sv] \
    [file join $project_root src/skew_buffers.sv] \
    [file join $project_root src/systolic_array.sv] \
    [file join $project_root src/dual_systolic_array.sv] \
    [file join $project_root src/tile_addr_gen.sv] \
    [file join $project_root src/tile_controller.sv] \
    [file join $project_root src/single_tile_controller.sv] \
    [file join $project_root src/accel_dual_tile_core.sv] \
    [file join $project_root src/c_buf.sv] \
    [file join $project_root src/ping_pong_bram.sv] \
    [file join $project_root src/unified_bram_feeder.sv] \
    [file join $project_root src/axis_out_dual_adapter.sv] \
    [file join $project_root src/accel_dual_engine_top.sv] \
    [file join $project_root src/axi_lite_regs.sv] \
    [file join $project_root src/axis_in_adapter.sv] \
    [file join $project_root src/axis_out_adapter.sv] \
    [file join $project_root src/accel_top.sv] \
    [file join $project_root src/accel_top_wrapper.v] \
    [file join $project_root src/accel_dual_axi_top.sv]]

set_property top accel_dual_axi_top [current_fileset]
update_compile_order -fileset sources_1

# This is the valid out-of-context constraint for the AXI wrapper. The full
# Zynq block design clocks the accelerator from PS FCLK and removes this XDC.
add_files -fileset constrs_1 -norecurse \
    [file join $project_root board_implementation/constraints/accel_dual_axi_top_ooc.xdc]

# Default synthesis options for full top system
if {[get_runs -quiet synth_1] ne ""} {
    set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {} -objects [get_runs synth_1]
}

# Keep all active self-checking benches in the simulation fileset.
add_files -fileset sim_1 -norecurse [list \
    [file join $project_root simulation/tb_accel_dual_engine_top.sv] \
    [file join $project_root simulation/tb_power_regression.sv] \
    [file join $project_root simulation/tb_accel_top_axis.sv] \
    [file join $project_root simulation/tb_adaptive_gemm.sv] \
    [file join $project_root simulation/tb_pe_mac.sv] \
    [file join $project_root simulation/tb_dual_systolic_array.sv] \
    [file join $project_root simulation/tb_accel_dual_tile_core.sv] \
    [file join $project_root simulation/tb_accel_cache_mvm.sv] \
    [file join $project_root simulation/tb_ping_pong_bram.sv] \
    [file join $project_root simulation/tb_skew_buffers.sv]]
set_property top tb_accel_dual_engine_top [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "Vivado project $proj_name created for $part at $proj_dir."

