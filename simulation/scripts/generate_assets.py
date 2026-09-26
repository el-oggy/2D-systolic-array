import os
import matplotlib.pyplot as plt
import numpy as np
import matplotlib.patches as patches

# Resolve paths dynamically
script_dir = os.path.dirname(os.path.abspath(__file__))
assets_dir = os.path.abspath(os.path.join(script_dir, "..", "assets"))
os.makedirs(assets_dir, exist_ok=True)

print(f"Generating assets into: {assets_dir}")

# =============================================================================
# 1. PIXEL-PERFECT 16x16 FSM CONTROLLER STATE MACHINE DIAGRAM
# =============================================================================
fig, ax = plt.subplots(figsize=(14, 8), dpi=300)
fig.patch.set_facecolor('#0d1117') # High-tech dark slate engineering theme
ax.set_facecolor('#0d1117')
ax.axis('off')

# Title & Subtitle with distinct vertical clearance
ax.text(0.5, 0.95, "2D Systolic Array Hardware Accelerator — FSM Controller Architecture",
        ha='center', va='center', fontsize=16, fontweight='bold', color='#58a6ff')
ax.text(0.5, 0.905, "Scaled for 16×16 Matrix Operations (256 Processing Elements) | 48-Cycle Compute Pipeline",
        ha='center', va='center', fontsize=10.5, color='#8b949e')

# State Box Data: (Name, Encoding, Duration, Outputs, CenterX, CenterY, HeaderColor, BoxColor)
states = [
    {
        "name": "STATE_IDLE",
        "code": "2'b00",
        "dur": "Duration: Indefinite (Wait for start)",
        "desc": "System idle & ready\nSystolic array held in reset",
        "outputs": [
            ("array_rst", "1"),
            ("load_en",   "0"),
            ("shift_en",  "0"),
            ("array_en",  "0"),
            ("done",      "0")
        ],
        "x": 0.13, "y": 0.58,
        "hdr_color": "#1f6feb", "box_color": "#161b22"
    },
    {
        "name": "STATE_LOAD",
        "code": "2'b01",
        "dur": "Duration: Exactly 1 Cycle",
        "desc": "Parallel matrix ingestion\nLatches A & B into skew buffers",
        "outputs": [
            ("array_rst", "1"),
            ("load_en",   "1"),
            ("shift_en",  "0"),
            ("array_en",  "0"),
            ("done",      "0")
        ],
        "x": 0.38, "y": 0.58,
        "hdr_color": "#d29922", "box_color": "#161b22"
    },
    {
        "name": "STATE_COMPUTE",
        "code": "2'b10",
        "dur": "Duration: 3N - 1 = 47 Cycles (N=16)",
        "desc": "Diagonal wave-front propagation\nShift buffers active; PEs compute",
        "outputs": [
            ("array_rst", "0"),
            ("load_en",   "0"),
            ("shift_en",  "1"),
            ("array_en",  "1"),
            ("done",      "0")
        ],
        "x": 0.64, "y": 0.58,
        "hdr_color": "#238636", "box_color": "#161b22"
    },
    {
        "name": "STATE_DONE",
        "code": "2'b11",
        "dur": "Duration: 1+ Cycles (Holds until start)",
        "desc": "Matrix C fully computed & valid\nAvailable across 256 PEs",
        "outputs": [
            ("array_rst", "0"),
            ("load_en",   "0"),
            ("shift_en",  "0"),
            ("array_en",  "0"),
            ("done",      "1")
        ],
        "x": 0.89, "y": 0.58,
        "hdr_color": "#8957e5", "box_color": "#161b22"
    }
]

box_w = 0.20
box_h = 0.30

