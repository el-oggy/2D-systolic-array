# ==============================================================================
# File: build_bitstream.tcl
# Description: Automated Vivado Batch Script for PYNQ-Z2 16x16 Systolic Accelerator
# Target Device: Xilinx Zynq-7000 SoC (xc7z020clg400-1)
# Top Module: pynq_z2_demo_16x16_top
# ==============================================================================

set_param general.maxThreads 6

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize "$script_dir/../.."]

cd $repo_root
puts "=================================================================="
puts "  BUILDING PYNQ-Z2 16x16 SYSTOLIC ARRAY HARDWARE ACCELERATOR      "
puts "  Repository Root: $repo_root                                     "
puts "=================================================================="

# 1. Create In-Memory Project
create_project -in_memory -part xc7z020clg400-1

# 2. Add SystemVerilog / Verilog Sources
read_verilog -sv [list \
    {boards/pynq_z2/src/systolic_pkg.sv} \
    {boards/pynq_z2/src/controller.sv} \
    {boards/pynq_z2/src/processing_element.sv} \
    {boards/pynq_z2/src/skew_buffer.sv} \
    {boards/pynq_z2/src/systolic_array.sv} \
    {boards/pynq_z2/src/systolic_top.sv} \
    {boards/pynq_z2/board_implementation/pynq_z2_demo_16x16_top.sv} \
]

# 3. Add Constraints
read_xdc [list {boards/pynq_z2/board_implementation/pynq_z2_constraints.xdc}]

# 4. Synthesize Design
puts "\n--- [Step 1/4] Running Synthesis ---"
synth_design -top pynq_z2_demo_16x16_top -part xc7z020clg400-1
report_utilization -file {boards/pynq_z2/board_implementation/utilization_synth.rpt}

# 5. Logic Optimization and Placement
puts "\n--- [Step 2/4] Running Optimization and Placement ---"
opt_design
place_design

# 6. Routing and Timing Verification
puts "\n--- [Step 3/4] Running Route and Timing Analysis ---"
route_design
report_utilization -file {boards/pynq_z2/board_implementation/utilization_route.rpt}
report_timing_summary -max_paths 10 -file {boards/pynq_z2/board_implementation/timing_summary.rpt}

# 7. Bitstream Generation
puts "\n--- [Step 4/4] Writing Bitstream ---"
write_bitstream -force {boards/pynq_z2/pynq_z2_systolic_16x16.bit}

puts "\n=================================================================="
puts "  SUCCESS: Bitstream successfully generated!                     "
puts "  Output File: boards/pynq_z2/pynq_z2_systolic_16x16.bit          "
puts "=================================================================="
quit
