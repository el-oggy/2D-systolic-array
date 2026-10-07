## ==============================================================================
## PYNQ-Z2 LED Constraints for User LEDs (LD0-LD3) and Dual RGB LEDs (LD4-LD5)
## Target: Xilinx Zynq-7000 (xc7z020clg400-1)
## ==============================================================================

## 4 Individual Green User LEDs (LD0 - LD3)
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { leds_4bits_tri_o[0] }];
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { leds_4bits_tri_o[1] }];
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { leds_4bits_tri_o[2] }];
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { leds_4bits_tri_o[3] }];

## Dual Multi-color RGB LEDs (LD4: bits 0-2, LD5: bits 3-5)
## Standard PYNQ RGBLED mapping: bit 0 = Blue, bit 1 = Green, bit 2 = Red
set_property -dict { PACKAGE_PIN L15   IOSTANDARD LVCMOS33 } [get_ports { rgbleds_6bits_tri_o[0] }]; ## LD4 Blue
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { rgbleds_6bits_tri_o[1] }]; ## LD4 Green
set_property -dict { PACKAGE_PIN N15   IOSTANDARD LVCMOS33 } [get_ports { rgbleds_6bits_tri_o[2] }]; ## LD4 Red

set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports { rgbleds_6bits_tri_o[3] }]; ## LD5 Blue
set_property -dict { PACKAGE_PIN L14   IOSTANDARD LVCMOS33 } [get_ports { rgbleds_6bits_tri_o[4] }]; ## LD5 Green
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { rgbleds_6bits_tri_o[5] }]; ## LD5 Red
