# Add the implemented-scope inventory to an already exported candidate.
lassign $argv candidate_dir
set candidate_dir [file normalize $candidate_dir]
open_checkpoint [file join $candidate_dir routed.dcp]
source [file join [file dirname [info script]] export_activity_scopes.tcl]
exit 0
