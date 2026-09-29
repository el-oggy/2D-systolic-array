# ==============================================================================
# Script: generate_schematic.tcl
# Description: Automated Vivado Tcl script to elaborate the 16x16 2D Systolic
#              Array accelerator and generate RTL Schematic, hierarchy reports,
#              and netlists.
# ==============================================================================

set SCRIPT_DIR [file dirname [info script]]
set SRC_DIR    [file normalize "$SCRIPT_DIR/../src"]
set OUT_DIR    [file normalize "$SCRIPT_DIR/../reports"]

file mkdir "$OUT_DIR"

puts "========================================================================"
puts "  Elaborating RTL Schematic for 16x16 2D Systolic Array Accelerator"
puts "  Source Directory : $SRC_DIR"
puts "  Report Directory : $OUT_DIR"
puts "========================================================================"

# Read SystemVerilog Sources
read_verilog -sv [list \
    "$SRC_DIR/systolic_pkg.sv" \
    "$SRC_DIR/processing_element.sv" \
    "$SRC_DIR/skew_buffer.sv" \
    "$SRC_DIR/controller.sv" \
    "$SRC_DIR/systolic_array.sv" \
    "$SRC_DIR/systolic_top.sv" \
]

# Run RTL Elaboration
puts "\[INFO\] Running RTL Elaboration (synth_design -rtl)..."
synth_design -top systolic_top -part xc7a35tcpg236-1 -rtl -name rtl_1

# Write Elaborated Netlist
puts "\[INFO\] Writing Elaborated Structural Verilog Netlist..."
write_verilog -force "$OUT_DIR/systolic_16x16_elaborated_netlist.v"

# Count and report elaborated hierarchical modules & cells
puts "\[INFO\] Generating Elaborated Hierarchy & Cell Count Report..."
set all_cells [get_cells -hierarchical]
set pe_cells  [get_cells -hierarchical -filter {REF_NAME == processing_element}]

set fp [open "$OUT_DIR/systolic_16x16_elaboration_summary.rpt" w]
puts $fp "================================================================================"
puts $fp "  16x16 2D Systolic Array - Vivado Elaborated RTL Design Summary"
puts $fp "================================================================================"
puts $fp "  Target Device              : xc7a35tcpg236-1 (Artix-7 / Basys 3)"
puts $fp "  Top-Level Module           : systolic_top"
puts $fp "  Total Elaborated Instances : [llength $all_cells]"
puts $fp "  Processing Elements (PEs)  : [llength $pe_cells] (16x16 Grid = 256 PEs)"
puts $fp "================================================================================"
close $fp

puts "========================================================================"
puts "  \[SUCCESS\] RTL Elaboration Complete!"
puts "  Summary Report     : $OUT_DIR/systolic_16x16_elaboration_summary.rpt"
puts "  Structural Netlist : $OUT_DIR/systolic_16x16_elaborated_netlist.v"
puts "========================================================================"
