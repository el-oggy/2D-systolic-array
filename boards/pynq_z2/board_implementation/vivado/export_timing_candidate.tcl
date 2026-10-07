# Re-export simulation files from an existing isolated routed checkpoint.
lassign $argv candidate_dir
set candidate_dir [file normalize $candidate_dir]
open_checkpoint [file join $candidate_dir routed.dcp]
set pl_clock [get_clocks -quiet clk_fpga_0]
if {[llength $pl_clock]!=1} { error "Expected one source PL clock in routed checkpoint" }
set period [get_property PERIOD $pl_clock]
set fp [open [file join $candidate_dir routed_clock.json] w]
puts $fp "{\"period_ns\": $period, \"frequency_mhz\": [expr {1000.0/$period}]}"
close $fp
set core [get_cells -hier -filter {NAME =~ */u_dual_top && IS_PRIMITIVE == 0}]
if {[llength $core] != 1} { error "Expected one accelerator instance, got $core" }
write_verilog -force -mode timesim -sdf_anno false -cell $core -rename_top accel_sim [file join $candidate_dir accel_timesim.v]
write_sdf -force -process_corner slow -cell $core -rename_top accel_sim [file join $candidate_dir accel_timesim.sdf]
set fp [open [file join $candidate_dir accelerator_instance.txt] w]
puts $fp $core
close $fp
set hwh [file join $candidate_dir project p.gen sources_1 bd b hw_handoff b.hwh]
if {[file exists $hwh]} {
    file copy -force $hwh [file join $candidate_dir adaptive_gemm.hwh]
} elseif {![file exists [file join $candidate_dir adaptive_gemm.hwh]]} {
    error "Matching handoff missing"
}
write_verilog -force -mode timesim -sdf_anno false -rename_top board_sim [file join $candidate_dir board_timesim.v]
write_sdf -force -process_corner slow -rename_top board_sim [file join $candidate_dir board_timesim.sdf]
set ps [get_cells -hier -filter {REF_NAME == PS7}]
if {[llength $ps] != 1} { error "Cannot locate one PS7 primitive" }
set hierarchy "dut"
foreach segment [split $ps /] {
    if {[regexp {^[a-zA-Z_][a-zA-Z0-9_$]*$} $segment]} {
        append hierarchy ".$segment"
    } else { append hierarchy ".\\$segment " }
}
set fp [open [file join $candidate_dir ps7_binding.vh] w]
puts $fp "`define PS $hierarchy"
close $fp
source [file join [file dirname [info script]] export_activity_scopes.tcl]
if {[info exists ::env(PYNQ_POWER_PYTHON)] && $::env(PYNQ_POWER_PYTHON) ne ""} {
    set manifest_python $::env(PYNQ_POWER_PYTHON)
} else {
    set manifest_python python
}
# Vivado prepends its Python 3.13 libraries to the environment. Ignore Python
# environment variables when invoking a separately installed interpreter.
exec $manifest_python -E [file join [file dirname [info script]] write_export_manifest.py] $candidate_dir
exit 0
