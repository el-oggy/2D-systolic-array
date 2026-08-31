<p align="center">
  <img src="2D-systolic-array/block_diagram.png" alt="2D Systolic Array Architecture" width="700"/>
</p>

<h1 align="center">⚡ 2D Systolic Array — Edge AI Accelerator</h1>

<p align="center">
  <strong>High-performance N×N matrix multiplication engine in Verilog & SystemVerilog for Edge AI inference</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/HDL-Verilog%20%7C%20SystemVerilog-blue?style=for-the-badge&logo=v&logoColor=white" alt="Verilog"/>
  <img src="https://img.shields.io/badge/Simulator-Icarus%20Verilog%20%7C%20Vivado-orange?style=for-the-badge" alt="Icarus Verilog"/>
  <img src="https://img.shields.io/badge/Platforms-macOS%20%7C%20Windows%20%7C%20Linux-brightgreen?style=for-the-badge" alt="Platforms"/>
  <img src="https://img.shields.io/badge/Hackathon-Edge%20AI%202026-green?style=for-the-badge&logo=hackthebox&logoColor=white" alt="Edge AI 2026"/>
  <img src="https://img.shields.io/badge/Matrix-N×N%20Configurable-purple?style=for-the-badge" alt="NxN"/>
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="MIT"/>
</p>

<p align="center">
  <a href="#-architecture">Architecture</a> •
  <a href="#-installation--setup-guide">Installation & Setup</a> •
  <a href="#-how-to-simulate-all-files">Simulate All Files</a> •
  <a href="#-quick-start-for-team-members">Quick Start</a> •
  <a href="#-branching-strategy">Branching</a> •
  <a href="#-project-structure">Structure</a> •
  <a href="#-references--research">Research Papers</a> •
  <a href="#-team">Team</a>
</p>

---

## 🧠 What Is This?

A **2D Systolic Array** hardware accelerator designed for **matrix multiplication** — the core computation powering deep learning and edge neural network inference. Built from scratch in Verilog and SystemVerilog for the **Edge AI Hackathon 2026**.

> **Why Systolic Arrays?**  
> Google's Tensor Processing Unit (TPU) utilizes 2D systolic arrays to achieve massive parallelism with minimal memory bandwidth bottlenecks.  
> Our design brings this architectural paradigm to **edge devices** — ultra-low power, high computational throughput, and fully pipelined spatial computing.

### Key Features

| Feature | Description |
|---------|-------------|
| 🔧 **Parameterized N×N** | Configure any matrix size ($2\times2$, $4\times4$, $8\times8$, up to $N\times N$) |
| ⚡ **Fully Pipelined** | Computes $C = A \times B$ in just `3N - 1` clock cycles |
| 🧱 **Modular Architecture** | Processing Element (PE) → Systolic Grid → Skew Buffers → FSM Controller → Top Wrapper |
| 📐 **Configurable Precision** | Configurable `DATA_WIDTH` (default 8-bit signed INT8 for quantized AI models) |
| 🛡️ **Zero-Overflow Accumulator** | Auto-scaled `2 × DATA_WIDTH` accumulator registers |
| 💻 **Cross-Platform Support** | Ready for simulation on **macOS (Apple Silicon & Intel)**, **Windows**, and **Linux** |
| 🎯 **FPGA Ready** | Synthesis-verified with Digilent Basys 3 (Artix-7 XC7A35T) constraints & 7-segment display driver |

### 🌍 Applications

This architecture is versatile and accelerates linear algebra across multiple edge domains:
*   **Deep Learning Inference:** On-device CNN/Transformer GEMM (General Matrix Multiply) without cloud latency or bandwidth dependency.
*   **Digital Signal Processing (DSP):** Real-time FIR filtering, 2D spatial convolution, FFTs, and radar processing.
*   **Scientific & Embedded Computing:** Matrix solvers and physics simulations on micro-embedded platforms.
*   **5G/6G & Massive MIMO:** High-throughput beamforming weight computation and spatial signal detection.

### 💎 Value Proposition

*   **Optimal Data Reuse:** Each input weight and activation is fetched ONCE from memory and reused $N$ times across the PE grid, achieving an $N\times$ memory bandwidth reduction.
*   **Symmetric Delay-Line Skewing:** Reusable shift-register delay line buffers stagger inputs to ensure exact spatial-temporal wave-front synchronization.
*   **Zero Wasted Cycles:** The autonomous 4-phase FSM (`IDLE` → `LOAD` → `COMPUTE` → `DONE`) guarantees maximum PE utilization.

