# 2D Systolic Array Accelerator — Vivado Simulation & Hardware Guide

This directory contains the Vivado-ready implementation and verification suite for an **$N \times N$ 2D Systolic Array Matrix Multiplication Accelerator**, along with FPGA deployment files for the **Digilent Basys 3 (Artix-7 XC7A35T)** board.

---

## 1. Directory Structure

```
simulation/
├── src/                               # Synthesizable RTL Design Sources (.sv)
│   ├── processing_element.sv          # MAC processing element + forwarding registers
│   ├── systolic_array.sv              # Parametric N x N 2D spatial grid
│   ├── skew_buffer.sv                 # Input matrix skewing/delay line buffer
│   ├── controller.sv                  # FSM controller (IDLE -> LOAD -> COMPUTE -> DONE)
│   └── systolic_top.sv                # Complete integrated top-level accelerator
├── sim/                               # Step-by-Step Simulation Testbenches
│   ├── tb_step1_pe.sv                 # Step 1: Single PE MAC and register verification
│   ├── tb_step2_systolic_2x2.sv       # Step 2: 2x2 Array spatial wave-front dataflow
│   ├── tb_step3_skew_buffer.sv        # Step 3: Input skewing & staggering verification
│   └── tb_step4_systolic_4x4.sv       # Step 4: Full 4x4 top-level automated testbench
├── fpga_basys3/                       # Hardware Implementation for Basys 3 FPGA
│   ├── basys3_demo_top.sv             # Top wrapper with ROM matrices, switches, LEDs
│   ├── seven_segment_ctrl.sv          # 4-Digit 7-Segment display multiplexer
│   └── basys3_constraints.xdc         # Basys 3 pin mappings (Clock, Buttons, Switches, 7-Seg)
├── scripts/
│   ├── run_sim_cli.bat                # 1-Click Command-Line runner for all simulations
│   └── run_sim.tcl                    # Vivado Tcl script for GUI simulation
└── README_SIMULATION_GUIDE.md         # This comprehensive documentation
```

---

## 2. Why the Original Code Failed in Vivado & What Was Fixed

