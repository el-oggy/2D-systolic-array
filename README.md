<p align="center">
  <img src="2D-systolic-array/block_diagram.png" alt="2D Systolic Array Architecture" width="700"/>
</p>

<h1 align="center">⚡ 2D Systolic Array — Edge AI Accelerator</h1>

<p align="center">
  <strong>High-Performance N×N Matrix Multiplication Engine in Verilog & SystemVerilog for Edge AI Inference</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/HDL-Verilog%20%7C%20SystemVerilog-blue?style=for-the-badge&logo=v&logoColor=white" alt="Verilog"/>
  <img src="https://img.shields.io/badge/Simulator-Icarus%20Verilog%20%7C%20Vivado-orange?style=for-the-badge" alt="Icarus Verilog"/>
  <img src="https://img.shields.io/badge/FPGA%20Target-Digilent%20Basys%203%20(Artix--7)-red?style=for-the-badge&logo=xilinx&logoColor=white" alt="Basys 3"/>
  <img src="https://img.shields.io/badge/Platforms-macOS%20%7C%20Windows%20%7C%20Linux-brightgreen?style=for-the-badge" alt="Platforms"/>
  <img src="https://img.shields.io/badge/Matrix-N×N%20Configurable-purple?style=for-the-badge" alt="NxN"/>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="MIT License"/></a>
</p>

<p align="center">
  <a href="#-overview">Overview</a> •
  <a href="#-architecture">Architecture</a> •
  <a href="#-installation--setup">Setup Guide</a> •
  <a href="#-simulation--verification">Simulate</a> •
  <a href="#-fpga-deployment">FPGA</a> •
  <a href="#-research-papers">Research</a> •
  <a href="#-team--contributing">Team & Git</a>
</p>

---

## 🧠 Overview

The **2D Systolic Array Accelerator** is a high-throughput, low-power spatial computing core designed for **Matrix Multiplication ($C = A \times B$)** — the foundational mathematical workload driving deep learning, convolutional neural networks (CNNs), transformers, and digital signal processing (DSP) at the edge.

Inspired by the spatial architecture of Google's Tensor Processing Unit (TPU), this engine delivers **maximum data reuse** and **deterministic latency** on resource-constrained embedded platforms and FPGAs.

### 🌟 Key Highlights

| Feature | Specification | Architectural Advantage |
|---|---|---|
| ⚡ **Compute Latency** | `3N - 1` Clock Cycles | Fully pipelined wave-front execution with zero stall bubbles |
| 🔄 **Memory Bandwidth** | $N\times$ Data Reuse | Operands are fetched once from memory and streamed across the PE grid |
| 📐 **Precision & Sizing** | Parameterized $N\times N$, INT8/INT16 | Configurable `DATA_WIDTH` (default 8-bit signed) with auto-sized 16-bit accumulators |
| 🛡️ **Zero Arithmetic Overflow** | $2 \times \text{DATA\_WIDTH}$ Registers | Prevents precision degradation across deep dot-product accumulations |
| 🎯 **FPGA Ready** | Digilent Basys 3 (Artix-7 XC7A35T) | Complete board wrapper, switch matrix selector, and 4-digit 7-segment display driver |
| 💻 **Cross-Platform** | macOS, Windows, Linux | Verified on **Icarus Verilog (`iverilog`)**, **GTKWave**, and **AMD Vivado** |

---

## 🏗️ Architecture

<p align="center">
  <img src="2D-systolic-array/flowchart.png" alt="FSM Controller Flowchart" width="500"/>
</p>

### System Dataflow

```
                    ┌─────────────────────────────────────────────┐
                    │              systolic_top                    │
                    │                                             │
  Matrix A ──────► │  ┌────────────┐    ┌──────────────────┐     │
  (Row Stream)      │  │ Skew Buf A │──►│                  │     │
                    │  └────────────┘   │   N×N Systolic   │     │──► Result Matrix C
  Matrix B ──────► │  ┌────────────┐   │      Array       │     │    (A × B)
  (Col Stream)      │  │ Skew Buf B │──►│   (PE Grid)      │     │
                    │  └────────────┘   └──────────────────┘     │
                    │       ▲                    ▲                │
  Start ─────────► │  ┌────┴────────────────────┴───┐            │
  Pulse             │  │     FSM Controller          │──► Done Pulse
                    │  │  IDLE → LOAD → COMPUTE → DONE │         │
                    │  └────────────────────────────────┘         │
                    └─────────────────────────────────────────────┘
```

