# Args: candidate_dir SAIF output_prefix testbench_top
lassign $argv candidate_dir saif prefix test_top
set candidate_dir [file normalize $candidate_dir]
open_checkpoint [file join $candidate_dir routed.dcp]
read_saif -strip_path ${test_top}/dut -out_file ${prefix}_coverage.rpt $saif
report_power -hier all -hierarchical_depth 8 -file ${prefix}_power.rpt
report_switching_activity -all -file ${prefix}_switching.rpt
report_clocks -file ${prefix}_clocks.rpt
exit 0
