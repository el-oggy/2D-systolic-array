# Out-of-context constraint for the two-engine PYNQ accelerator IP.
# In the Zynq block design the AXI and stream interfaces use FCLK_CLK0;
# board-level pin locations belong only to the standalone demo top.
if {![info exists power_clock_mhz]} { set power_clock_mhz 100.0 }
create_clock -name core_clk -period [expr {1000.0 / $power_clock_mhz}] [get_ports clk]
# Reserve 1 ns at each input/output boundary for the OOC interface budget.
# The integrated block design uses the PS FCLK and system-level constraints.
set_input_delay -clock core_clk -max 1.000 [get_ports -filter {DIRECTION == IN && NAME != clk} *]
set_input_delay -clock core_clk -min 0.000 [get_ports -filter {DIRECTION == IN && NAME != clk} *]
set_output_delay -clock core_clk -max 1.000 [get_ports -filter {DIRECTION == OUT} *]
set_output_delay -clock core_clk -min 0.000 [get_ports -filter {DIRECTION == OUT} *]
