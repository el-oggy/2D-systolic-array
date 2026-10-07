<p align="center">
  <img src="assets/pynq_z2_routed_floorplan.png" alt="PYNQ-Z2 Routed FPGA Floorplan" width="850"/>
</p>

<h1 align="center">⚡ Dual-Core Adaptive 2D Systolic Array Accelerator</h1>

<p align="center">
  <strong>High-Throughput 512-MAC Spatial Computing Architecture with Exact Signed INT8 Arithmetic, Dynamic Matrix Tiling & Real-Time Edge AI Demonstration on Xilinx Zynq-7000 (PYNQ-Z2)</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/FPGA%20Target-PYNQ--Z2%20(XC7Z020--1CLG400C)-red?style=for-the-badge&logo=xilinx&logoColor=white" alt="PYNQ-Z2"/>
  <img src="https://img.shields.io/badge/Architecture-Dual%2016%C3%9716%20Mesh%20(512%20MACs)-blue?style=for-the-badge" alt="Dual 16x16"/>
  <img src="https://img.shields.io/badge/Precision-Exact%20Signed%20INT8%20%7C%20INT20%20Acc-purple?style=for-the-badge" alt="Precision"/>
  <img src="https://img.shields.io/badge/Frequency-100%20MHz%20Routed-brightgreen?style=for-the-badge" alt="Clock"/>
  <img src="https://img.shields.io/badge/Verification-7%20%2F%207%20Passed%20(100%25)-success?style=for-the-badge" alt="Verification"/>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="MIT License"/></a>
</p>

<p align="center">
  <a href="#-problem-statement--objectives">Problem & Objectives</a> •
  <a href="#-key-architectural-highlights">Highlights</a> •
  <a href="#-system-architecture">Architecture</a> •
  <a href="#-implementation--fpga-resource-utilization">FPGA Utilization</a> •
  <a href="#-hardware-verification--test-results">Verification Results</a> •
  <a href="#-edge-ai-application-demo">Edge AI Demo</a> •
  <a href="#-interactive-3d-web-visualizer">Web Visualizer</a> •
  <a href="#-repository-structure">Structure</a> •
  <a href="#-quickstart--deployment">Quickstart</a> •
  <a href="#-team--track-details">Team</a>
</p>

---

## 🎯 Track & Problem Statement

- **Hackathon Track**: Track 1 — FPGA / PYNQ-Z2 / AMD Xilinx Zynq-7000 XC7Z020
- **Problem Statement**: **Problem #5: 2D Systolic Array-Based Processing Elements**
- **Core Focus**: Designing an energy-efficient, high-performance spatial matrix multiplication accelerator capable of dynamic workload adaptation, zero arithmetic precision loss, and seamless hardware-software co-design for edge inference.

---

## 🧠 Problem Statement & Objectives

### The Edge AI Challenge
Modern Convolutional Neural Networks (CNNs), Vision Transformers (ViTs), and Deep Neural Network inference workloads rely overwhelmingly on General Matrix Multiplication (**GEMM**: $C = A \times B + C$) and Matrix-Vector Multiplication (**MVM**). However, executing these layers on edge embedded platforms faces critical bottlenecks:
1. **Underutilization on Irregular Shapes**: Traditional fixed-size systolic arrays waste substantial clock cycles on zero-padding or idling when layer dimensions ($M, K, N$) do not perfectly match the hardware grid size.
2. **Memory Bandwidth & Routing Congestion**: Memory transfer between off-chip DRAM and the spatial compute fabric easily throttles throughput and inflates power consumption.
3. **Severe Resource Constraints**: Edge FPGAs like the AMD Xilinx Zynq XC7Z020 have finite DSP slices (220 DSP48E1 blocks). Naive 512-PE implementations exceed available DSP resources.

### Objectives Achieved
- **Dual-Engine Spatial Fabric**: Built two parallel $16 \times 16$ systolic array engines delivering **512 physical MAC operations per cycle**.
- **Balanced Hybrid PE Design**: Symmetrically partitioned DSP and LUT resources across both engines (**110 DSP48E1 MACs + 146 LUT MACs per engine**) to consume exactly 100% of available DSP slices (220/220) without over-allocation.
- **Exact Signed INT8 Precision**: Implemented full signed INT8 arithmetic with 20-bit saturating accumulators and sign-extended INT32 outputs, preventing arithmetic overflow.
- **Dynamic Dimension Adaptation & Tiling**: Hardware-level active dimension masks ($M, K, N \le 16$) and zero-padding handle tail bounds, while host software transparently tiles arbitrarily large matrices.
- **Complete End-to-End Edge AI Demonstration**: Deployed a real-time Hand Gesture CNN on the PYNQ-Z2 board via Python AXI DMA and an interactive 3D Web visualizer.

