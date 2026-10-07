# Export only a separately qualified isolated candidate. Never reuse an old bit.
if {![info exists candidate_dir]} {
    error "Set candidate_dir to the routed/activity-qualified candidate directory first"
}
set script_dir [file dirname [file normalize [info script]]]
set argv [list $candidate_dir]
set candidate_batch_mode 0
source [file join $script_dir write_qualified_bitstream.tcl]
