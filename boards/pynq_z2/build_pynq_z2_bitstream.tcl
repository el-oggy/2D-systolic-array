# ============================================================================
# Vivado Tcl Script: build_pynq_z2_bitstream.tcl
# Description: Automated Headless Synthesis, Implementation & Bitstream Build
# Target: PYNQ-Z2 (xc7z020clg400-1)
# ============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
source "$SCRIPT_DIR/create_pynq_z2_proj.tcl"

puts "======================================================================"
puts "  STARTING SYNTHESIS (synth_1)..."
puts "======================================================================"
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "\[ERROR\] Synthesis failed! Check synth_1 run log."
    exit 1
}
puts "  Synthesis completed successfully!"

puts "======================================================================"
puts "  STARTING IMPLEMENTATION & BITSTREAM GENERATION (impl_1)..."
puts "======================================================================"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "\[ERROR\] Implementation or Bitstream generation failed! Check impl_1 run log."
    exit 1
}

# Copy bitstream to a convenient root location
set BIT_FILE [get_files -of_objects [get_runs impl_1] -filter {FILE_TYPE == "Bitstream File"}]
if {[file exists $BIT_FILE]} {
    file copy -force $BIT_FILE "$SCRIPT_DIR/pynq_z2_systolic_16x16.bit"
    puts "======================================================================"
    puts "  SUCCESS! BITSTREAM GENERATED AT:"
    puts "  $SCRIPT_DIR/pynq_z2_systolic_16x16.bit"
    puts "======================================================================"
} else {
    puts "\[WARNING\] Bitstream file generated inside impl_1 run directory."
}