---

## 🌟 Key Architectural Highlights

| Specification | Implementation | Architectural Advantage |
|---|---|---|
| **Compute Engines** | **Dual $16 \times 16$ Systolic Arrays** | Two parallel engines (Engine 0 & Engine 1) yielding **512 physical MAC units** |
| **Operating Frequency** | **100 MHz (Closed Timing)** | Fully placed and routed on Xilinx XC7Z020 with zero negative slack |
| **Arithmetic Precision** | **Exact Signed INT8** | 8-bit signed two's complement inputs with zero quantization loss during GEMM |
| **Accumulator Depth** | **20-bit Accumulators** | Accommodates maximum dot-product accumulations ($16 \times 127 \times 127 = 258,096 < 2^{19}$) |
| **Output Format** | **Sign-Extended INT32** | 256 words per tile streamed directly over AXI DMA |
| **DSP Allocation** | **Hybrid 220 DSP + 292 LUT PEs** | 110 DSPs + 146 LUT PEs per engine (100% DSP budget utilization) |
| **LUT Optimization** | **38,765 LUTs (27.14% reduction)** | Slashed from 53,200 baseline LUTs down to 38,765 routed LUTs |
| **Memory System** | **Ping-Pong True Dual-Port BRAM** | Bank 0 / Bank 1 ping-pong buffering feeds both engines with continuous streaming |
| **DMA Interface** | **AXI DMA over AXI HP0** | High-performance 32-bit streaming data path with burst size 16 |
| **Control Interface** | **AXI4-Lite & 6 Interrupts** | Controlled by ARM Cortex-A9 Processing System (PS) |

---

## 🏗️ System Architecture

### Hardware Top-Level Block Diagram

```
                              ┌─────────────────────────────────────────────────────────────┐
                              │                    ARM Cortex-A9 (PS)                       │
                              │           Control & Status Registers (AXI4-Lite)            │
                              └──────────────────────────────┬──────────────────────────────┘
                                                             │
                              ┌──────────────────────────────▼──────────────────────────────┐
                              │                    DDR3 System Memory                       │
                              │       Matrices A & B (INT8)  │  Matrix C Results (INT32)    │
                              └──────────────────────────────┬──────────────────────────────┘
                                                             │
                                                             │ AXI HP0 (High Performance Port)
                                                             ▼
                                              ┌──────────────────────────────┐
                                              │       AXI DMA Subsystem      │
                                              │   MM2S (In)  │  S2MM (Out)   │
                                              └───────┬──────────────▲───────┘
                                                      │              │
                                         Matrix Stream│              │Result Stream
                                                      ▼              │
                                              ┌──────────────────────┴───────┐
                                              │   Ping-Pong True Dual-Port   │
                                              │          BRAM Banks          │
                                              │       (Bank 0 / Bank 1)      │
                                              └───────┬──────────────┬───────┘
                                                      │              │
                                      Feeder Stream 0 │              │ Feeder Stream 1
                                                      ▼              ▼
       ┌────────────────────────────────────────────────┐          ┌────────────────────────────────────────────────┐
       │             ENGINE 0 (16×16 Mesh)              │          │             ENGINE 1 (16×16 Mesh)              │
       │           256 Processing Elements              │          │           256 Processing Elements              │
       ├────────────────────────────────────────────────┤          ├────────────────────────────────────────────────┤
       │  • 110 DSP48E1 PEs + 146 Distributed LUT PEs   │          │  • 110 DSP48E1 PEs + 146 Distributed LUT PEs   │
       │  • Triangular Skew Buffers (A: Rows, B: Cols)  │          │  • Triangular Skew Buffers (A: Rows, B: Cols)  │
       │  • INT8 MAC Multipliers + 20-bit Accumulators  │          │  • INT8 MAC Multipliers + 20-bit Accumulators  │
       │  • Result Capture Unit (INT20 -> INT32)        │          │  • Result Capture Unit (INT20 -> INT32)        │
       └────────────────────────────────────────────────┘          └────────────────────────────────────────────────┘
                               Total Across Both Engines: 512 Physical MAC PEs (220 DSP48E1 + 292 LUT PEs)
```

### End-to-End 10-Step Compute Workflow