for st in states:
    bx = st["x"] - box_w / 2
    by = st["y"] - box_h / 2
    
    # Outer border
    rect_bg = patches.FancyBboxPatch((bx, by), box_w, box_h,
                                     boxstyle="round,pad=0.015,rounding_size=0.02",
                                     linewidth=1.8, edgecolor=st["hdr_color"],
                                     facecolor=st["box_color"], zorder=2)
    ax.add_patch(rect_bg)
    
    # Header bar
    hdr_h = 0.075
    rect_hdr = patches.FancyBboxPatch((bx, by + box_h - hdr_h), box_w, hdr_h,
                                      boxstyle="round,pad=0.015,rounding_size=0.02",
                                      linewidth=0, facecolor=st["hdr_color"], zorder=3)
    ax.add_patch(rect_hdr)
    
    # State name & code
    ax.text(st["x"], by + box_h - 0.024, f"{st['name']} ({st['code']})",
            ha='center', va='center', fontsize=10.5, fontweight='bold', color='#ffffff', zorder=4)
    ax.text(st["x"], by + box_h - 0.052, st["dur"],
            ha='center', va='center', fontsize=7.5, fontweight='bold', color='#e6edf3', zorder=4)
    
    # Description
    ax.text(st["x"], by + box_h - 0.105, st["desc"],
            ha='center', va='center', fontsize=8, color='#c9d1d9', zorder=4)
    
    # Divider line
    ax.plot([bx + 0.015, bx + box_w - 0.015], [by + 0.12, by + 0.12],
            color='#30363d', lw=1, zorder=4)
    
    # Outputs label
    ax.text(bx + 0.02, by + 0.098, "Control Outputs:", fontsize=7.2, fontweight='bold', color='#8b949e', zorder=4)
    
    # Output signals formatted clearly
    sig_strs = [f"{k}={v}" for k, v in st["outputs"]]
    line1 = f"{sig_strs[0]}  {sig_strs[1]}  {sig_strs[2]}"
    line2 = f"{sig_strs[3]}  {sig_strs[4]}"
    ax.text(st["x"], by + 0.062, line1, ha='center', va='center', fontsize=7.5, color='#e6edf3', fontfamily='monospace', zorder=4)
    ax.text(st["x"], by + 0.028, line2, ha='center', va='center', fontsize=7.5, color='#e6edf3', fontfamily='monospace', zorder=4)

# Forward Transition Arrows
# 1. IDLE -> LOAD
ax.annotate('', xy=(0.28, 0.58), xytext=(0.23, 0.58),
            arrowprops=dict(arrowstyle="->", lw=2.2, color='#58a6ff', mutation_scale=16), zorder=5)
ax.text(0.255, 0.615, "start == 1", ha='center', va='center', fontsize=8.5, fontweight='bold',
        color='#58a6ff', bbox=dict(boxstyle='round,pad=0.2', facecolor='#0d1117', edgecolor='#58a6ff', lw=0.8))

# 2. LOAD -> COMPUTE
ax.annotate('', xy=(0.54, 0.58), xytext=(0.48, 0.58),
            arrowprops=dict(arrowstyle="->", lw=2.2, color='#d29922', mutation_scale=16), zorder=5)
ax.text(0.51, 0.615, "1 Cycle\n(Unconditional)", ha='center', va='center', fontsize=8, fontweight='bold',
        color='#d29922', bbox=dict(boxstyle='round,pad=0.2', facecolor='#0d1117', edgecolor='#d29922', lw=0.8))

# 3. COMPUTE -> DONE
ax.annotate('', xy=(0.79, 0.58), xytext=(0.74, 0.58),
            arrowprops=dict(arrowstyle="->", lw=2.2, color='#238636', mutation_scale=16), zorder=5)
ax.text(0.765, 0.615, "cycle_count ==\n3N-2 (46)", ha='center', va='center', fontsize=8, fontweight='bold',
        color='#3fb950', bbox=dict(boxstyle='round,pad=0.2', facecolor='#0d1117', edgecolor='#238636', lw=0.8))

# 4. COMPUTE self loop (count++)
ax.annotate('', xy=(0.62, 0.73), xytext=(0.66, 0.73),
            arrowprops=dict(arrowstyle="->", lw=2, color='#3fb950',
                            connectionstyle="arc3,rad=-1.7", mutation_scale=14), zorder=5)
ax.text(0.64, 0.815, "cycle_count < 46\n(count++)", ha='center', va='center', fontsize=8,
        fontweight='bold', color='#3fb950')

# 5. DONE -> LOAD (Loopback underneath curving downwards below boxes)
ax.annotate('', xy=(0.38, 0.41), xytext=(0.89, 0.41),
            arrowprops=dict(arrowstyle="->", lw=2.2, color='#a371f7',
                            connectionstyle="arc3,rad=-0.25", mutation_scale=16), zorder=5)