### Module Hierarchy

| Module | Verilog (`.v`) | SystemVerilog (`.sv`) | Core Role |
|---|---|---|---|
| **Processing Element (PE)** | [`1_pe.v`](./2D-systolic-array/1_pe.v) | [`processing_element.sv`](./simulation/src/processing_element.sv) | Multiply-Accumulate unit (`acc += a * b`) with 1-cycle pipeline forwarding |
| **Systolic Array** | [`3_systolic_array.v`](./2D-systolic-array/3_systolic_array.v) | [`systolic_array.sv`](./simulation/src/systolic_array.sv) | Parametric $N \times N$ 2D spatial grid with automated interconnect routing |
| **Skew Buffer** | [`5_skew_buffer.v`](./2D-systolic-array/5_skew_buffer.v) | [`skew_buffer.sv`](./simulation/src/skew_buffer.sv) | Triangular delay lines ($0, 1, \dots, N-1$ delays) for wave-front timing |
| **Controller** | [`6_controller.v`](./2D-systolic-array/6_controller.v) | [`controller.sv`](./simulation/src/controller.sv) | 4-state deterministic FSM sequencing execution phases and handshakes |
| **Top Wrapper** | [`7_systolic_top.v`](./2D-systolic-array/7_systolic_top.v) | [`systolic_top.sv`](./simulation/src/systolic_top.sv) | Integrated hardware accelerator top-level system |

---

## 🛠️ Installation & Setup

Expand your operating system below for 1-click installation commands and environment variable setup:

<details>
<summary><b>🍎 macOS Setup (MacBook Pro / Air — Apple Silicon M1/M2/M3/M4 & Intel)</b></summary>

<br>

#### 1. Install Homebrew (if not already installed)
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### 2. Ensure Homebrew is in your Shell PATH
```bash
# For Apple Silicon (M1/M2/M3/M4):
(echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# For Intel Macs:
(echo; echo 'eval "$(/usr/local/bin/brew shellenv)"') >> ~/.zprofile
eval "$(/usr/local/bin/brew shellenv)"
```

#### 3. Install Icarus Verilog & GTKWave
```bash
brew install icarus-verilog
brew install --cask gtkwave
```

> [!TIP]
> **Fixing macOS Gatekeeper for GTKWave:**  
> If macOS blocks GTKWave (*"unidentified developer"*), run:  
> `sudo xattr -d com.apple.quarantine /Applications/gtkwave.app`  
> *(Or use the **WaveTrace (Waveform Viewer)** extension directly inside VS Code).*

#### 4. Verify Installation
```bash
iverilog -v && vvp -v
```

</details>

<details>
<summary><b>🪟 Windows Setup (with PATH Troubleshooting Guide)</b></summary>

<br>