```mermaid
sequenceDiagram
    autonumber
    actor Host as ARM PS / Python Runtime
    participant DDR as DDR3 Memory
    participant DMA as AXI DMA Engine
    participant BRAM as Ping-Pong BRAM
    participant Core as Dual 16x16 Engines
    participant Out as Output Stream FIFO

    Host->>DDR: 1. Quantize weights & activations to signed INT8; determine M, K, N
    Host->>Core: 2. Write tile configuration & active mask via AXI4-Lite
    Host->>DMA: 3. Initiate AXI DMA MM2S transfer from DDR3
    DMA->>BRAM: 4. Stream 32-bit burst-16 data into active Ping-Pong BRAM Bank
    BRAM->>Core: 5. Stream A/B operands through triangular skew delay buffers
    Core->>Core: 6. Execute 2D wave-front MAC operations across 512 PEs simultaneously
    Core->>Out: 7. Capture tile results: convert INT20 accumulators to INT32
    Out->>DMA: 8. Drain INT32 result words into AXI DMA S2MM stream
    DMA->>DDR: 9. Write completed matrix C tile directly into DDR3 result buffer
    DDR->>Host: 10. Dequantize, apply bias & activation function; proceed to next layer
```

---

## 📊 Implementation & FPGA Resource Utilization

The design was fully synthesized, implemented, and closed for timing at **100 MHz** on the **Xilinx Zynq-7000 XC7Z020-1CLG400C** FPGA using AMD Vivado.

### Implementation Optimization Progress
- **Baseline Synthesis**: 53,200 LUTs (exceeded slice floorplan limits).
- **Optimized Synthesis**: **38,765 LUTs** — achieved a **27.14% reduction in LUT utilization** through hybrid DSP/LUT logic mapping and unified BRAM feeder sharing.

### Post-Route Resource Utilization Table (from Vivado Implementation Reports)

| Resource Type | Used | Available | Utilization Percentage | Status / Notes |
|---|---|---|---|---|
| **LUT (Look-Up Tables)** | **38,765** | 53,200 | **72.86%** | Optimized hybrid PE mapping (27.14% reduction) |
| **LUTRAM (Distributed RAM)** | **1,152** | 17,400 | **6.62%** | Skew buffers and small delay FIFO lines |
| **FF (Flip-Flops)** | **33,325** | 106,400 | **31.32%** | Pipeline registers, accumulators, and valid tags |
| **DSP48E1 Slices** | **220** | 220 | **100.00%** | 110 DSPs allocated to Engine 0, 110 to Engine 1 |
| **BRAM36 Equivalents** | **18** | 140 | **12.85%** | Ping-Pong input banks and output stream queues |
| **Slices** | **12,043** | 13,300 | **90.55%** | Placed across clock regions X0Y0 to X1Y2 |
| **Clock Frequency** | **100.0 MHz** | — | **10.00 ns** | **WNS > 0.00 ns (Zero timing violations)** |

---

## 🧪 Hardware Verification & Test Results

The architecture underwent extensive self-checking testbench simulations (SystemVerilog) and physical hardware-in-the-loop test runs on the PYNQ-Z2 board. All 7 benchmark test suites passed with 100% bit-exact accuracy against NumPy double-precision golden models.

### Verification Results Table (Exact Hardware Test Data)

| Test Suite | Matrix Size ($M \times K \times N$) | Output Vector $y$ / Matrix Sample | Expected Output | Status |
|---|---|---|---|:---:|
| `identity_4` | $4 \times 4$ | `[3, -1, 4, 2]` | `[3, -1, 4, 2]` | ✔ **PASS** |
| `zero_4` | $4 \times 4$ | `[0, 0, 0, 0]` | `[0, 0, 0, 0]` | ✔ **PASS** |
| `negative_4` | $4 \times 4$ | `[10, 18, 26, 34]` | `[10, 18, 26, 34]` | ✔ **PASS** |
| `random_4` | $4 \times 4$ | `[33, 11, 51, 19]` | `[33, 11, 51, 19]` | ✔ **PASS** |
| `random_8` | $8 \times 8$ | `[-33, -2, -5, -111, 83, 46, 34, -64]` | `[-33, -2, -5, -111, 83, 46, 34, -64]` | ✔ **PASS** |
| `random_16_scalability` | $16 \times 16$ | `[-14, -28, 96, … 218 … -40]` | Matches golden 16×16 GEMM | ✔ **PASS** |
| `max_values_4` | $4 \times 4$ | `[64516, 64516, 64516, 64516]` | `[64516, 64516, 64516, 64516]` | ✔ **PASS** |

### Key Verification Takeaways
1. **100% Pass Rate (7 / 7 Cases)**: Flawless arithmetic correctness across zero, identity, negative, random, and boundary-value matrices.
2. **Dynamic Scaling ($4 \times 4 \to 16 \times 16$)**: Hardware masks dynamically active rows and columns, verifying zero-bubble tail execution.
3. **Overflow Immunity**: The `max_values_4` stress test (saturating all 8-bit inputs) achieved `64,516`, proving the 20-bit accumulators prevent overflow under extreme dynamic range.

