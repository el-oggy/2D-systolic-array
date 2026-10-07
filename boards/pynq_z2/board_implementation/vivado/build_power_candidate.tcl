# Isolated board route and simulation export. No artifact is published here.
# Args: candidate_dir DSP_limit clock_MHz power_opt(0/1) placed_base_or_empty threads
lassign $argv candidate_dir power_dsp_limit power_clock_mhz power_opt resume_placed_dir power_build_threads
set project_root [file normalize [file join [file dirname [info script]] ../..]]
set candidate_dir [file normalize $candidate_dir]
file mkdir $candidate_dir
if {[file exists [file join $candidate_dir synthesized.dcp]] || [file exists [file join $candidate_dir routed.dcp]]} {
    error "Existing candidate checkpoints must be preserved; choose a new directory"
}
if {$power_build_threads eq ""} { set power_build_threads 1 }
if {![string is integer -strict $power_build_threads] || $power_build_threads ni {1 2 4}} {
    error "Build threads must be 1, 2 or 4"
}
# Multiple synthesis workers duplicate substantial design state. Default to
# one on this 8 GB Windows host; this changes tool scheduling, not the RTL.
set_param general.maxThreads $power_build_threads
if {[current_project -quiet] ne ""} { close_project }
if {$resume_placed_dir ne ""} {
    if {!$power_opt} { error "Placed-checkpoint reuse is only for the explicit power-opt comparison" }
    set resume_placed_dir [file normalize $resume_placed_dir]
    open_checkpoint [file join $resume_placed_dir placed.dcp]
    set pl_clock [get_clocks -quiet clk_fpga_0]
    if {[llength $pl_clock]!=1 || abs([get_property PERIOD $pl_clock]-1000.0/$power_clock_mhz)>0.001} {
        error "Placed checkpoint clock does not match the requested candidate"
    }
    set handoff [file join $resume_placed_dir adaptive_gemm.hwh]
    if {![file exists $handoff]} { error "Matching base handoff missing" }
    file copy $handoff [file join $candidate_dir adaptive_gemm.hwh]
} else {
create_project p [file join $candidate_dir project] -part xc7z020clg400-1 -force
# Short generated names avoid Vivado's 260-byte Windows path limit.
set bd_name b
source [file join $project_root board_implementation/vivado/create_project.tcl]
source [file join $project_root board_implementation/vivado/block_design.tcl]
add_files -fileset constrs_1 -norecurse [file join $project_root board_implementation/constraints/pynq_z2_leds.xdc]
set_property GENERATE_SYNTH_CHECKPOINT false [get_files */${bd_name}.bd]
synth_design -top ${bd_name}_wrapper -part xc7z020clg400-1
}
report_utilization -hierarchical -file [file join $candidate_dir utilization_synth_hier.rpt]
set feeder_cells [get_cells -hier -filter {NAME =~ */u_feeder/* && REF_NAME =~ RAM*}]
set tile_lutram [filter $feeder_cells {REF_NAME =~ RAMD* || REF_NAME =~ RAMS*}]
set feeder_bram [filter $feeder_cells {REF_NAME =~ RAMB*}]
if {[llength $tile_lutram] || ![llength $feeder_bram]} { error "Feeder did not map exclusively to BRAM" }
set dsp_cells [get_cells -hier -filter {REF_NAME == DSP48E1}]
if {[llength $dsp_cells] != 2*$power_dsp_limit} { error "Unexpected DSP count [llength $dsp_cells]" }
foreach engine {u_engine_0 u_engine_1} {
    set engine_dsps [get_cells -hier -filter "NAME =~ */$engine/* && REF_NAME == DSP48E1"]
    if {[llength $engine_dsps] != $power_dsp_limit} { error "Unexpected $engine DSP count" }
}
set pe_cells [get_cells -hier -filter {NAME =~ *gen_row*.gen_col*.u_pe && IS_PRIMITIVE == 0}]
if {[llength $pe_cells] != 512} { error "Expected 512 physical PE instances, got [llength $pe_cells]" }
if {$resume_placed_dir eq ""} {
    write_checkpoint -force [file join $candidate_dir synthesized.dcp]
    opt_design
    place_design
}
write_checkpoint -force [file join $candidate_dir placed.dcp]
if {$power_opt} { power_opt_design }
phys_opt_design
route_design
write_checkpoint -force [file join $candidate_dir routed.dcp]
report_utilization -file [file join $candidate_dir utilization_routed.rpt]
report_timing_summary -report_unconstrained -file [file join $candidate_dir timing_routed.rpt]
report_route_status -file [file join $candidate_dir route_status.rpt]
report_drc -file [file join $candidate_dir drc.rpt]
report_power -file [file join $candidate_dir power_vectorless.rpt]
set setup_paths [get_timing_paths -delay_type max -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1]
set wns [get_property SLACK $setup_paths]
set whs [get_property SLACK $hold_paths]
set critical [get_drc_violations -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]
set fp [open [file join $candidate_dir route_status.json] w]
puts $fp "{\"clock_mhz\": $power_clock_mhz, \"dsp_per_engine\": $power_dsp_limit, \"power_opt\": $power_opt, \"wns_ns\": $wns, \"whs_ns\": $whs, \"critical_drc\": [llength $critical], \"power_validated\": false}"
close $fp
set core [get_cells -hier -filter {NAME =~ */u_dual_top && IS_PRIMITIVE == 0}]
if {[llength $core] != 1} { error "Cannot locate accelerator cell for timing simulation" }
write_verilog -force -mode timesim -sdf_anno false -cell $core -rename_top accel_sim [file join $candidate_dir accel_timesim.v]
write_sdf -force -process_corner slow -cell $core -rename_top accel_sim [file join $candidate_dir accel_timesim.sdf]
set fp [open [file join $candidate_dir accelerator_instance.txt] w]
puts $fp $core
close $fp
if {$resume_placed_dir eq ""} {
    set bd_hwh [file join $candidate_dir project p.gen sources_1 bd $bd_name hw_handoff ${bd_name}.hwh]
    if {![file exists $bd_hwh]} { error "Expected matching HWH missing: $bd_hwh" }
    file copy -force $bd_hwh [file join $candidate_dir adaptive_gemm.hwh]
}
puts "ROUTE COMPLETE: WNS=$wns WHS=$whs; power activity and signoff still required"
if {$wns < 0 || $whs < 0 || [llength $critical]} { error "Candidate rejected: routed timing or critical DRC failure" }
if {![info exists candidate_batch_mode] || $candidate_batch_mode} { exit 0 }
