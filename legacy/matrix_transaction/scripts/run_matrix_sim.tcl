# ==============================================================================
# Script: run_matrix_sim.tcl
# Description: Vivado Tcl simulation script for OOP SystemVerilog Verification
# ==============================================================================

set SCRIPT_DIR [file dirname [info script]]
set ROOT_DIR   [file normalize "$SCRIPT_DIR/.."]

puts "========================================================================"
puts "  Launching Vivado Simulation for OOP SystemVerilog Testbench"
puts "  Root Directory: $ROOT_DIR"
puts "========================================================================"

# Set include directories
set_property include_dirs [list "$ROOT_DIR/src" "$ROOT_DIR/tb"] [current_fileset -simset]

# Compile SystemVerilog Files
exec xvlog -sv -i "$ROOT_DIR/src" -i "$ROOT_DIR/tb" \
    "$ROOT_DIR/src/systolic_pkg.sv" \
    "$ROOT_DIR/src/processing_element.sv" \
    "$ROOT_DIR/src/skew_buffer.sv" \
    "$ROOT_DIR/src/controller.sv" \
    "$ROOT_DIR/src/systolic_array.sv" \
    "$ROOT_DIR/src/systolic_top.sv" \
    "$ROOT_DIR/tb/tb_matrix_top.sv"

# Elaborate
exec xelab -debug typical -top tb_matrix_top -snapshot tb_matrix_top_snapshot

# Simulate
xsim tb_matrix_top_snapshot -R
