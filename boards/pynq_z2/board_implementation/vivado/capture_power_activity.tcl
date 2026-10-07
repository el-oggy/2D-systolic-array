# xsim Tcl: capture either a continuous workload or each real compute window.
# The caller sets MODE and PERIOD_NS through environment variables.
set mode $::env(POWER_ACTIVITY_MODE)
set period $::env(POWER_PERIOD_NS)
set pairs $::env(POWER_PAIRS)
set scope /$::env(POWER_TEST_TOP)/dut
set finished /$::env(POWER_TEST_TOP)/finished
set cycles 0
set windows 0
set_param tcl.collectionResultDisplayLimit 0
set fp [open $::env(POWER_ACTIVITY_SCOPES) r]
set modules [split [string trim [read $fp]] \n]
close $fp
set signals {}
set cache activity_objects.tcllist
set cache_signature activity_objects.signature
set use_cache 0
if {[info exists ::env(POWER_SCOPE_SIGNATURE)] && [file exists $cache] && [file exists $cache_signature]} {
    set fp [open $cache_signature r]
    set use_cache [expr {[string trim [read $fp]] eq $::env(POWER_SCOPE_SIGNATURE)}]
    close $fp
}
if {$use_cache} {
    set fp [open $cache r]
    set signals [read $fp]
    close $fp
    if {![llength $signals]} { error "Empty cached activity selection" }
} else {
set requested {}
foreach module $modules { dict set requested [string trim $module] 1 }
set seen {}
set queued [dict create . 1]
set queue [list [list . $scope]]
for {set index 0} {$index < [llength $queue]} {incr index} {
    if {$index%100==0} { puts "SAIF scope inventory: $index / [llength $modules]" }
    lassign [lindex $queue $index] module path
    current_scope $path
    set objects [get_objects -quiet *]
    if {![llength $objects]} { error "Implemented scope has no observable signals: $path" }
    lappend signals {*}$objects
    dict set seen $module 1
    # Use simulator scope handles verbatim. Escaped SV identifiers have doubled
    # backslashes and terminator spaces here, including vendor names with '/'.
    foreach child [get_scopes -quiet *] {
        set name [string range [get_property NAME $child] [expr {[string length $scope]+1}] end]
        set name [string map [list \\ "" " " ""] $name]
        if {[dict exists $requested $name] && ![dict exists $queued $name]} {
            lappend queue [list $name $child]
            dict set queued $name 1
        }
    }
}
foreach module [dict keys $requested] {
    if {![dict exists $seen $module]} { error "Implemented scope missing from timing simulation: $module" }
}
set signals [lsort -unique $signals]
if {[info exists ::env(POWER_SCOPE_SIGNATURE)]} {
    set fp [open $cache w]; puts $fp $signals; close $fp
    set fp [open $cache_signature w]; puts $fp $::env(POWER_SCOPE_SIGNATURE); close $fp
}
}
current_scope /$::env(POWER_TEST_TOP)
puts "SAIF: [llength $signals] implemented signals in [llength $modules] module scopes"
if {$mode eq "transaction"} {
    open_saif transaction.saif
    log_saif $signals
    run all
    close_saif
} else {
    set candidates [get_objects -r $scope/*array_en*]
    if {![llength $candidates]} { error "No compute enable available in routed netlist" }
    set compute [lindex $candidates 0]
    puts "COMPUTE ENABLE: $compute"
    set fp [open compute_window_signal.txt w]
    puts $fp $compute
    puts $fp "Event-driven capture at routed compute-enable transitions; aggregate enabled intervals"
    close $fp
    set recording 0
    # Conditions execute at actual signal changes, avoiding a clock-period
    # polling offset and hundreds of thousands of Tcl run calls.
    add_condition -name compute_begin -notrace "$compute == 1" {
        if {!$recording} {
            open_saif [format "compute_%04d.saif" $windows]
            log_saif $signals
            set recording 1
        }
    }
    add_condition -name compute_end -notrace "$compute == 0" {
        if {$recording} {
            close_saif
            incr windows
            set recording 0
        }
    }
    run all
    if {[get_value -radix bin $finished] ne "1"} { error "Workload did not finish" }
    if {$recording} { close_saif; incr windows }
    set fp [open capture_complete.txt w]
    puts $fp $windows
    close $fp
    if {$windows != $pairs} { error "Expected $pairs compute windows, got $windows" }
}
quit
