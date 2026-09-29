# PYNQ-Z2 16x16 Systolic Array Accelerator Hardware User Guide

**Target Board:** TUL PYNQ-Z2  
**FPGA Device:** Xilinx Zynq-7000 SoC (`xc7z020clg400-1`)  
**Core Scale:** 16x16 Grid = 256 Processing Elements (PEs)  
**Clock Frequency:** 125 MHz On-board Oscillator (`sysclk`, Pin `H16`)  
**Deterministic Compute Latency:** 48 Clock Cycles (384 ns @ 125 MHz)

---

## 1. Hardware Pin Mapping Summary

| Signal Name | PYNQ-Z2 Hardware | Pin Location | I/O Standard | Description |
| :--- | :--- | :--- | :--- | :--- |
| `sysclk` | 125 MHz Clock | **H16** | LVCMOS33 | Primary System Oscillator |
| `btn[0]` | Push Button 0 | **D19** | LVCMOS33 | **Synchronous Reset** |
| `btn[1]` | Push Button 1 | **D20** | LVCMOS33 | **Start 16x16 Execution Pulse** |
| `btn[2]` | Push Button 2 | **L20** | LVCMOS33 | **Step Matrix Inspection Index** |
| `btn[3]` | Push Button 3 | **L19** | LVCMOS33 | **Mode Toggle** |
| `sw[0]` | Slide Switch 0 | **M20** | LVCMOS33 | Matrix Preset Selection Bit 0 |
| `sw[1]` | Slide Switch 1 | **M19** | LVCMOS33 | Matrix Preset Selection Bit 1 |
| `led[0]` | Single LED 0 | **R14** | LVCMOS33 | **Heartbeat (Blinks @ ~1.86 Hz)** |
| `led[1]` | Single LED 1 | **P14** | LVCMOS33 | **Busy Computing (48 Cycles)** |
| `led[2]` | Single LED 2 | **N16** | LVCMOS33 | **DONE Flag (Latched)** |
| `led[3]` | Single LED 3 | **M14** | LVCMOS33 | **256/256 Verification PASS** |
| `rgbled4` | RGB LED 4 | **M15, T16, Q15** | LVCMOS33 | **Core State (Blue=Idle, Amber=Busy, Green=PASS)** |
| `rgbled5` | RGB LED 5 | **L15, F16, G14** | LVCMOS33 | **Pattern Color (Cyan, Magenta, Yellow, White)** |
| `uart_tx` | PMOD A Pin 1 | **Y18** | LVCMOS33 | **115200 Baud Diagnostic Reporter** |

---

## 2. Test Pattern Selection (`sw[1:0]`)

Configure the two slide switches (`sw[1]` and `sw[0]`) to select which test matrix multiplication to perform:

| `sw[1]` | `sw[0]` | RGB LED 5 Color | Matrix Test Mode | Mathematical Verification Check |
| :---: | :---: | :--- | :--- | :--- |
| `0` | `0` | **Cyan** | Matrix $A \times$ Identity $I_{16}$ | Result $C = A$. Verifies diagonal propagation & timing. |
| `0` | `1` | **Magenta** | Matrix $A \times 2 \times$ Identity | Result $C = 2A$. Verifies scaling arithmetic in PEs. |
| `1` | `0` | **Yellow** | Dense Signed INT8 GEMM | General dense matrix multiply with positive and negative numbers. |
| `1` | `1` | **White** | All-Ones Stress Test | $A_{ij}=1 \times B_{ij}=1 \implies C_{ij}=16$ for all 256 cells. |

---

## 3. How to Run the 16x16 Matrix Multiplication on Hardware

1. **Connect & Power On**:
   * Connect the PYNQ-Z2 board via Micro-USB to your computer.
   * Power on the board.
2. **Program the Bitstream**:
   * Open Vivado Hardware Manager or use `scripts/open_pynq_z2_vivado.bat`.
   * Open Target -> Auto Connect -> Program Device using `boards/pynq_z2/pynq_z2_systolic_16x16.bit`.
3. **Verify Power-On State**:
   * `led[0]` (LD0) immediately starts blinking smoothly at ~1.86 Hz. This confirms the FPGA bitstream is loaded and running on the 125 MHz clock.
   * `rgbled4` (LD4) glows **Solid Blue** (indicating `IDLE` state, ready for computation).
   * `rgbled5` (LD5) displays the color of the selected switch mode.
4. **Trigger Computation**:
   * Set `sw[1:0]` to your desired test preset (e.g., `00` for Identity test).
   * Press `btn[1]` (Start button).
   * `led[1]` (LD1) flashes on and `rgbled4` pulses **Amber** while the 256 PEs compute in parallel.
   * In 48 clock cycles (384 nanoseconds), computation finishes:
     * `led[2]` (LD2) lights up **Solid Bright** (DONE flag).
     * `led[3]` (LD3) lights up **Solid Bright** (256/256 Verification PASS).
     * `rgbled4` turns **Vibrant Solid Green** (Success)!
5. **Inspect Individual Results**:
   * Press `btn[2]` to step through the 256 matrix elements one-by-one.
6. **View Serial Terminal Output**:
   * Connect a 3.3V USB-to-UART adapter to PMOD A Pin 1 (Pin `Y18`) and GND.
   * Open PuTTY / Serial Monitor at **115200 Baud, 8N1**.
   * When `btn[1]` is pressed, the accelerator streams: `16x16 GEMM: PASS\n`.