ax.text(0.635, 0.315, "start == 1 (Trigger New Computation Run Without Full Hardware Reset)",
        ha='center', va='center', fontsize=8.5, fontweight='bold', color='#a371f7',
        bbox=dict(boxstyle='round,pad=0.35', facecolor='#161b22', edgecolor='#a371f7', lw=1.2), zorder=6)

# Bottom Specification Panel with clean margins & hierarchy
panel_bg = patches.FancyBboxPatch((0.04, 0.035), 0.92, 0.22,
                                  boxstyle="round,pad=0.015,rounding_size=0.015",
                                  linewidth=1.2, edgecolor='#30363d', facecolor='#161b22', zorder=2)
ax.add_patch(panel_bg)

ax.text(0.065, 0.22, "16×16 HARDWARE ACCELERATOR SYSTEM SPECIFICATIONS & METRICS",
        fontsize=10, fontweight='bold', color='#58a6ff', zorder=3)

bullets = [
    "• MATRIX DIMENSIONS: N = 16 (16×16 Dense INT8 Matrix Multiplication, 256 Total Elements per Matrix)",
    "• PROCESSING ELEMENTS: 256 PEs in 2D spatial mesh (each containing 8-bit MAC + horizontal/vertical forwarding registers)",
    "• ACCELERATOR TIMING: 1 Load Cycle + 47 Compute Cycles (3N-1) = 48 Cycles Total Latency (480 ns @ 100 MHz clock)",
    "• HARDWARE THROUGHPUT: 2 × 16³ = 8,192 Operations per 48 cycles ≈ 17.06 Giga-Operations Per Second (GOPS) @ 100 MHz",
    "• CONTROLLER SIGNALS: Fully autonomous handshake via 'start' pulse and single-cycle 'done' notification flag"
]

y_pos = 0.18
for bullet in bullets:
    ax.text(0.065, y_pos, bullet, fontsize=8, color='#c9d1d9', zorder=3)
    y_pos -= 0.032

plt.tight_layout()
plt.savefig(os.path.join(assets_dir, "fsm_diagram.png"), dpi=300, facecolor='#0d1117')
plt.close()
print("1. fsm_diagram.png updated successfully.")

# =============================================================================
# 2. 16x16 2D SYSTOLIC ARRAY ARCHITECTURE DIAGRAM
# =============================================================================
fig, ax = plt.subplots(figsize=(13, 7.5), dpi=300)
fig.patch.set_facecolor('#ffffff')
ax.set_facecolor('#ffffff')
ax.axis('off')

ax.text(0.5, 0.96, "2D Systolic Array Hardware Architecture (16×16 Grid = 256 Processing Elements)",
        ha='center', va='center', fontsize=14, fontweight='bold', color='#111827')
ax.text(0.5, 0.92, "Spatial Wave-Front Dataflow: Matrix A (Horizontal Skew) × Matrix B (Vertical Skew)",
        ha='center', va='center', fontsize=10, color='#6b7280')

grid_n = 4
pe_size = 0.075
spacing = 0.115
start_x = 0.37
start_y = 0.62

labels = [
    ["PE(0,0)", "PE(0,1)", "PE(0,2)", "PE(0,15)"],
    ["PE(1,0)", "PE(1,1)", "PE(1,2)", "PE(1,15)"],
    ["PE(2,0)", "PE(2,1)", "PE(2,2)", "PE(2,15)"],
    ["PE(15,0)", "PE(15,1)", "PE(15,2)", "PE(15,15)"]
]

for r in range(grid_n):
    for c in range(grid_n):
        px = start_x + c * spacing
        py = start_y - r * spacing
        wave_cycle = r + c
        pe_box = patches.FancyBboxPatch((px, py), pe_size, pe_size,
                                        boxstyle="round,pad=0.005",
                                        facecolor='#e0f2fe' if wave_cycle < 2 else '#bae6fd' if wave_cycle < 4 else '#7dd3fc',
                                        edgecolor='#0284c7', linewidth=1.5)
        ax.add_patch(pe_box)
        ax.text(px + pe_size/2, py + pe_size/2 + 0.012, labels[r][c],
                ha='center', va='center', fontsize=7.5, fontweight='bold', color='#0369a1')
        ax.text(px + pe_size/2, py + pe_size/2 - 0.014, "MAC",
                ha='center', va='center', fontsize=7, color='#0284c7')

