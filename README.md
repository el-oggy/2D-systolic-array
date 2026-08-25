<p align="center">
  <img src="2D-systolic-array/block_diagram.png" alt="2D Systolic Array Architecture" width="700"/>
</p>

<h1 align="center">⚡ 2D Systolic Array — Edge AI Accelerator</h1>

<p align="center">
  <strong>High-performance N×N matrix multiplication engine in Verilog for Edge AI inference</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/HDL-Verilog-blue?style=for-the-badge&logo=v&logoColor=white" alt="Verilog"/>
  <img src="https://img.shields.io/badge/Simulator-Icarus%20Verilog-orange?style=for-the-badge" alt="Icarus Verilog"/>
  <img src="https://img.shields.io/badge/Hackathon-Edge%20AI%202026-green?style=for-the-badge&logo=hackthebox&logoColor=white" alt="Edge AI 2026"/>
  <img src="https://img.shields.io/badge/Matrix-N×N%20Configurable-purple?style=for-the-badge" alt="NxN"/>
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="MIT"/>
</p>

<p align="center">
  <a href="#-architecture">Architecture</a> •
  <a href="#-quick-start-for-team-members">Quick Start</a> •
  <a href="#-branching-strategy">Branching</a> •
  <a href="#-project-structure">Structure</a> •
  <a href="#-how-to-simulate">Simulate</a> •
  <a href="#-team">Team</a>
</p>

---

## 🧠 What Is This?

A **2D Systolic Array** hardware accelerator designed for **matrix multiplication** — the core operation behind neural network inference on edge devices. Built from scratch in Verilog for the **Edge AI Hackathon 2026**.

> **Why Systolic Arrays?**  
> Google's TPU uses systolic arrays to achieve massive parallelism for AI workloads.  
> Our design brings this concept to **edge devices** — low power, high throughput, fully pipelined.

### Key Features

| Feature | Description |
|---------|-------------|
| 🔧 **Parameterized N×N** | Configure any matrix size (tested with 2×2 and 4×4) |
| ⚡ **Fully Pipelined** | Computes C = A × B in just `3N - 1` clock cycles |
| 🧱 **Modular Design** | PE → Array → Skew Buffers → Controller → Top |
| 📐 **8-bit Signed** | Configurable `DATA_WIDTH`, default 8-bit for INT8 inference |
| ✅ **Verified** | Testbenches for PE, 2×2 array, and full 4×4 system |

### 🌍 Applications

This architecture is highly versatile and accelerates matrix operations in several domains:
*   **Deep Learning Inference:** Real-time, on-device AI inference without cloud dependency.
*   **Digital Signal Processing (DSP):** FIR filtering, FFT, and radar systems.
*   **Scientific Computing:** Matrix solvers and simulations on embedded platforms.
*   **Image & Video Processing:** 2D spatial convolutions for real-time video processing.
*   **5G/6G & Massive MIMO:** Accelerating beamforming and signal detection algorithms.

### 💎 Value Proposition

*   **Optimal Data Reuse:** Each input is read ONCE from memory and reused N times through the PE chain, resulting in an N× bandwidth reduction.
*   **Architectural Novelty:** Utilizes a unique B-matrix transposition technique prior to skewing, allowing complete reuse of a single shift-register buffer module for both horizontal and vertical data streams.
*   **Zero Wasted Cycles:** The precise 3N-1 cycle state machine guarantees maximum PE utilization.

---

## 🏗️ Architecture

<p align="center">
  <img src="2D-systolic-array/flowchart.png" alt="FSM Flowchart" width="500"/>
</p>

The system consists of **4 core modules** orchestrated by an FSM controller:

```
                    ┌─────────────────────────────────────────────┐
                    │              systolic_top                    │
                    │                                             │
  Matrix A ──────► │  ┌────────────┐    ┌──────────────────┐     │
                    │  │ Skew Buf A │──►│                  │     │
                    │  └────────────┘   │   N×N Systolic   │     │──► Result C = A×B
                    │  ┌────────────┐   │      Array       │     │
  Matrix B ──────► │  │ Skew Buf B │──►│   (PE Grid)      │     │
                    │  └────────────┘   └──────────────────┘     │
                    │       ▲                    ▲                │
  Start ─────────► │  ┌────┴────────────────────┴───┐            │
                    │  │     Controller FSM          │──► Done   │
                    │  │  IDLE → LOAD → COMPUTE → DONE │         │
                    │  └────────────────────────────────┘         │
                    └─────────────────────────────────────────────┘
```

