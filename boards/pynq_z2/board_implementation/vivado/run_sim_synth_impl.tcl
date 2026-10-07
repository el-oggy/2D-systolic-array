# GUI entry point: checked behavioral simulation, then isolated board routing.
# Power activity and coverage qualification precede bitstream export.
set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ../..]]
source [file join $script_dir create_project.tcl]
set_property top tb_power_regression [get_filesets sim_1]
update_compile_order -fileset sim_1
if {[current_sim -quiet] ne ""} { close_sim -force }
launch_simulation -simset sim_1 -mode behavioral
run all
if {[get_value -radix bin /tb_power_regression/finished] ne "1"} {
    error "Self-checking simulation failed or did not finish"
}
close_sim -force
if {![info exists candidate_dir]} {
    set candidate_dir [file join $project_root results power_optimization gui_[clock seconds]]
}
if {![info exists power_dsp_limit]} { set power_dsp_limit 110 }
if {![info exists power_clock_mhz]} { set power_clock_mhz 100 }
if {![info exists power_opt]} { set power_opt 0 }
set argv [list $candidate_dir $power_dsp_limit $power_clock_mhz $power_opt]
set candidate_batch_mode 0
source [file join $script_dir build_power_candidate.tcl]
puts "Routed candidate: $candidate_dir. Run timing activity and coverage qualification before write_qualified_bitstream.tcl."