# Interconnect arrows
for r in range(grid_n):
    for c in range(grid_n):
        px = start_x + c * spacing
        py = start_y - r * spacing
        if c < grid_n - 1:
            ax.annotate('', xy=(px + spacing, py + pe_size/2), xytext=(px + pe_size, py + pe_size/2),
                        arrowprops=dict(arrowstyle="->", lw=1.2, color='#2563eb'))
        if r < grid_n - 1:
            ax.annotate('', xy=(px + pe_size/2, py - spacing + pe_size), xytext=(px + pe_size/2, py),
                        arrowprops=dict(arrowstyle="->", lw=1.2, color='#16a34a'))

ax.text(start_x + 2.5 * spacing + pe_size/2, start_y - 1.5 * spacing + pe_size/2, "· · ·\n(Cols 3-14)",
        ha='center', va='center', fontsize=8, color='#64748b', fontweight='bold')
ax.text(start_x + 1.5 * spacing + pe_size/2, start_y - 2.5 * spacing + pe_size/2, "· · · (Rows 3-14)",
        ha='center', va='center', fontsize=8, color='#64748b', fontweight='bold')

# Matrix A Skew Buffer (Left)
skew_a_box = patches.FancyBboxPatch((0.08, start_y - 3*spacing), 0.20, 3*spacing + pe_size,
                                    boxstyle="round,pad=0.01",
                                    facecolor='#fef3c7', edgecolor='#d97706', linewidth=2)
ax.add_patch(skew_a_box)
ax.text(0.18, start_y - 1.5*spacing + pe_size/2,
        "Matrix A Skew Buffer\n(16 Rows × 31 Stages)\n\nDelay Formulation:\nRow r = r cycles delay\n(Row 0: 0, ..., Row 15: 15)",
        ha='center', va='center', fontsize=8.2, fontweight='bold', color='#92400e')

for r in range(grid_n):
    py = start_y - r * spacing + pe_size/2
    ax.annotate('', xy=(start_x, py), xytext=(0.28, py),
                arrowprops=dict(arrowstyle="->", lw=1.6, color='#d97706'))

# Matrix B Skew Buffer (Top)
skew_b_box = patches.FancyBboxPatch((start_x, start_y + pe_size + 0.05), 3*spacing + pe_size, 0.11,
                                    boxstyle="round,pad=0.01",
                                    facecolor='#dcfce7', edgecolor='#16a34a', linewidth=2)
ax.add_patch(skew_b_box)
ax.text(start_x + 1.5*spacing + pe_size/2, start_y + pe_size + 0.105,
        "Matrix B Column Skew Buffer (16 Cols × 31 Stages) — Delay: Col c = c cycles",
        ha='center', va='center', fontsize=8.5, fontweight='bold', color='#166534')

for c in range(grid_n):
    px = start_x + c * spacing + pe_size/2
    ax.annotate('', xy=(px, start_y + pe_size), xytext=(px, start_y + pe_size + 0.05),
                arrowprops=dict(arrowstyle="->", lw=1.6, color='#16a34a'))

# Controller Box
ctrl_box = patches.FancyBboxPatch((0.08, 0.05), 0.84, 0.13,
                                  boxstyle="round,pad=0.01",
                                  facecolor='#f3e8ff', edgecolor='#9333ea', linewidth=1.8)
ax.add_patch(ctrl_box)
ax.text(0.5, 0.135, "FSM Central Controller & Autonomous Handshake",
        ha='center', va='center', fontsize=10.5, fontweight='bold', color='#6b21a8')
ax.text(0.5, 0.085, "Inputs: clk, rst, start  |  Outputs: load_en (Buf Load), shift_en (Stream), array_en (Clock PEs), array_rst, done (Cycle 48)\nLatency = 1 cycle (Load) + 47 cycles (Compute 3N-1) = 48 Clock Cycles (480 ns @ 100MHz)",
        ha='center', va='center', fontsize=8.2, color='#581c87')

plt.tight_layout()
plt.savefig(os.path.join(assets_dir, "systolic_16x16_architecture.png"), dpi=300)
plt.close()
print("2. systolic_16x16_architecture.png updated successfully.")

print("All asset updates completed.")