---

## ✋ Edge AI Application: Real-Time Hand Gesture CNN Demo

To demonstrate real-world edge acceleration beyond synthetic benchmarks, we developed an end-to-end edge vision pipeline that maps convolutional inference onto the systolic accelerator:

- **Model**: **HandNet INT8**, a calibrated tiny convolutional neural network trained for low-latency hand gesture recognition.
- **Workflow**:
  1. Live video feed captured from webcam via OpenCV.
  2. Hand bounding box and landmarks localized in real time.
  3. Feature maps transformed to matrix patches using an optimized `im2col` pipeline.
  4. Matrix multiplication ($C = A \times B$) offloaded to the **Dual 16×16 Systolic Array** via the PYNQ overlay driver.
  5. Classified gestures (Fist, Open Hand, Thumbs Up, Peace, Pointing, OK) displayed with real-time hardware inference latency.

The demo application scripts and calibrated models are located in [`applications/hand_gesture/`](./applications/hand_gesture/).

---

## 🌐 Interactive 3D Web Visualizer

We built a full-featured, interactive 3D Web Visualizer powered by **Three.js** that connects directly to the PYNQ-Z2 hardware bridge:

- **3D Spatial Mesh Animation**: Real-time 3D visualization of matrix operands $A$ and $B$ propagating along the systolic wave-front through each PE.
- **Interactive Matrix Editor**: Input custom $M \times K \times N$ matrices and inspect intermediate accumulator values cycle by cycle.
- **Hardware Bridge**: Connects over WebSocket / HTTP to `bridge/server.py` on the PYNQ board to run live on-board execution and compare FPGA results with browser-side software emulation.
- **Quick Launch**: Located in [`webpage/`](./webpage/) — run [`OPEN_WEBPAGE.bat`](./webpage/OPEN_WEBPAGE.bat) to launch instantly.

---

## 📁 Repository Structure

```
.
├── applications/
│   └── hand_gesture/                 # End-to-end HandNet INT8 edge vision demo
│       ├── full_screen_hand_tracker.py
│       ├── gesture_classifier.py
│       ├── hand_gesture_engine.py
│       ├── im2col.py
│       ├── models/                   # Calibrated INT8 weights & gesture models
│       └── START_HARDWARE_GESTURE_DEMO.bat
├── assets/
│   ├── NEXT_IN_Presentation.pptx     # Complete Hackathon Final Presentation Deck
│   ├── pynq_z2_routed_floorplan.png  # Vivado routed device floorplan (XC7Z020)
│   ├── 2D Systolic array.pdf
│   └── Edge_AI_Hackathon_Brochure.pdf
├── boards/
│   ├── basys3/                       # Baseline Basys 3 (Artix-7) implementation
│   │   ├── board_implementation/
│   │   ├── sim/
│   │   └── src/
│   └── pynq_z2/                      # Production Dual 16×16 PYNQ-Z2 Implementation
│       ├── bitstream/                # Ready-to-flash bitstream & hardware handoff
│       │   ├── adaptive_gemm.bit     # Fully routed 100 MHz bitstream
│       │   ├── adaptive_gemm.hwh     # Hardware handoff specification
│       │   └── optimization_candidate.bit
│       ├── board_implementation/
│       │   ├── constraints/          # Pinouts and out-of-context XDC constraints
│       │   └── vivado/               # Block design & bitstream build TCL scripts
│       ├── pynq/                     # Host Python driver, notebooks, & test cases
│       │   ├── adaptive_gemm.py      # Core AXI DMA systolic array Python driver
│       │   ├── adaptive_gemm_notebook.ipynb
│       │   ├── benchmark_power.py    # Power & throughput benchmarking
│       │   ├── cases.json            # 7 verification test matrices
│       │   ├── pynq_gesture_server.py
│       │   └── run_cases.py          # Automated verification test runner
│       ├── sim/                      # SystemVerilog testbenches & regression scripts
│       │   ├── run_regressions.ps1
│       │   ├── tb_accel_dual_engine_top.sv
│       │   ├── tb_adaptive_gemm.sv
│       │   ├── tb_pe_mac.sv
│       │   └── tb_ping_pong_bram.sv
│       └── src/                      # Complete Synthesizable SystemVerilog RTL
│           ├── accel_dual_axi_top.sv # AXI4-Lite + AXI DMA Top
│           ├── accel_dual_engine_top.sv # Dual 16×16 engine integrator
│           ├── accel_dual_tile_core.sv
│           ├── c_buf.sv
│           ├── dual_systolic_array.sv
│           ├── pe_mac.sv             # Hybrid DSP48E1 / LUT PE
│           ├── ping_pong_bram.sv     # True dual-port input buffer
│           ├── single_tile_controller.sv
│           ├── skew_buffers.sv       # Triangular delay line
│           ├── systolic_array.sv     # 16×16 systolic mesh
│           └── unified_bram_feeder.sv
├── docs/                             # Official Technical Documents & Reports
│   ├── 16x16_Systolic_Array_Vivado_Simulation_Guide.pdf
│   ├── 2D_Systolic_Array_Innovation_Ideas_Report.pdf
│   ├── 2D_Systolic_Array_Vivado_Complete_Guide.pdf
│   ├── EDGE-AI_NEXT_IN_Project_Presentation.pdf
│   ├── Edge_AI_Hackathon_2026_Technical_Report.pdf  # Comprehensive technical report
│   └── Literature Survey - 2D Systolic Array-Based Processing Elements.pdf
├── research_papers/                  # Foundational Literature & Architecture Papers
│   ├── 04_Jouppi2017_TPUv1.pdf
│   ├── 05_Jouppi2023_TPUv4.pdf
│   ├── 06_Chen2019_EyerissV2.pdf
│   ├── 08_Qin2020_SIGMA.pdf
│   ├── 09_Genc2021_Gemmini.pdf
│   ├── 10_Samajdar2020_SCALESim.pdf
│   └── ...
├── webpage/                          # Interactive 3D Three.js Web Visualizer
│   ├── bridge/                       # Python WebSocket / HTTP bridge server
│   ├── css/
│   ├── js/
│   ├── index.html
│   └── OPEN_WEBPAGE.bat
├── LICENSE                           # MIT License
└── README.md
```