---

## 🏗️ Architecture

<p align="center">
  <img src="2D-systolic-array/flowchart.png" alt="FSM Flowchart" width="500"/>
</p>

The system consists of **4 core hardware modules** orchestrated by an FSM controller:

```
                    ┌─────────────────────────────────────────────┐
                    │              systolic_top                    │
                    │                                             │
  Matrix A ──────► │  ┌────────────┐    ┌──────────────────┐     │
  (Rows)            │  │ Skew Buf A │──►│                  │     │
                    │  └────────────┘   │   N×N Systolic   │     │──► Result C = A×B
  Matrix B ──────► │  ┌────────────┐   │      Array       │     │
  (Cols)            │  │ Skew Buf B │──►│   (PE Grid)      │     │
                    │  └────────────┘   └──────────────────┘     │
                    │       ▲                    ▲                │
  Start ─────────► │  ┌────┴────────────────────┴───┐            │
                    │  │     Controller FSM          │──► Done   │
                    │  │  IDLE → LOAD → COMPUTE → DONE │         │
                    │  └────────────────────────────────┘         │
                    └─────────────────────────────────────────────┘
```

### Module Hierarchy

| # | Module | Verilog Source | SystemVerilog Source | Purpose |
|---|--------|----------------|----------------------|---------|
| 1 | `PE` / `processing_element` | `2D-systolic-array/1_pe.v` | `simulation/src/processing_element.sv` | Multiply-Accumulate unit (`acc += a * b`) with 1-cycle pipeline forwarding registers |
| 2 | `systolic_array` | `2D-systolic-array/3_systolic_array.v` | `simulation/src/systolic_array.sv` | Parametric $N \times N$ spatial grid with automated interconnect wiring |
| 3 | `skew_buffer` | `2D-systolic-array/5_skew_buffer.v` | `simulation/src/skew_buffer.sv` | Staggers row and column inputs with triangular delay lines ($0, 1, 2, \dots, N-1$ cycles) |
| 4 | `controller` | `2D-systolic-array/6_controller.v` | `simulation/src/controller.sv` | Deterministic FSM sequencer managing execution phases and `done` handshake |
| 5 | `systolic_top` | `2D-systolic-array/7_systolic_top.v` | `simulation/src/systolic_top.sv` | Complete integrated top-level hardware accelerator wrapper |

---

## 🛠️ Installation & Setup Guide

Choose your operating system below for a complete, step-by-step setup guide.

### 🍎 macOS Setup (MacBook Pro / MacBook Air — Apple Silicon M1/M2/M3/M4 & Intel)

macOS users can install and run the entire verification suite in minutes using **Homebrew**.

#### Step 1: Install Homebrew (if not already installed)
Open **Terminal** (press `Cmd + Space`, type `Terminal`, and press Enter) and run:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### Step 2: Ensure Homebrew is in your Shell PATH
For **Apple Silicon (M1/M2/M3/M4)** Macs, add Homebrew to your environment:
```bash
(echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```
*(For older Intel-based Macs, Homebrew is located at `/usr/local/bin` and is usually configured automatically).*

#### Step 3: Install Icarus Verilog (`iverilog`) & `gtkwave`
```bash
# Install Icarus Verilog compiler and runtime (vvp)
brew install icarus-verilog

# Install GTKWave waveform viewer
brew install --cask gtkwave
```

> [!TIP]
> **Fixing macOS Gatekeeper for GTKWave:**  
> If macOS displays *"GTKWave cannot be opened because it is from an unidentified developer"*, run this command in Terminal to clear the quarantine flag:
> ```bash
> sudo xattr -d com.apple.quarantine /Applications/gtkwave.app
> ```
> *Alternative:* Open **System Settings** → **Privacy & Security** → scroll down to GTKWave and click **"Open Anyway"**.

> [!NOTE]
> **Recommended VS Code Extension (Zero-Install Waveforms on Mac):**  
> Install the **WaveTrace (Waveform Viewer)** or **TerosHDL** extension in VS Code to view `.vcd` waveform files directly inside your code editor without launching GTKWave.

#### Step 4: Verify Installation on macOS
```bash
iverilog -v
vvp -v
which iverilog
```
If version information appears, your MacBook is 100% ready to simulate!

