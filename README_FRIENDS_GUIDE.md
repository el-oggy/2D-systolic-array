# 16x16 2D Systolic Array Hardware Accelerator — Quick Start Guide

Welcome! This package contains the complete, self-contained 16x16 2D Systolic Array Matrix Multiplication Hardware Accelerator for FPGA.

---

## 1. Directory Structure

- **`boards/pynq_z2/`** : Complete implementation for TUL PYNQ-Z2 (Zynq-7000 `xc7z020clg400-1`).
  - `board_implementation/` : Top module with ROM test matrices & status LEDs (`pynq_z2_demo_16x16_top.sv`) + master XDC constraints (`pynq_z2_constraints.xdc`).
  - `src/` : All core synthesizable RTL modules.
  - `sim/` : Standalone 16x16 testbench + OOP verification suite.
- **`boards/basys3/`** : Complete implementation for Digilent Basys 3 (Artix-7 `xc7a35tcpg236-1`).
  - `board_implementation/` : Top module with 7-segment display + constraints (`basys3_constraints.xdc`).
  - `src/` : All core synthesizable RTL modules.
  - `sim/` : Unit testbenches (Step 1 to Step 6).
- **`rtl/`** : Centralized synthesizable RTL source files.
- **`scripts/`** : One-click batch simulation scripts (`run_sim_16x16.bat`, `run_oop_verification.bat`).
- **`docs/`** : The complete PDF guide (`16x16_Systolic_Array_Vivado_Simulation_Guide.pdf`).

---

## 2. Quick Simulation in 1 Click (No Vivado GUI Needed)

Just double-click either batch script in the `scripts/` folder:
1. **`scripts/run_sim_16x16.bat`** : Runs the standalone 16x16 testbench (validates Identity $A \times I = A$, Scaled $A \times 2I = 2A$, and Dense Signed GEMM across all 256 PEs).
2. **`scripts/run_oop_verification.bat`** : Runs the 30-transaction randomized enterprise OOP verification suite (7,680 individual output element checks).

---

## 3. Opening in Vivado 2025.1 GUI

1. Open Vivado 2025.1 -> **Create Project** -> **RTL Project**.
2. Select your device:
   - For PYNQ-Z2: **`xc7z020clg400-1`**
   - For Basys 3: **`xc7a35tcpg236-1`**
3. **Add Design Sources**: Add all files in `boards/pynq_z2/src/` plus `boards/pynq_z2/board_implementation/pynq_z2_demo_16x16_top.sv`.
4. **Add Constraints**: Add `boards/pynq_z2/board_implementation/pynq_z2_constraints.xdc`.
5. **Add Simulation Sources**: Add `boards/pynq_z2/sim/tb_step6_systolic_16x16.sv`.
6. **To Run Simulation**:
   - Right-click `tb_step6_systolic_16x16.sv` in Sources -> **Set as Top**.
   - Click **Run Simulation -> Run Behavioral Simulation**.
7. **To Generate Bitstream for Hardware**:
   - Right-click `pynq_z2_demo_16x16_top.sv` in Sources -> **Set as Top**.
   - Click **Generate Bitstream**.

See `16x16_Systolic_Array_Vivado_Simulation_Guide.pdf` for the complete guide with timing diagrams and hardware controls!
