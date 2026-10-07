# ============================================================================
# Vivado Block Design Script for PYNQ-Z2 Option 2 Dual-Engine Systolic Accelerator
# Target: Xilinx Zynq-7000 (XC7Z020CLG400-1)
# Features:
# - Plan B: Symmetrical 110/110 DSP partition across Engine 0 and Engine 1
# - Plan C: Single Unified AXI DMA MM2S/S2MM streaming channel
# - Plan A: BRAM-First Memory Mapping with pure Verilog IP Integrator wrapper
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
if {$script_dir eq "" || $script_dir eq "."} {
    set script_dir [file normalize [file join [pwd] "board_implementation/vivado"]]
}
if {![info exists bd_name]} { set bd_name "pynq_z2_dual_gemm_bd" }
if {![info exists power_clock_mhz]} { set power_clock_mhz 100.0 }
if {![info exists power_dsp_limit]} { set power_dsp_limit 110 }
if {$power_clock_mhz ni {100 100.0 75 75.0 50 50.0}} { error "Unsupported PL clock" }
if {$power_dsp_limit ni {110 96 80 64}} { error "Unsupported symmetric DSP limit" }

# 1. Clean up any previous or half-built design canvas
if {[current_bd_design -quiet] ne ""} {
    catch {close_bd_design [current_bd_design]}
}
if {[get_files -quiet *$bd_name.bd] ne ""} {
    remove_files [get_files -quiet *$bd_name.bd]
}

# 2. Ensure all project RTL sources and the pure Verilog (.v) wrapper are added.
#    Vivado IP Integrator requires .v for top-level module references (ERROR 56-195).
set wrapper_path [file normalize [file join $script_dir "../../src/accel_top_wrapper.v"]]
if {[get_files -quiet *accel_top_wrapper.v] eq ""} {
    puts "Adding accel_top_wrapper.v to project sources..."
    add_files -norecurse [list $wrapper_path]
    update_compile_order -fileset sources_1
}

# 3. Create fresh block design
create_bd_design $bd_name
current_bd_design $bd_name

# 4. Processing System 7 (Zynq ARM Cortex-A9 on PYNQ-Z2)
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:* processing_system7_0]
make_bd_intf_pins_external [get_bd_intf_pins processing_system7_0/DDR]
make_bd_intf_pins_external [get_bd_intf_pins processing_system7_0/FIXED_IO]
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $power_clock_mhz \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART0_UART0_IO {MIO 14 .. 15} \
] $ps

# 5. Reset and Clock Infrastructure
set reset [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* proc_sys_reset_0]

set reset_locked [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* reset_locked_0]
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $reset_locked

# 6. AXI Interconnects (4-port GP0 for DMA, Accel Engine, LEDs, and RGB LEDs)
set gp_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:* axi_interconnect_gp0]
set_property -dict [list CONFIG.NUM_MI {4}] $gp_ic

set hp_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:* axi_interconnect_hp0]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] $hp_ic

# 7. Single AXI DMA (Plan C: feeds both engines concurrently via Unified BRAM Feeder)
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:* axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_s2mm_burst_size {16} \
] $dma

# 8. Unified Dual-Engine Systolic GEMM Accelerator (Plan B: 512 MACs, 110/110 DSPs)
set accel [create_bd_cell -type module -reference accel_top_wrapper accel_engine]
set_property -dict [list \
    CONFIG.ARRAY_ROWS {16} \
    CONFIG.ARRAY_COLS {16} \
    CONFIG.TILE_K {16} \
    CONFIG.DATA_WIDTH {8} \
    CONFIG.ACC_WIDTH {20} \
    CONFIG.DSP_PE_LIMIT_0 $power_dsp_limit \
    CONFIG.DSP_PE_LIMIT_1 $power_dsp_limit \
] $accel

# 8b. Physical Board LED Peripherals (4 User LEDs LD0-LD3, 2 RGB LEDs LD4-LD5)
set leds_gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* leds_gpio]
set_property -dict [list \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_GPIO_WIDTH {4} \
] $leds_gpio

set rgbleds_gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* rgbleds_gpio]
set_property -dict [list \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_GPIO_WIDTH {6} \
] $rgbleds_gpio

# External Interface Ports for LEDs
set leds_4bits [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 leds_4bits]
connect_bd_intf_net [get_bd_intf_pins leds_gpio/GPIO] [get_bd_intf_ports leds_4bits]

set rgbleds_6bits [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 rgbleds_6bits]
connect_bd_intf_net [get_bd_intf_pins rgbleds_gpio/GPIO] [get_bd_intf_ports rgbleds_6bits]

# 9. Interrupt Concentrator (3 channels: DMA MM2S, DMA S2MM, Accel stream done)
set irq_concat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:* irq_concat_0]
set_property -dict [list CONFIG.NUM_PORTS {3}] $irq_concat