---

### 🪟 Windows Setup (with PATH Configuration Guide)

#### Step 1: Download & Install Icarus Verilog
1. Download the Icarus Verilog Windows installer from [bleyer.org/icarus](http://bleyer.org/icarus/) (e.g. `iverilog-v12-20220611-x64_setup.exe`).
2. Run the installer.
3. **Important:** On the *"Select Additional Tasks"* screen, make sure to check the box:  
   ☑ **"Add executable folder(s) to system PATH"**
4. Complete the installation (default location: `C:\iverilog`).

---

#### 🔧 Troubleshooting: How to Fix "iverilog is not recognized as an internal or external command"

If you open Command Prompt / PowerShell / VS Code Terminal and see:
> `'iverilog' is not recognized as an internal or external command, operable program or batch file.`

This means the installation folder was not added to your Windows Environment Variables. Follow either method below to fix it:

#### Method A: GUI Setup (Recommended)
1. Press `Win + R`, type `sysdm.cpl`, and press **Enter** (or search for *"Edit the system environment variables"* in Windows search).
2. Go to the **Advanced** tab and click **"Environment Variables..."** at the bottom.
3. Under **User variables** (or **System variables**), find the variable named **`Path`** and click **Edit...**.
4. Click **New** on the right side and add the path to the Icarus Verilog binary folder:
   ```
   C:\iverilog\bin
   ```
5. Click **New** again and add the path to the GTKWave binary folder:
   ```
   C:\iverilog\gtkwave\bin
   ```
6. Click **OK** on all three open windows to save your changes.
7. **Restart VS Code or close and reopen your Terminal / PowerShell** for the new PATH to take effect.

#### Method B: One-Line PowerShell Command (Run as Administrator)
Open PowerShell as Administrator and run:
```powershell
[System.Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\iverilog\bin;C:\iverilog\gtkwave\bin", [System.EnvironmentVariableTarget]::Machine)
```

#### Step 2: Verify Installation on Windows
Open a **new** PowerShell or Command Prompt terminal and run:
```powershell
iverilog -v
vvp -v
where.exe iverilog
```
If both commands print version details, your Windows environment is fully configured!

---

### 🐧 Linux Setup (Ubuntu / Debian / Fedora / Arch)

```bash
# Ubuntu / Debian / Linux Mint:
sudo apt update
sudo apt install -y iverilog gtkwave

# Fedora / RHEL:
sudo dnf install -y iverilog gtkwave

# Arch Linux / Manjaro:
sudo pacman -S iverilog gtkwave

# Verify:
iverilog -v
which iverilog
```

---

## 🔬 How to Simulate (All Files & Commands)

All simulation files can be executed across macOS, Windows, and Linux. Below is the command reference for every single module and testbench in the project.

---

### 📁 Suite 1: Core Verilog RTL (`2D-systolic-array/`)

Navigate to the `2D-systolic-array` folder first:
```bash
cd 2D-systolic-array
```

#### 1️⃣ Single Processing Element (PE) Verification
* **Source Files:** `1_pe.v` (PE Module), `2_pe_tb.v` (Testbench)
* **What it tests:** Reset values, Multiply-Accumulate computation (`acc = acc + a * b`), 1-cycle horizontal/vertical data forwarding registers.
* **Commands:**
  ```bash
  # Compile
  iverilog -o pe_tb.vvp 1_pe.v 2_pe_tb.v

  # Run Simulation
  vvp pe_tb.vvp

  # Open Waveform (optional)
  gtkwave pe_tb.vcd
  ```

#### 2️⃣ 2×2 Systolic Array Grid Verification
* **Source Files:** `1_pe.v` (PE), `3_systolic_array.v` (2D Grid), `4_systolic_2x2_tb.v` (Testbench)
* **What it tests:** 2D spatial interconnect wiring and cycle-by-cycle wave-front data propagation across 4 PEs.
* **Commands:**
  ```bash
  # Compile
  iverilog -o systolic_2x2.vvp 1_pe.v 3_systolic_array.v 4_systolic_2x2_tb.v

  # Run Simulation
  vvp systolic_2x2.vvp

  # Open Waveform (optional)
  gtkwave systolic_2x2_tb.vcd
  ```

#### 3️⃣ Full 4×4 Systolic Accelerator System Verification
* **Source Files:** `1_pe.v`, `3_systolic_array.v`, `5_skew_buffer.v`, `6_controller.v`, `7_systolic_top.v`, `8_systolic_4x4_tb.v`
* **What it tests:** Full autonomous accelerator integration: FSM Controller (`LOAD` → `COMPUTE` → `DONE`), Skew Buffers, 16 PEs, self-checking matrix verification.
* **Commands:**
  ```bash
  # Compile all modules together
  iverilog -o systolic_4x4.vvp 1_pe.v 3_systolic_array.v 5_skew_buffer.v 6_controller.v 7_systolic_top.v 8_systolic_4x4_tb.v

  # Run Simulation
  vvp systolic_4x4.vvp

  # Open Waveform (optional)
  gtkwave systolic_4x4_tb.vcd
  ```

---

### 📁 Suite 2: Advanced SystemVerilog & Vivado Verification (`simulation/`)

> [!NOTE]
> SystemVerilog files (`.sv`) use modern syntax (e.g. 2D unpacked array ports, interfaces).  
> To compile them with **Icarus Verilog**, always include the **`-g2012`** flag!

From the project root:
```bash
cd simulation
```

#### Step 1 — Processing Element (`tb_step1_pe.sv`)
```bash
iverilog -g2012 -o tb_step1_pe.vvp src/processing_element.sv sim/tb_step1_pe.sv
vvp tb_step1_pe.vvp
```

#### Step 2 — 2×2 Systolic Grid (`tb_step2_systolic_2x2.sv`)
```bash
iverilog -g2012 -o tb_step2_2x2.vvp src/processing_element.sv src/systolic_array.sv sim/tb_step2_systolic_2x2.sv
vvp tb_step2_2x2.vvp
```

#### Step 3 — Skew Buffer Delay Lines (`tb_step3_skew_buffer.sv`)
```bash
iverilog -g2012 -o tb_step3_skew.vvp src/skew_buffer.sv sim/tb_step3_skew_buffer.sv
vvp tb_step3_skew.vvp
```

#### Step 4 — Full 4×4 Autonomous Accelerator (`tb_step4_systolic_4x4.sv`)
```bash
iverilog -g2012 -o tb_step4_4x4.vvp src/processing_element.sv src/systolic_array.sv src/skew_buffer.sv src/controller.sv src/systolic_top.sv sim/tb_step4_systolic_4x4.sv
vvp tb_step4_4x4.vvp
```

#### Step 5 — Extended 8×8 Systolic Array (64 PEs) (`tb_step5_systolic_8x8.sv`)
```bash
iverilog -g2012 -o tb_step5_8x8.vvp src/processing_element.sv src/systolic_array.sv src/skew_buffer.sv src/controller.sv src/systolic_top.sv sim/tb_step5_systolic_8x8.sv
vvp tb_step5_8x8.vvp
```

---

### ⚡ 1-Click Simulation Runners

* **Windows 1-Click Batch Runner:**  
  Double click or run `simulation/scripts/run_sim_cli.bat` to run all 5 SystemVerilog verification steps in sequence.
* **AMD Vivado GUI Runner:**  
  Run `vivado -mode gui -source simulation/scripts/run_sim.tcl` to launch behavioral simulations in Vivado.
* **Automated PDF Report Generator:**  
  Run `python simulation/scripts/generate_pdf_report.py` to regenerate verification summary reports.

---

## 🚀 Quick Start for Team Members

> [!CAUTION]
> **MANDATORY WORKFLOW:** The `main` branch is protected. You **cannot** push code directly to `main`. GitHub will block your push. You must *always* create a new branch, push your branch, and open a **Pull Request (PR)** for review.

### Step 1 — Clone the Repository

```bash
# Clone via HTTPS (easiest)
git clone https://github.com/el-oggy/2D-systolic-array-.git

# OR clone via SSH (if you have SSH keys set up)
git clone git@github.com:el-oggy/2D-systolic-array-.git

# Enter the project directory
cd 2D-systolic-array-
```

### Step 2 — Create Your Working Branch

```bash
# Always pull the latest main first
git checkout main
git pull origin main

# Create your feature branch (pick a naming convention below)
git checkout -b feature/<your-name>/<what-you-are-working-on>

# Examples:
git checkout -b feature/rahul/add-8x8-testbench
git checkout -b feature/priya/optimize-pe-pipeline
git checkout -b fix/adarsh/skew-buffer-timing
```

### Step 3 — Make Changes & Commit

```bash
# Check what you changed
git status
git diff

# Stage your changes
git add .

# Commit with a meaningful message
git commit -m "feat: add 8x8 systolic array testbench"

# Push your branch to GitHub
git push origin feature/<your-name>/<what-you-are-working-on>
```

### Step 4 — Open a Pull Request (MANDATORY)

1. Go to the repo on GitHub: [https://github.com/el-oggy/2D-systolic-array-](https://github.com/el-oggy/2D-systolic-array-)
2. Click **"Compare & pull request"** (a green banner appears after you push).
3. Write a description of what you changed and *why*.
4. **Important:** Request a review from the repository admin (Adarsh).
5. **Wait for Approval:** Once reviewed and approved, the admin merges the PR into `main`.

---

## 🐣 Beginner's Guide to Contributing (No Terminal Required!)

If you are contributing documentation or minor edits without command-line Git:

### Editing a File via GitHub Web
1. Navigate to the file on GitHub (e.g. `README.md`).
2. Click the **pencil icon** (✏️) in the top right corner.
3. Make your edits in the web editor.
4. Scroll down to **"Commit changes..."**.
5. Select **"Create a new branch for this commit and start a pull request"**.
6. Click **"Propose changes"** → **"Create pull request"**.

### Uploading New Documents or Research Papers
1. Navigate to the desired folder (e.g. `research/` or `assets/`).
2. Click **"Add file"** → **"Upload files"**.
3. Drag and drop your `.pdf` or image file.
4. Choose **"Create a new branch..."** and open a Pull Request.

---

## 🌿 Branching Strategy

```
main (protected — always stable)
  │
  ├── develop (integration branch — merge features here first)
  │     │
  │     ├── feature/rahul/add-8x8-testbench
  │     ├── feature/priya/optimize-pe-pipeline
  │     ├── feature/adarsh/add-relu-activation
  │     └── fix/adarsh/skew-buffer-timing
  │
  └── release/v1.0 (tagged releases for submission)
```

| Prefix | Use When | Example |
|--------|----------|---------|
| `feature/` | Adding new functionality | `feature/rahul/add-8x8-testbench` |
| `fix/` | Fixing a bug | `fix/priya/pe-overflow-fix` |
| `docs/` | Documentation only | `docs/adarsh/update-readme` |
| `experiment/` | Trying something new (may not merge) | `experiment/rahul/fp16-pe` |
| `refactor/` | Restructuring code without changing behavior | `refactor/priya/clean-controller` |

---

## 📁 Project Structure

```
2D-systolic-array-/
│
├── 📄 README.md                                  ← Complete Project & Setup Guide (You are here)
├── 📄 .gitignore                                 ← Git ignore rules (build artifacts, vvp, vcd)
├── 📄 2D_Systolic_Array_Innovation_Ideas_Report.pdf ← Innovation & Architecture Whitepaper
│
├── 📂 2D-systolic-array/                         ← Core Verilog RTL & Testbenches
│   ├── 1_pe.v                                    ← Processing Element (MAC + forwarding)
│   ├── 2_pe_tb.v                                 ← PE Testbench (Unit test)
│   ├── 3_systolic_array.v                        ← N×N Spatial Array Grid
│   ├── 4_systolic_2x2_tb.v                       ← 2×2 Array Verification Testbench
│   ├── 5_skew_buffer.v                           ← Triangular Input Skew Buffer
│   ├── 6_controller.v                            ← FSM Controller (IDLE/LOAD/COMPUTE/DONE)
│   ├── 7_systolic_top.v                          ← Top-Level Accelerator Wrapper
│   ├── 8_systolic_4x4_tb.v                       ← Full 4×4 System Testbench
│   ├── EDGE-AI_ABSTRACT_FILLED.docx              ← Official Hackathon Abstract
│   ├── Systolic_Array_Code_Explanation.pdf       ← In-depth Code Architecture Document
│   ├── block_diagram.png                         ← System Architecture Visual Diagram
│   └── flowchart.png                             ← FSM Flowchart Visual Diagram
│
├── 📂 simulation/                                ← SystemVerilog & Vivado Verification Suite
│   ├── src/                                      ← Synthesizable SystemVerilog Design Files (.sv)
│   │   ├── processing_element.sv
│   │   ├── systolic_array.sv
│   │   ├── skew_buffer.sv
│   │   ├── controller.sv
│   │   └── systolic_top.sv
│   ├── sim/                                      ← Step-by-Step SystemVerilog Testbenches (.sv)
│   │   ├── tb_step1_pe.sv
│   │   ├── tb_step2_systolic_2x2.sv
│   │   ├── tb_step3_skew_buffer.sv
│   │   ├── tb_step4_systolic_4x4.sv
│   │   └── tb_step5_systolic_8x8.sv
│   ├── fpga_basys3/                               ← Digilent Basys 3 FPGA Hardware Target
│   │   ├── basys3_demo_top.sv                    ← Top wrapper with on-chip ROM & 7-seg multiplexer
│   │   ├── seven_segment_ctrl.sv                 ← 4-Digit 7-segment display controller
│   │   └── basys3_constraints.xdc                ← Physical pin constraints (Artix-7 XC7A35T)
│   ├── scripts/                                  ← Automation & Report Scripts
│   │   ├── run_sim_cli.bat                       ← 1-Click command-line test runner
│   │   ├── run_sim.tcl                           ← Vivado simulation automation script
│   │   ├── generate_assets.py
│   │   └── generate_pdf_report.py
│   ├── README_SIMULATION_GUIDE.md                ← Vivado-specific simulation guide
│   └── 2D_Systolic_Array_Vivado_Complete_Guide.pdf ← Full Vivado & FPGA manual
│
├── 📂 research/                                  ← Academic Papers & Theoretical Foundations
│   ├── README.md                                 ← Research paper summaries and notes
│   ├── 00502886-45a8-4c5e-8499-5a693a1fbfe4.pdf  ← MPX: Unified Matrix & Polynomial Array (Nokia Bell Labs)
│   ├── 978-3-030-05677-3_16.pdf                  ← Systolic Array Accelerator & Algorithm Mapping (Springer)
│   └── Laser Photonics Reviews - 2025 - Kim...pdf← Photonic Systolic Array (Laser & Photonics 2025/2026)
│
├── 📂 assets/                                    ← Hackathon Specifications & Guides
│   ├── 2D Systolic array.pdf
│   ├── 2D_Systolic_Array_Vivado_Complete_Guide.pdf
│   ├── EDGE-AI_2026_PROBLEM_STATEMET.docx
│   ├── EDGE-AI_ABSTRACT.docx
│   └── Edge_AI_Hackathon_Brochure.pdf
│
└── 📂 vivado/                                    ← Vivado Project Workspace
```

---

## ⚙️ Configuration & Parameterization

Both matrix dimension `N` and data width `DATA_WIDTH` are parameterized:

```verilog
// In systolic_top or your custom testbench:
systolic_top #(
    .N(8),              // 8×8 matrix multiplication (64 PEs)
    .DATA_WIDTH(8)      // 8-bit signed INT8 inputs
) dut (
    .clk(clk),
    .rst(rst),
    .start(start),
    .matrix_a(matrix_a),
    .matrix_b(matrix_b),
    .result(result),
    .done(done)
);
```

| Parameter | Default | Valid Range | Description |
|---|---|---|---|
| `N` | `4` | $2, 3, 4, 8, 16, \dots$ | Matrix dimension ($N \times N$) |
| `DATA_WIDTH` | `8` | $4, 8, 16, 32$ | Signed input element bit width |
| `ACCUMULATOR_WIDTH` | `2 × DATA_WIDTH` | Auto-sized (`16-bit` for 8-bit inputs) | Prevents arithmetic overflow during dot products |

---

## 🧪 Verified Test Cases

| Test Case | Module | Matrix Size | Test Description | Status |
|---|---|---|---|---|
| **PE Unit Test** | `1_pe.v` / `processing_element.sv` | $1 \times 1$ | Reset, MAC dot product $[1,2,3] \cdot [7,10,13] = 66$, and forwarding delay | ✅ Passed |
| **2×2 Spatial Wavefront** | `3_systolic_array.v` / `systolic_array.sv` | $2 \times 2$ | Staggered input wave propagation and spatial accumulation | ✅ Passed |
| **Skew Buffer Delay Line** | `5_skew_buffer.v` / `skew_buffer.sv` | $3 \times 3$ | Parallel matrix load to cycle-delayed diagonal output stream | ✅ Passed |
| **Identity Multiplication** | `7_systolic_top.v` / `systolic_top.sv` | $4 \times 4$ | $A \times I = A$ (Autonomous FSM + Skew Buffers) | ✅ Passed |
| **Scalar Scaling** | `7_systolic_top.v` / `systolic_top.sv` | $4 \times 4$ | $A \times 2I = 2A$ | ✅ Passed |
| **General Dense GEMM** | `7_systolic_top.v` / `systolic_top.sv` | $4 \times 4$ | Arbitrary signed integer matrix multiplication vs Software Golden Model | ✅ Passed |
| **Extended 8×8 Array** | `7_systolic_top.v` / `systolic_top.sv` | $8 \times 8$ | Full 64-PE array verification across 64 output matrix elements | ✅ Passed |

---

## 🔮 Future Work & Innovation Roadmap

As outlined in our Innovation Exploration Whitepaper, we are exploring several architectural extensions:

1. **Workload-Adaptive / Utilization-Aware Array:** Dynamically clock-gate inactive PE rows/columns for sub-$N\times N$ matrices to eliminate dark silicon power.
2. **Resource-Aware Quantized DSP Mapping:** Packing multiple INT4/INT8 operations into single FPGA DSP48E1 slices.
3. **Sparse Matrix Acceleration:** Zero-skipping logic in skew buffers to bypass zero-valued operands in pruned AI models.
4. **On-Chip Weight Stationary Mode:** Supporting both Output-Stationary and Weight-Stationary modes for transformer attention and CNN layers.

---

## 📚 References & Research Papers

### Academic Research Papers (in [`research/`](./research/))
1. **G. Alexakis, D. Schoinianakis, and G. Dimitrakopoulos**, *"MPX: A Unified Systolic Array for Matrix and Polynomial Multiplication"*, Democritus Univ. & Nokia Bell Labs. [[PDF](./research/00502886-45a8-4c5e-8499-5a693a1fbfe4.pdf)]
2. **Z. Yang, L. Wang, D. Ding, X. Zhang, Y. Deng, S. Li, and Q. Dou**, *"Systolic Array Based Accelerator and Algorithm Mapping for Deep Learning Algorithms"*, Springer CCF-THPC. [[PDF](./research/978-3-030-05677-3_16.pdf)]
3. **J. Kim, Q. Zhou, and Z. Yu**, *"Photonic Systolic Array for All-Optical Matrix–Matrix Multiplication"*, Laser & Photonics Reviews, 2025/2026. [[PDF](./research/Laser%20%20%20Photonics%20Reviews%20-%202025%20-%20Kim%20-%20Photonic%20Systolic%20Array%20for%20All%E2%80%90Optical%20Matrix%20Matrix%20Multiplication.pdf)]

> [!TIP]
> **Adding Future Research Papers:**  
> When new papers are collected for the project, simply save the PDF into the [`research/`](./research/) folder, add a short summary to [`research/README.md`](./research/README.md), and add a link in this section.

### Foundational Literature
* **H. T. Kung and C. E. Leiserson (1978)** — *"Systolic Arrays (for VLSI)"*, Sparse Matrix Proceedings. *(The seminal paper introducing systolic architectures)*.
* **N. P. Jouppi et al. (Google, 2017)** — *"In-Datacenter Performance Analysis of a Tensor Processing Unit (TPU)"*, ISCA. *(Commercial validation of 2D systolic arrays at scale)*.
* **Y. Chen, J. Emer, and V. Sze (MIT, 2016)** — *"Eyeriss: A Spatial Architecture for Energy-Efficient Dataflow for Convolutional Neural Networks"*, ISCA.

### Hardware Manual & Vivado Guide
* **2D Systolic Array Hardware Accelerator: Architecture, Vivado Simulation & Basys 3 FPGA Deployment Manual**: [[Complete PDF Guide](./assets/2D_Systolic_Array_Vivado_Complete_Guide.pdf)]

---

## 🤝 Team

| Member | Role |
|--------|------|
| **Adarsh** | Team Lead / RTL & Architecture |
| **Gulam** | Team Member |
| **Yamini** | Team Member |
| **Arpita** | Team Member |
| **Mihir** | Team Member |

---

## 📜 License

This project is developed for the **Edge AI Hackathon 2026**. Distributed under the MIT License.

---

<p align="center">
  <strong>Built with 💡 for Edge AI Hackathon 2026</strong><br/>
  <sub>Accelerating AI at the Edge — One Systolic Array at a Time</sub>
</p>
