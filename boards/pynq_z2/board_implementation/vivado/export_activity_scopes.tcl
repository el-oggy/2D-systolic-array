# Called with the routed design open and candidate_dir defined. Record only
# implemented module scopes: UNISIM model bookkeeping is not a physical net.
# Nets connecting primitive ports are present in their parent module scope.
set fp [open [file join $candidate_dir activity_scopes.txt] w]
puts $fp .
foreach cell [lsort [get_cells -hier -filter {IS_PRIMITIVE == 0}]] {
    puts $fp [get_property NAME $cell]
}
close $fp
