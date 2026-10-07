# Args: candidate_dir. Never substitutes an old bitstream or ignores timing.
lassign $argv candidate_dir
set candidate_dir [file normalize $candidate_dir]
set script_dir [file dirname [file normalize [info script]]]
set qualification_python python
if {[info exists ::env(PYNQ_POWER_PYTHON)] && $::env(PYNQ_POWER_PYTHON) ne ""} {
    set qualification_python $::env(PYNQ_POWER_PYTHON)
}
exec $qualification_python -E [file join $script_dir qualify_candidate.py] $candidate_dir
open_checkpoint [file join $candidate_dir routed.dcp]
report_drc -file [file join $candidate_dir drc_pre_bitstream.rpt]
if {[llength [get_drc_violations -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]]} {
    error "Critical DRCs block write_bitstream"
}
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[get_property SLACK $setup]<0 || [get_property SLACK $hold]<0} { error "Routed timing blocks write_bitstream" }
write_bitstream -force [file join $candidate_dir adaptive_gemm.bit]
if {![file exists [file join $candidate_dir adaptive_gemm.bit]]} { error "Missing newly written bitstream" }
puts "Matching candidate bitstream written; run pynq/benchmark_power.py before claiming board verification"
if {![info exists candidate_batch_mode] || $candidate_batch_mode} { exit 0 }
