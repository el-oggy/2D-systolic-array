# GUI entry point. CODEX_VALIDATE_ONLY=1 only generates/validates the BD.
set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ../..]]
if {[info exists ::env(CODEX_VALIDATE_ONLY)] && $::env(CODEX_VALIDATE_ONLY) eq "1"} {
    source [file join $script_dir create_project.tcl]
    source [file join $script_dir block_design.tcl]
    puts "Block design validated; implementation and power are unverified."
} else {
    source [file join $script_dir run_sim_synth_impl.tcl]
}