# 10. Clocks: 100 MHz PL clock shared across CPU, DMA, accelerator, and interconnects
set clocks [list \
    processing_system7_0/FCLK_CLK0 \
    processing_system7_0/M_AXI_GP0_ACLK \
    processing_system7_0/S_AXI_HP0_ACLK \
    proc_sys_reset_0/slowest_sync_clk \
    axi_interconnect_gp0/ACLK axi_interconnect_gp0/S00_ACLK \
    axi_interconnect_gp0/M00_ACLK axi_interconnect_gp0/M01_ACLK \
    axi_interconnect_gp0/M02_ACLK axi_interconnect_gp0/M03_ACLK \
    axi_interconnect_hp0/ACLK axi_interconnect_hp0/M00_ACLK \
    axi_interconnect_hp0/S00_ACLK axi_interconnect_hp0/S01_ACLK \
    axi_dma_0/s_axi_lite_aclk axi_dma_0/m_axi_mm2s_aclk axi_dma_0/m_axi_s2mm_aclk \
    leds_gpio/s_axi_aclk rgbleds_gpio/s_axi_aclk \
    accel_engine/clk]

connect_bd_net {*}[lmap pin $clocks {get_bd_pins $pin}]

# 11. Resets
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins proc_sys_reset_0/ext_reset_in]
connect_bd_net [get_bd_pins reset_locked_0/dout] [get_bd_pins proc_sys_reset_0/dcm_locked]

set resets [list \
    axi_interconnect_gp0/ARESETN axi_interconnect_gp0/S00_ARESETN \
    axi_interconnect_gp0/M00_ARESETN axi_interconnect_gp0/M01_ARESETN \
    axi_interconnect_gp0/M02_ARESETN axi_interconnect_gp0/M03_ARESETN \
    axi_interconnect_hp0/ARESETN axi_interconnect_hp0/M00_ARESETN \
    axi_interconnect_hp0/S00_ARESETN axi_interconnect_hp0/S01_ARESETN \
    axi_dma_0/axi_resetn leds_gpio/s_axi_aresetn rgbleds_gpio/s_axi_aresetn accel_engine/rst_n]

connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] {*}[lmap pin $resets {get_bd_pins $pin}]

# 12. PS Control Plane: CPU master connects to DMA Lite, Accelerator Lite, and LED GPIOs
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins axi_interconnect_gp0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_gp0/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_gp0/M01_AXI] [get_bd_intf_pins accel_engine/s_axi]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_gp0/M02_AXI] [get_bd_intf_pins leds_gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_gp0/M03_AXI] [get_bd_intf_pins rgbleds_gpio/S_AXI]

# 13. AXI-Stream Data Streaming: Single full-duplex DMA MM2S and S2MM channel
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins accel_engine/s_axis]
connect_bd_intf_net [get_bd_intf_pins accel_engine/m_axis] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# 14. High-Performance Memory Bus: DMA MM2S & S2MM share HP0 port into DDR3 RAM
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins axi_interconnect_hp0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins axi_interconnect_hp0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_hp0/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# 15. Interrupt Wiring: DMA and Accel interrupts to PS IRQ_F2P
connect_bd_net [get_bd_pins axi_dma_0/mm2s_introut] [get_bd_pins irq_concat_0/In0]
connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut] [get_bd_pins irq_concat_0/In1]
connect_bd_net [get_bd_pins accel_engine/interrupt] [get_bd_pins irq_concat_0/In2]
connect_bd_net [get_bd_pins irq_concat_0/dout] [get_bd_pins processing_system7_0/IRQ_F2P]

# 16. Assign Memory-Mapped Addresses
create_bd_addr_seg -range 64K -offset 0x40000000 [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs accel_engine/s_axi/reg0] SEG_accel_engine_reg0
create_bd_addr_seg -range 64K -offset 0x40400000 [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_dma_0/S_AXI_LITE/Reg] SEG_axi_dma_0_Reg
create_bd_addr_seg -range 64K -offset 0x41200000 [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs leds_gpio/S_AXI/Reg] SEG_leds_gpio_Reg
create_bd_addr_seg -range 64K -offset 0x41240000 [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs rgbleds_gpio/S_AXI/Reg] SEG_rgbleds_gpio_Reg

# Assign DDR address space for the DMA MM2S and S2MM channels
assign_bd_address [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM]
validate_bd_design
regenerate_bd_layout
save_bd_design

# 17. Generate Block Design HDL Wrapper and set as Project Top
set bd_file [get_files -all *$bd_name.bd]
generate_target all $bd_file
set wrapper_file [make_wrapper -files $bd_file -top]
add_files -norecurse [list $wrapper_file]
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

# Remove standalone OOC constraint if present (PS FCLK clocks the full board system)
set ooc_xdc [get_files -quiet *accel_dual_axi_top_ooc.xdc]
if {[llength $ooc_xdc]} {
    remove_files $ooc_xdc
}

puts "=================================================================="
puts " SUCCESS: Option 2 Block Design '$bd_name' Generated & Set as Top!"
puts " Top Module: ${bd_name}_wrapper"
puts " Unified Dual-Engine Accelerator (512 MACs, 110/110 DSPs), Single DMA, and PS7 fully wired."
puts "=================================================================="