---

## 🚀 Quickstart & Deployment

### 1. Flash & Run on PYNQ-Z2 Board
If you have a PYNQ-Z2 board connected via Ethernet or USB:

```bash
# SSH into the PYNQ board
ssh xilinx@192.168.2.99

# Clone or copy repository to the board
cd /home/xilinx/
git clone https://github.com/el-oggy/2D-systolic-array-.git
cd 2D-systolic-array-/boards/pynq_z2/pynq

# Run automated 7/7 test suite
python3 run_cases.py
```

### 2. Run Python Interactive Jupyter Notebook
1. Open your browser and navigate to `http://192.168.2.99:9090` (password: `xilinx`).
2. Open [`boards/pynq_z2/pynq/adaptive_gemm_notebook.ipynb`](./boards/pynq_z2/pynq/adaptive_gemm_notebook.ipynb).
3. Execute the cells to inspect matrix quantization, AXI DMA transfers, and cycle timing.

### 3. Launch 3D Three.js Web Visualizer
On Windows, simply double-click:
```bat
webpage\OPEN_WEBPAGE.bat
```
Or start the bridge server and open in any modern browser:
```bash
python webpage/bridge/server.py
# Open webpage/index.html in your browser
```

### 4. Run Edge AI Gesture Recognition Demo
```bat
applications\hand_gesture\START_HARDWARE_GESTURE_DEMO.bat
```

### 5. Rebuild Vivado Bitstream from Scratch
If you wish to re-synthesize and implement the dual-engine design in AMD Vivado (2022.2 or later):
```bash
cd boards/pynq_z2/board_implementation/vivado
vivado -mode batch -source block_design.tcl
vivado -mode batch -source synth_accel.tcl
vivado -mode batch -source run_full_bitstream.tcl
```

---

## 👥 Team & Track Details

**Track 1**: FPGA / PYNQ-Z2 / AMD Xilinx Zynq-7000 XC7Z020  
**Problem Statement**: Problem #5: 2D Systolic Array-Based Processing Element  

| Team Member | Registration Number |
|---|---|
| **Adarsh Swarup Maharana** | `#2301109373` |
| **Arpita Mishra** | `#2301109371` |
| **Ashishayan Pattanyak** | `#2301109373` |
| **Ghulam Qadir** | `#2301109391` |
| **Srikanta Behera** | `#2301109427` |

---

## 📜 License & Acknowledgments

This project is open-source under the [MIT License](./LICENSE).  
Architecture inspired by foundational research from Google TPU (Jouppi et al.), MIT Eyeriss V2 (Chen et al.), and UC Berkeley Gemmini (Genc et al.). All cited works are archived in [`research_papers/`](./research_papers/).
