# ==============================================================================
# Script: create_block_design.tcl
# Description: Automated Vivado Tcl script to generate an IP Integrator Block
#              Design (.bd) for the 16x16 2D Systolic Array Accelerator.
# Target Board: Digilent Basys 3 (xc7a35tcpg236-1) or generic Artix-7
# ==============================================================================

set SCRIPT_DIR  [file dirname [info script]]
set PROJECT_DIR [file normalize "$SCRIPT_DIR/../vivado_bd_proj"]
set SRC_DIR     [file normalize "$SCRIPT_DIR/../src"]

puts "========================================================================"
puts "  Creating Vivado IP Integrator Block Design for 16x16 Systolic Array"
puts "  Project Directory : $PROJECT_DIR"
puts "  Source Directory  : $SRC_DIR"
puts "========================================================================"

# Create Project
create_project -force systolic_16x16_bd_proj "$PROJECT_DIR" -part xc7a35tcpg236-1

# Add All Synthesizable RTL Sources
add_files [list \
    "$SRC_DIR/systolic_pkg.sv" \
    "$SRC_DIR/processing_element.sv" \
    "$SRC_DIR/skew_buffer.sv" \
    "$SRC_DIR/controller.sv" \
    "$SRC_DIR/systolic_array.sv" \
    "$SRC_DIR/systolic_top.sv" \
    "$SRC_DIR/systolic_axi_wrapper.sv" \
    "$SRC_DIR/systolic_axi_wrapper_top.v" \
]

update_compile_order -fileset sources_1

# Create Block Design
create_bd_design "systolic_16x16_bd"
current_bd_design "systolic_16x16_bd"

# ------------------------------------------------------------------------------
# 1. Instantiate Systolic Array RTL Module Reference (Verilog .v Wrapper)
# ------------------------------------------------------------------------------
set systolic_inst [create_bd_cell -type module -reference systolic_axi_wrapper_top systolic_axi_0]

# ------------------------------------------------------------------------------
# 2. Instantiate Processor System Reset
# ------------------------------------------------------------------------------
set rst_gen [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0]

# ------------------------------------------------------------------------------
# 3. Create External AXI Clock & Reset Ports
# ------------------------------------------------------------------------------
create_bd_port -dir I -type clk -freq_hz 100000000 s_axi_aclk
create_bd_port -dir I -type rst s_axi_aresetn
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports s_axi_aresetn]

# Expose Interrupt Done Flag
create_bd_port -dir O irq_done

# Expose Standard AXI4-Lite Slave Bus Interface
make_bd_intf_pins_external [get_bd_intf_pins systolic_axi_0/s_axi] -name "s_axi"
set_property CONFIG.ASSOCIATED_BUSIF {s_axi} [get_bd_ports s_axi_aclk]
set_property CONFIG.ASSOCIATED_RESET {s_axi_aresetn} [get_bd_ports s_axi_aclk]

# ------------------------------------------------------------------------------
# 4. Connect Clock, Reset, and Interrupt Networks
# ------------------------------------------------------------------------------
# Clock Distribution
connect_bd_net [get_bd_ports s_axi_aclk] [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net [get_bd_ports s_axi_aclk] [get_bd_pins systolic_axi_0/s_axi_aclk]

# Reset Distribution
connect_bd_net [get_bd_ports s_axi_aresetn] [get_bd_pins proc_sys_reset_0/ext_reset_in]
connect_bd_net [get_bd_ports s_axi_aresetn] [get_bd_pins systolic_axi_0/s_axi_aresetn]

# Interrupt Output
connect_bd_net [get_bd_pins systolic_axi_0/irq_done] [get_bd_ports irq_done]

# Assign AXI Address Space (4KB Register Map)
assign_bd_address [get_bd_addr_segs {systolic_axi_0/s_axi/reg0}]

# ------------------------------------------------------------------------------
# 5. Validate and Save Block Design
# ------------------------------------------------------------------------------
validate_bd_design
save_bd_design

# ------------------------------------------------------------------------------
# 6. Generate HDL Wrapper and Output Targets
# ------------------------------------------------------------------------------
set wrapper_file [make_wrapper -files [get_files [get_property FILE_NAME [current_bd_design]]] -top]
add_files -norecurse [list $wrapper_file]
update_compile_order -fileset sources_1

# Generate all output products (synthesis, simulation, implementation files for BD)
generate_target all [get_files [get_property FILE_NAME [current_bd_design]]]

puts "========================================================================"
puts "  \[SUCCESS\] Block Design 'systolic_16x16_bd' successfully generated!"
puts "  Target BD File   : [get_property FILE_NAME [current_bd_design]]"
puts "  HDL Wrapper File : $wrapper_file"
puts "========================================================================"
