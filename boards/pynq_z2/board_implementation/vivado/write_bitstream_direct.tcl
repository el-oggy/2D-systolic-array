# Standalone script to generate the final bitstream and hardware handoff
# from the already routed implementation checkpoint.

set script_dir [file dirname [file normalize [info script]]]
if {$script_dir eq "" || $script_dir eq "."} {
    set script_dir [file normalize [file join [pwd] "board_implementation/vivado"]]
}
set project_root [file normalize [file join $script_dir ../..]]

set dcp_file [file join $project_root "prj/pynq_gemm.runs/impl_1/pynq_z2_dual_gemm_bd_wrapper_routed.dcp"]
if {![file exists $dcp_file]} {
    error "Routed checkpoint not found: $dcp_file"
}

puts "Opening routed checkpoint: $dcp_file..."
open_checkpoint $dcp_file

set results_dir [file join $project_root "results"]
file mkdir $results_dir

# Ensure top-level DRC does not treat this design as an out-of-context module
catch {set_property IS_OUT_OF_CONTEXT 0 [current_design]}

puts "Generating bitstream: [file join $results_dir adaptive_gemm.bit]..."
write_bitstream -force [file join $results_dir adaptive_gemm.bit]

# Copy hardware handoff (.hwh)
set hwh_files [glob -nocomplain -directory [file join $project_root prj] [file join ** *.hwh]]
if {[llength $hwh_files] > 0} {
    file copy -force [lindex $hwh_files 0] [file join $results_dir adaptive_gemm.hwh]
    puts "Copied HWH: [lindex $hwh_files 0] -> [file join $results_dir adaptive_gemm.hwh]"
}

puts "=================================================================="
puts " SUCCESS: Option 2 Bitstream Generated!"
puts " Bitstream: [file join $results_dir adaptive_gemm.bit]"
puts "=================================================================="
