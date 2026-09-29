# ============================================================================
# Vivado Tcl Simulation Script
# Usage in Vivado Tcl Console:
#   cd {c:/Users/adars/OneDrive/Desktop/vs-code/simulation/scripts}
#   source run_sim.tcl
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize "$script_dir/.."]

puts "============================================================================"
puts "  Loading 2D Systolic Array Simulation in Vivado"
puts "  Root directory: $root_dir"
puts "============================================================================"

# Create an in-memory project or update current project
if {[catch {current_project}]} {
    create_project -in_memory -part xc7a35tcpg236-1
}

# Add Design Sources
add_files -fileset sources_1 [glob "$root_dir/src/*.sv"]
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sources_1]]

# Add Testbenches
add_files -fileset sim_1 [glob "$root_dir/sim/*.sv"]
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1]]

# Set Top Module for Simulation (Default: tb_step4_systolic_4x4)
set_property top tb_step4_systolic_4x4 [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ">>> Sources added successfully. Launching behavioral simulation..."
launch_simulation -mode behavioral

puts ">>> Simulation running..."
run all