#### 1. Download & Install Icarus Verilog
1. Download the Windows installer from [bleyer.org/icarus](http://bleyer.org/icarus/) (e.g. `iverilog-v12-20220611-x64_setup.exe`).
2. Run the installer and check the box: ☑ **"Add executable folder(s) to system PATH"**.
3. Complete installation to `C:\iverilog`.

#### 2. Troubleshooting: If `'iverilog' is not recognized`
If your terminal cannot find `iverilog`, add the binaries to your Windows PATH:

* **Method A (GUI):**
  1. Press `Win + R`, type `sysdm.cpl`, press Enter.
  2. Go to **Advanced** → **Environment Variables...**.
  3. Under *User* or *System* variables, select `Path` → click **Edit...**.
  4. Click **New** and add: `C:\iverilog\bin`
  5. Click **New** again and add: `C:\iverilog\gtkwave\bin`
  6. Click **OK** on all windows and **restart VS Code / Terminal**.

* **Method B (PowerShell One-Liner as Admin):**
  ```powershell
  [System.Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\iverilog\bin;C:\iverilog\gtkwave\bin", [System.EnvironmentVariableTarget]::Machine)
  ```

#### 3. Verify Installation
```powershell
iverilog -v
vvp -v
```

</details>

<details>
<summary><b>🐧 Linux Setup (Ubuntu / Debian / Fedora / Arch)</b></summary>

<br>

```bash
# Ubuntu / Debian / Linux Mint:
sudo apt update && sudo apt install -y iverilog gtkwave

# Fedora / RHEL:
sudo dnf install -y iverilog gtkwave

# Arch Linux / Manjaro:
sudo pacman -S iverilog gtkwave

# Verify:
iverilog -v && which iverilog
```

</details>

---

## 🔬 Simulation & Verification

Every testbench in this project is verified and automated. Choose your desired test suite:

### 📁 Suite 1: Core Verilog RTL (`2D-systolic-array/`)

```bash
cd 2D-systolic-array
```

| Testbench | Description | Compile & Run Commands |
|---|---|---|
| **PE Unit Test** | Validates MAC unit (`acc += a*b`) & 1-cycle forwarding | `iverilog -o pe_tb.vvp 1_pe.v 2_pe_tb.v`<br>`vvp pe_tb.vvp` |
| **2×2 Systolic Grid** | Validates 2D wave-front propagation across 4 PEs | `iverilog -o systolic_2x2.vvp 1_pe.v 3_systolic_array.v 4_systolic_2x2_tb.v`<br>`vvp systolic_2x2.vvp` |
| **Full 4×4 System** | Full autonomous accelerator (FSM + Skew Buffers + 16 PEs) | `iverilog -o systolic_4x4.vvp 1_pe.v 3_systolic_array.v 5_skew_buffer.v 6_controller.v 7_systolic_top.v 8_systolic_4x4_tb.v`<br>`vvp systolic_4x4.vvp` |

*(To view waveforms, add `gtkwave <filename>.vcd` after running simulation).*

---

### 📁 Suite 2: Advanced SystemVerilog & Vivado Suite (`simulation/`)

> [!NOTE]
> SystemVerilog files (`.sv`) require the **`-g2012`** flag in Icarus Verilog.

```bash
cd simulation
```

<details>
<summary><b>View SystemVerilog Testbench Commands (Steps 1 to 5)</b></summary>

<br>

* **Step 1 — Processing Element:**
  ```bash
  iverilog -g2012 -o tb_step1_pe.vvp src/processing_element.sv sim/tb_step1_pe.sv && vvp tb_step1_pe.vvp
  ```
* **Step 2 — 2×2 Systolic Array Grid:**
  ```bash
  iverilog -g2012 -o tb_step2_2x2.vvp src/processing_element.sv src/systolic_array.sv sim/tb_step2_systolic_2x2.sv && vvp tb_step2_2x2.vvp
  ```
* **Step 3 — Input Skew Buffer Delay Line:**
  ```bash
  iverilog -g2012 -o tb_step3_skew.vvp src/skew_buffer.sv sim/tb_step3_skew_buffer.sv && vvp tb_step3_skew.vvp
  ```
* **Step 4 — Full 4×4 Autonomous Top System:**
  ```bash
  iverilog -g2012 -o tb_step4_4x4.vvp src/processing_element.sv src/systolic_array.sv src/skew_buffer.sv src/controller.sv src/systolic_top.sv sim/tb_step4_systolic_4x4.sv && vvp tb_step4_4x4.vvp
  ```
* **Step 5 — Extended 8×8 Systolic Array (64 PEs):**
  ```bash
  iverilog -g2012 -o tb_step5_8x8.vvp src/processing_element.sv src/systolic_array.sv src/skew_buffer.sv src/controller.sv src/systolic_top.sv sim/tb_step5_systolic_8x8.sv && vvp tb_step5_8x8.vvp
  ```

</details>

---

## 🎯 FPGA Deployment (Digilent Basys 3)

The design is synthesizable and tested for the **Xilinx Artix-7 (XC7A35T-1CPG236C)** FPGA.

* **FPGA Top Wrapper:** [`simulation/fpga_basys3/basys3_demo_top.sv`](./simulation/fpga_basys3/basys3_demo_top.sv)  
  *Includes on-chip ROM matrix storage, button triggers, and slide switch matrix index selectors.*
* **7-Segment Display Controller:** [`simulation/fpga_basys3/seven_segment_ctrl.sv`](./simulation/fpga_basys3/seven_segment_ctrl.sv)  
  *Displays computed 16-bit output matrix values in hexadecimal format across 4 multiplexed digits.*
* **Physical Constraints:** [`simulation/fpga_basys3/basys3_constraints.xdc`](./simulation/fpga_basys3/basys3_constraints.xdc)  
  *Complete pin mappings for 100MHz system clock, pushbuttons, LEDs, slide switches, and 7-segment cathodes/anodes.*
* 📖 **Hardware & Vivado Manual:** [[Download Complete Vivado Guide PDF](./assets/2D_Systolic_Array_Vivado_Complete_Guide.pdf)]

---

## 🧪 Verification Matrix

| Test Suite | Scope | Inputs / Dimensions | Test Status |
|---|---|---|---|
| **PE Unit Test** | Atomic MAC math, zero-reset, forwarding registers | Scalar dot-product $[1,2,3] \cdot [7,10,13] = 66$ | ✅ **PASS** |
| **2×2 Systolic Grid** | Spatial wave-front dataflow & diagonal accumulation | 2×2 Dense Matrix Multiplication | ✅ **PASS** |
| **Skew Buffer** | Triangular delay line timing ($0, 1, \dots, N-1$) | 3×3 Staggered Matrix Conversion | ✅ **PASS** |
| **Identity GEMM** | Autonomous FSM + Skew Buffers | $A \times I = A$ (4×4 & 8×8) | ✅ **PASS** |
| **Scalar Scaling** | Arithmetic linearity & precision verification | $A \times 2I = 2A$ | ✅ **PASS** |
| **Dense GEMM** | Arbitrary signed integer multiplication vs Golden Model | 4×4 & 8×8 Random Signed Matrices | ✅ **PASS** |

---

## 📚 Research Papers

The architecture is built on foundational and cutting-edge academic literature located in [`research_papers/`](./research_papers/):

1. **MPX: A Unified Systolic Array for Matrix and Polynomial Multiplication** — George Alexakis, Dimitrios Schoinianakis, Giorgos Dimitrakopoulos (*Democritus Univ. & Nokia Bell Labs*). [[PDF](./research_papers/EXTRA_Alexakis2026_MPX_UnifiedSystolicArray.pdf)]
2. **Systolic Array Based Accelerator and Algorithm Mapping for Deep Learning** — Zhijie Yang et al. (*Springer CCF-THPC*). [[PDF](./research_papers/EXTRA_Yang2018_SystolicArray_AcceleratorMapping.pdf)]
3. **Photonic Systolic Array for All-Optical Matrix–Matrix Multiplication** — Jungmin Kim, Qingyi Zhou, Zongfu Yu (*Laser & Photonics Reviews, 2025/2026*). [[PDF](./research_papers/EXTRA_Kim2025_Photonic_Systolic_Array.pdf)]
4. **Literature Survey - 2D Systolic Array-Based Processing Elements** [[PDF](./Literature%20Survey%20-%202D%20Systolic%20Array-Based%20Processing%20Elements.pdf)]
5. **2D Systolic Array Innovation Ideas Report** [[PDF](./2D_Systolic_Array_Innovation_Ideas_Report.pdf)]

> [!TIP]
> **Adding Future Research Papers:**  
> Drop new `.pdf` files into [`research_papers/`](./research_papers/), add a brief summary to [`research_papers/README.md`](./research_papers/README.md), and reference them in this section.

---

## 🤝 Team & Contributing

### Team Members

| Member | Role |
|---|---|
| **Adarsh** | Team Lead / RTL Architecture & FPGA Implementation |
| **Gulam** | Team Member |
| **Yamini** | Team Member |
| **Arpita** | Team Member |
| **Srikanth** | Team Member |

### 🌿 Git Branching Workflow

```
main (protected — stable releases only)
  └── feature/<name>/<task-description>  ──► Open Pull Request (PR) for Review
```

```bash
# 1. Pull latest main
git checkout main && git pull origin main

# 2. Create your feature branch
git checkout -b feature/<your-name>/<feature-name>

# 3. Commit and push
git add . && git commit -m "feat: add systolic optimization"
git push origin feature/<your-name>/<feature-name>
```

---

## 📜 License

This project is licensed under the **MIT License** — see the [`LICENSE`](./LICENSE) file for details.

---

<p align="center">
  <strong>Built with 💡 for Edge AI Hackathon 2026</strong><br/>
  <sub>Accelerating AI at the Edge — One Systolic Array at a Time</sub>
</p>
