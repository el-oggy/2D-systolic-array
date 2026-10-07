# A minimal environment probe; it does not inspect or modify accelerator RTL.
puts "VIVADO VERSION: [version -short]"
set probe_dir [file normalize [lindex $argv 0]]
create_project tool_probe $probe_dir -part xc7z020clg400-1
if {[catch {create_bd_design probe} message options]} {
    puts "IP INTEGRATOR ENVIRONMENT FAILURE: $message"
    puts [dict get $options -errorinfo]
    exit 1
}
puts "IP INTEGRATOR ENVIRONMENT PASS"
exit 0
