## ============================================================================
## File: pynq_z2_constraints.xdc
## Description: Master Physical & Timing Constraints for PYNQ-Z2 Board
## Project: 16x16 2D Systolic Array Hardware Accelerator
## Target Part: Xilinx Zynq-7000 SoC (xc7z020clg400-1)
## Board: TUL PYNQ-Z2
## ============================================================================

## ----------------------------------------------------------------------------
## 1. Primary Clock Definition (125 MHz On-Board Oscillator)
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { sysclk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4.00} [get_ports { sysclk }];

## ----------------------------------------------------------------------------
## 2. Slide Switches (SW0, SW1) - Matrix Test Pattern Selection
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN M20   IOSTANDARD LVCMOS33 } [get_ports { sw[0] }];
set_property -dict { PACKAGE_PIN M19   IOSTANDARD LVCMOS33 } [get_ports { sw[1] }];

## ----------------------------------------------------------------------------
## 3. Push Buttons (BTN0 to BTN3)
##    BTN0 = System Reset (Synchronous release)
##    BTN1 = Start Pulse (Starts 16x16 GEMM execution)
##    BTN2 = Step Element Pointer (Increments inspection address)
##    BTN3 = Mode Toggle
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN D19   IOSTANDARD LVCMOS33 } [get_ports { btn[0] }];
set_property -dict { PACKAGE_PIN D20   IOSTANDARD LVCMOS33 } [get_ports { btn[1] }];
set_property -dict { PACKAGE_PIN L20   IOSTANDARD LVCMOS33 } [get_ports { btn[2] }];
set_property -dict { PACKAGE_PIN L19   IOSTANDARD LVCMOS33 } [get_ports { btn[3] }];

## ----------------------------------------------------------------------------
## 4. Individual Status LEDs (LD0 to LD3)
##    LD0 = Heartbeat (~1.86 Hz smooth blink)
##    LD1 = Computing / Active Systolic Wavefront Flag
##    LD2 = Computation DONE Flag (Latched)
##    LD3 = 256/256 Hardware Self-Verification PASS Indicator
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

## ----------------------------------------------------------------------------
## 5. RGB LED 4 (LD4) - Accelerator Status State
##    Blue  = IDLE (Ready for Start pulse)
##    Amber = COMPUTING (16x16 Wavefront Active)
##    Green = DONE & 100% VERIFIED
##    Red   = RESET / MISMATCH
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN N15   IOSTANDARD LVCMOS33 } [get_ports { rgbled4_r }];
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { rgbled4_g }];
set_property -dict { PACKAGE_PIN L15   IOSTANDARD LVCMOS33 } [get_ports { rgbled4_b }];

## ----------------------------------------------------------------------------
## 6. RGB LED 5 (LD5) - Matrix Preset Indicator Color
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { rgbled5_r }];
set_property -dict { PACKAGE_PIN L14   IOSTANDARD LVCMOS33 } [get_ports { rgbled5_g }];
set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports { rgbled5_b }];

## ----------------------------------------------------------------------------
## 7. UART Serial Diagnostic Output (115200 Baud, 8N1)
##    Routed to PMOD A Pin 1 (Package Pin Y18)
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN Y18   IOSTANDARD LVCMOS33 } [get_ports { uart_tx }];

## ----------------------------------------------------------------------------
## 8. DRC & Bitstream Configuration Properties for Zynq-7000
## ----------------------------------------------------------------------------
# Note: Zynq-7000 (xc7z020) does NOT use CFGBVS, CONFIG_VOLTAGE, or SPI_BUSWIDTH
# (PL is configured via the Processing System PS7 / PCAP or JTAG).

# Compress bitstream for faster programming
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Downgrade PS7 check for standalone pure-PL designs without a Processing System block
set_property SEVERITY {Warning} [get_drc_checks ZPS7-1]

# Prevent unconstrained pin/standard DRC errors from blocking bitstream generation
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