| Issue in Previous Attempt | Root Cause | Fix Applied |
| :--- | :--- | :--- |
| **`[VRFC 10-3642] port must not be declared to be an array`** | Unpacked array ports (`input wire [7:0] a_in [0:N-1]`) are **SystemVerilog** syntax, but files had `.v` (Verilog) extension. | Upgraded all design and testbench files to `.sv` with SystemVerilog type definitions. |
| **`[XSIM 43-4099] Module doesn't have a timescale`** | Vivado requires matching timescale across every file in the design hierarchy. | Added `` `timescale 1ns / 1ps `` explicitly across all source files. |
| **`[DRC NSTD-1] & [DRC UCIO-1] Unconstrained Ports`** | Attempting to synthesize 256 I/O pins directly to FPGA pins without a board wrapper. | Created `basys3_demo_top.sv` with on-chip ROM, switch-based matrix element selector, and 7-segment display. |

---

## 3. Step-by-Step Simulation Flow

### **STEP 1: Single Processing Element (`tb_step1_pe.sv`)**
- **Goal**: Verify that one PE multiplies two 8-bit signed inputs, adds to its internal accumulator, and forwards inputs horizontally and vertically with 1 clock cycle latency.
- **Test vector**: Computes dot product $[1, 2, 3] \cdot [7, 10, 13] = 1\times7 + 2\times10 + 3\times13 = 66$.

### **STEP 2: 2×2 Systolic Array Grid (`tb_step2_systolic_2x2.sv`)**
- **Goal**: Verify spatial wave-front propagation across a $2 \times 2$ grid with manually skewed inputs.
- **Test vector**: Multiplies $\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix} \times \begin{pmatrix} 5 & 6 \\ 7 & 8 \end{pmatrix} = \begin{pmatrix} 19 & 22 \\ 43 & 50 \end{pmatrix}$.

### **STEP 3: Skew Buffer (`tb_step3_skew_buffer.sv`)**
- **Goal**: Verify that flat parallel matrices are converted into correctly staggered serial streams ($0$ delay for row 0, $1$ delay for row 1, etc.).

### **STEP 4: Full System 4×4 Verification (`tb_step4_systolic_4x4.sv`)**
- **Goal**: Validates autonomous top-level operation using FSM controller and skew buffers.
- **Automated Tests**:
  1. $A \times I = A$ (Identity matrix)
  2. $A \times 2I = 2A$ (Scalar multiplication)
  3. General Dense Matrix Multiplication against automated software golden model.

---

## 4. How to Run Simulation in Vivado GUI (Step-by-Step)

1. **Open Vivado** (e.g. Vivado 2025.1 or 2024.x).
2. **Create a New Project**:
   - File -> Project -> New...
   - Name: `systolic_array_sim`
   - Project Type: **RTL Project** (Do not specify sources yet).
   - Default Part: Select **Basys 3** or part **`xc7a35tcpg236-1`**.
3. **Add Design Sources**:
   - Under *Flow Navigator* -> Click **Add Sources** -> *Add or create design sources*.
   - Add all files from `simulation/src/`:
     - `processing_element.sv`
     - `systolic_array.sv`
     - `skew_buffer.sv`
     - `controller.sv`
     - `systolic_top.sv`
   - *Ensure Type is set to SystemVerilog*.
4. **Add Simulation Testbenches**:
   - Click **Add Sources** -> *Add or create simulation sources*.
   - Add testbenches from `simulation/sim/`:
     - `tb_step1_pe.sv`
     - `tb_step2_systolic_2x2.sv`
     - `tb_step3_skew_buffer.sv`
     - `tb_step4_systolic_4x4.sv`
5. **Set the Active Testbench**:
   - In the *Sources* window, expand `Simulation Sources` -> `sim_1`.
   - Right-click the desired testbench (e.g. `tb_step4_systolic_4x4`) and select **Set as Top**.
6. **Run Behavioral Simulation**:
   - In the *Flow Navigator*, click **Run Simulation** -> **Run Behavioral Simulation**.
   - In the Vivado Tcl Console or Waveform Viewer, click **Run All** (`F3` or icon with infinite arrow).
   - Check the Tcl Console to see the printed pass/fail matrix tables and waveform timings.

---

## 5. How to Run via Command-Line / VS Code Terminal (1 Click)

You can run the entire simulation suite directly without opening the heavy Vivado GUI:

1. Open PowerShell or Command Prompt in `simulation/scripts`.
2. Run:
   ```cmd
   run_sim_cli.bat
   ```
3. All 4 simulation steps will compile and execute with complete output logs printed to your console.

---

## 6. How to Deploy to Basys 3 FPGA Board

When you are ready to generate a bitstream and program the Basys 3 board:

1. In Vivado, add the hardware sources from `simulation/fpga_basys3/`:
   - `basys3_demo_top.sv` (Set as Top)
   - `seven_segment_ctrl.sv`
   - `basys3_constraints.xdc` (Add as Constraint file)
2. Click **Generate Bitstream** in Vivado. It will run Synthesis, Implementation, and DRC checks with **0 Errors**.
3. Connect your Basys 3 board via USB and open **Hardware Manager** -> **Program Device**.
4. **Interactive Controls on Board**:
   - **`btnC`** (Center Button): Reset array.
   - **`btnU`** (Top Button): Trigger start pulse.
   - **`sw[1:0]`**: Select Matrix Test Case:
     - `00`: $A \times I$ (Identity)
     - `01`: $A \times 2I$ (Double Matrix)
     - `10`: Dense General Matrix Multiply
   - **`sw[5:4]`** & **`sw[3:2]`**: Select Row & Column $(i, j)$ to inspect.
   - **7-Segment Display**: Shows the 16-bit result element $C[i][j]$ in Hexadecimal format.
   - **`led[0]`**: Lights up when computation is DONE.
