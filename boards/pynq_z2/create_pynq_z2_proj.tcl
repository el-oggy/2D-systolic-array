# ============================================================================
# Vivado Tcl Script: create_pynq_z2_proj.tcl
# Description: Automated Vivado Project Creation & Build for PYNQ-Z2
# Target Part: xc7z020clg400-1 (TUL PYNQ-Z2)
# ============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/../.."]
set PROJ_DIR   "$SCRIPT_DIR/pynq_z2_vivado_proj"
set PROJ_NAME  "systolic_16x16_pynq_z2"

puts "======================================================================"
puts "  CREATING PYNQ-Z2 VIVADO PROJECT: $PROJ_NAME"
puts "  Target Part: xc7z020clg400-1"
puts "  Repository Root: $REPO_ROOT"
puts "======================================================================"

# Create project
create_project -force $PROJ_NAME $PROJ_DIR -part xc7z020clg400-1

# Set target board if board files exist
catch { set_property board_part tul.com.tw:pynq-z2:part0:1.0 [current_project] }

# Add synthesizable RTL sources
add_files -norecurse [list \
    "$REPO_ROOT/rtl/systolic_pkg.sv" \
    "$REPO_ROOT/rtl/systolic_constants.vh" \
    "$REPO_ROOT/rtl/processing_element.sv" \
    "$REPO_ROOT/rtl/skew_buffer.sv" \
    "$REPO_ROOT/rtl/systolic_array.sv" \
    "$REPO_ROOT/rtl/controller.sv" \
    "$REPO_ROOT/rtl/systolic_top.sv" \
    "$REPO_ROOT/boards/pynq_z2/pynq_z2_demo_16x16_top.sv" \
]

# Set top module
set_property top pynq_z2_demo_16x16_top [current_fileset]

# Add physical constraints
add_files -fileset constrs_1 -norecurse "$SCRIPT_DIR/pynq_z2_constraints.xdc"

# Add simulation testbenches
add_files -fileset sim_1 -norecurse [list \
    "$REPO_ROOT/tb/unit/tb_step6_systolic_16x16.sv" \
]
set_property top tb_step6_systolic_16x16 [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "======================================================================"
puts "  PROJECT CREATED SUCCESSFULLY!"
puts "  Project Location: $PROJ_DIR/$PROJ_NAME.xpr"
puts "======================================================================"