### Module Hierarchy

| # | Module | File | Purpose |
|---|--------|------|---------|
| 1 | `PE` | `1_pe.v` | Processing Element: `acc += a_in × b_in`, passes data to neighbors |
| 2 | `systolic_array` | `3_systolic_array.v` | Instantiates N×N grid of PEs with auto-wiring |
| 3 | `skew_buffer` | `5_skew_buffer.v` | Staggers matrix inputs for correct timing alignment |
| 4 | `controller` | `6_controller.v` | FSM that sequences LOAD → COMPUTE → DONE phases |
| 5 | `systolic_top` | `7_systolic_top.v` | Top-level wrapper connecting all modules |

---

## 🚀 Quick Start for Team Members

> [!CAUTION]
> **MANDATORY WORKFLOW:** The `main` branch is protected. You **cannot** push code directly to `main`. GitHub will block your push. You must *always* create a new branch, push your branch, and open a **Pull Request (PR)** for review.

### Prerequisites

Make sure you have these installed:

| Tool | Install Command | Purpose |
|------|----------------|---------|
| **Git** | [Download Git](https://git-scm.com/downloads) | Version control |
| **Icarus Verilog** | `sudo apt install iverilog` / [Windows](http://bleyer.org/icarus/) | Verilog simulation |
| **GTKWave** *(optional)* | `sudo apt install gtkwave` / [Windows](http://gtkwave.sourceforge.net/) | Waveform viewer |
| **AMD Xilinx Vivado** *(optional)* | [Download](https://www.xilinx.com/support/download.html) <br> [📺 Installation Guide](https://youtu.be/BbryIz49Fyo?si=Z2W_im2wUE-0qvAd) | FPGA synthesis and implementation |

### Step 1 — Clone the Repository

```bash
# Clone via HTTPS (easiest)
git clone https://github.com/el-oggy/2D-systolic-array-.git

# OR clone via SSH (if you have SSH keys set up)
git clone git@github.com:el-oggy/2D-systolic-array-.git

# Enter the project
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

Because `main` is protected, you cannot merge your own code directly. You must ask for a review.

1. Go to the repo on GitHub.
2. Click **"Compare & pull request"** (a green banner appears after you push).
3. Write a description of what you changed and *why*.
4. **Important:** Request a review from the repository admin (Adarsh).
5. **Wait for Approval:** You must wait for the admin to review your code, approve it, and click merge. Once merged, your changes will appear in `main`.

---

## 🐣 Beginner's Guide to Contributing (No Coding Required!)

If you don't have Git installed or aren't comfortable with the command line, you can still contribute directly through the GitHub website!

### Editing a File (e.g., adding your name to the README)
1. Navigate to the repository on GitHub.
2. Click on the file you want to edit (e.g., `README.md`).
3. Click the **pencil icon** (✏️) in the top right corner of the file view.
4. Make your changes in the web editor.
5. Scroll down to **"Commit changes..."**.
6. Write a short description (e.g., "Add my name to team list").
7. Select **"Create a new branch for this commit and start a pull request"**.
8. Click **"Propose changes"**.
9. On the next screen, click **"Create pull request"**.
10. **Wait for Approval:** An administrator must review and approve your Pull Request before your changes are merged into the main project.

### Uploading a File (e.g., adding a new document or image)
1. Navigate to the folder where you want to add the file.
2. Click the **"Add file"** button near the top right, then select **"Upload files"**.
3. Drag and drop your file into the box.
4. Scroll down to **"Commit changes..."**.
5. Write a short description (e.g., "Upload final presentation PDF").
6. Select **"Create a new branch for this commit and start a pull request"**.
7. Click **"Propose changes"**.
8. On the next screen, click **"Create pull request"**.
9. **Wait for Approval:** Just like editing a file, an administrator must approve your upload before it appears in the main project.

---

## 🌿 Branching Strategy

We follow a **feature-branch workflow** to keep things clean:

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

### Branch Naming Convention

| Prefix | Use When | Example |
|--------|----------|---------|
| `feature/` | Adding new functionality | `feature/rahul/add-8x8-testbench` |
| `fix/` | Fixing a bug | `fix/priya/pe-overflow-fix` |
| `docs/` | Documentation only | `docs/adarsh/update-readme` |
| `experiment/` | Trying something new (may not merge) | `experiment/rahul/fp16-pe` |
| `refactor/` | Restructuring code without changing behavior | `refactor/priya/clean-controller` |

### Rules

> [!IMPORTANT]
> - **Never push directly to `main`** — GitHub will actively block it. You must use a branch and a Pull Request.
> - **Always pull before you push** — `git checkout main` then `git pull origin main` before starting new work.
> - **One feature per branch** — keep branches small and focused.
> - **Write descriptive commit messages** — your teammates need to know what you changed.

### Useful Git Commands

```bash
# See all branches (local + remote)
git branch -a

# Switch to an existing branch
git checkout develop

# Update your branch with latest develop
git checkout feature/your-branch
git merge develop

# Delete a branch after merging
git branch -d feature/your-old-branch

# See commit history (pretty)
git log --oneline --graph --all

# Stash your work temporarily
git stash
git stash pop    # get it back
```

---

## 📁 Project Structure

```
2D-systolic-array-/
│
├── 📄 README.md                          ← You are here
├── 📄 .gitignore                         ← Git ignore rules
│
├── 📂 2D-systolic-array/                 ← Core RTL Design
│   ├── 1_pe.v                            ← Processing Element
│   ├── 2_pe_tb.v                         ← PE Testbench
│   ├── 3_systolic_array.v                ← N×N Systolic Array
│   ├── 4_systolic_2x2_tb.v              ← 2×2 Array Testbench
│   ├── 5_skew_buffer.v                   ← Input Skew Buffer
│   ├── 6_controller.v                    ← FSM Controller
│   ├── 7_systolic_top.v                  ← Top-Level Wrapper
│   ├── 8_systolic_4x4_tb.v              ← Full 4×4 System Testbench
│   ├── EDGE-AI_ABSTRACT_FILLED.docx      ← Project Abstract
│   ├── Systolic_Array_Code_Explanation.pdf ← Code Explanation
│   ├── block_diagram.png                 ← System Architecture Diagram
│   └── flowchart.png                     ← FSM Flowchart
│
├── 📂 assets/                            ← Hackathon Documents
│   ├── 2D Systolic array.pdf             ← Systolic Array Docs
│   ├── EDGE-AI_2026_PROBLEM_STATEMET.docx
│   ├── EDGE-AI_ABSTRACT.docx
│   └── Edge_AI_Hackathon_Brochure.pdf
│
└── 📄 2D_Systolic_Array_Innovation_Ideas_Report.pdf
```

---

## 🔬 How to Simulate

### Run the PE Testbench

```bash
cd 2D-systolic-array

# Compile
iverilog -o pe_tb.vvp 1_pe.v 2_pe_tb.v

# Simulate
vvp pe_tb.vvp

# View waveforms (optional)
gtkwave pe_tb.vcd
```

### Run the 2×2 Array Testbench

```bash
iverilog -o systolic_2x2.vvp 1_pe.v 3_systolic_array.v 4_systolic_2x2_tb.v
vvp systolic_2x2.vvp
gtkwave systolic_2x2_tb.vcd
```

### Run the Full 4×4 System Testbench

```bash
iverilog -o systolic_4x4.vvp 1_pe.v 3_systolic_array.v 5_skew_buffer.v 6_controller.v 7_systolic_top.v 8_systolic_4x4_tb.v
vvp systolic_4x4.vvp
gtkwave systolic_4x4_tb.vcd
```

---

## ⚙️ Configuration

Both `DATA_WIDTH` and `N` are parameterized. To change matrix size or precision:

```verilog
// In systolic_top.v or your testbench:
systolic_top #(
    .N(8),              // 8×8 matrix multiplication
    .DATA_WIDTH(16)     // 16-bit signed inputs
) dut ( ... );
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N` | 4 | Matrix dimension (N×N) |
| `DATA_WIDTH` | 8 | Bit width of each element (signed) |
| Accumulator | `2 × DATA_WIDTH` | Auto-sized to prevent overflow |

---

## 🧪 Verified Test Cases

| Test | Matrix Size | Status |
|------|-------------|--------|
| PE unit test | 1×1 | ✅ Passed |
| Identity multiplication | 2×2 | ✅ Passed |
| Known-answer test | 4×4 | ✅ Passed |
| Negative numbers | 4×4 | ✅ Passed |

---

## 🔮 Future Work & Innovation Roadmap

As outlined in our Innovation Exploration Report, we are exploring several architectural improvements over the conventional fixed array:

1.  **Workload-Adaptive / Utilization-Aware Array:** Adapting the active computation region to actual workload dimensions to save power and improve true utilization.
2.  **Resource-Aware Optimization:** Reducing LUT/DSP overhead while maintaining computational performance.
3.  **Power-Aware Systolic Array:** Implementing clock gating and operand isolation to reduce unnecessary switching in inactive PEs.

---

## 🤝 Team

| Member | Role | Branch |
|--------|------|--------|
| **Adarsh** | Lead / Architecture | `main` |
| *Member 2* | *Role* | `feature/name/...` |
| *Member 3* | *Role* | `feature/name/...` |
| *Member 4* | *Role* | `feature/name/...` |
| *Member 5* | *Role* | `feature/name/...` |

> 📝 **Team members**: Update this table with your name and role after cloning!

---

## 📜 License

This project is built for the **Edge AI Hackathon 2026**. See the hackathon rules for usage terms.

---

## 📚 References & Research

### Foundational Literature
1. **H. T. Kung and C. E. Leiserson**, "Systolic Arrays (for VLSI)," *Sparse Matrix Proceedings*, 1978.
2. **N. P. Jouppi et al.**, "In-Datacenter Performance Analysis of a Tensor Processing Unit," *ISCA*, 2017.
3. **Y. Chen, J. Emer, and V. Sze**, "Eyeriss: A Spatial Architecture for Energy-Efficient Dataflow for Convolutional Neural Networks," *ISCA*, 2016.

### Academic Research Papers (in [`research/`](./research/))
4. **G. Alexakis, D. Schoinianakis, and G. Dimitrakopoulos**, "MPX: A Unified Systolic Array for Matrix and Polynomial Multiplication," *Democritus Univ. & Nokia Bell Labs*. [[PDF](./research/00502886-45a8-4c5e-8499-5a693a1fbfe4.pdf)]
5. **Z. Yang, L. Wang, D. Ding, X. Zhang, Y. Deng, S. Li, and Q. Dou**, "Systolic Array Based Accelerator and Algorithm Mapping for Deep Learning Algorithms," *Springer CCF-THPC*. [[PDF](./research/978-3-030-05677-3_16.pdf)]
6. **J. Kim, Q. Zhou, and Z. Yu**, "Photonic Systolic Array for All-Optical Matrix–Matrix Multiplication," *Laser & Photonics Reviews*, 2025/2026. [[PDF](./research/Laser%20%20%20Photonics%20Reviews%20-%202025%20-%20Kim%20-%20Photonic%20Systolic%20Array%20for%20All%E2%80%90Optical%20Matrix%20Matrix%20Multiplication.pdf)]

### Hardware & Simulation Guide
- **2D Systolic Array Hardware Accelerator: Architecture, Vivado Simulation & Basys 3 FPGA Deployment Manual**: [[Complete PDF Guide](./assets/2D_Systolic_Array_Vivado_Complete_Guide.pdf)]

---

<p align="center">
  <strong>Built with 💡 for Edge AI Hackathon 2026</strong><br/>
  <sub>Accelerating AI at the Edge — One Systolic Array at a Time</sub>
</p>
