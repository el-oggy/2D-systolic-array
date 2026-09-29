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
# 1. CLEAN MINIMALIST WHITE-BACKGROUND FSM CONTROLLER STATE DIAGRAM
# =============================================================================
fig, ax = plt.subplots(figsize=(14, 7.8), dpi=300)
fig.patch.set_facecolor('#ffffff') # Clean white background requested by user
ax.set_facecolor('#ffffff')
ax.axis('off')

# Title & Subtitle with crisp contrast
ax.text(0.5, 0.95, "2D Systolic Array Hardware Accelerator — FSM Controller Architecture",
        ha='center', va='center', fontsize=16, fontweight='bold', color='#0f172a', fontfamily='sans-serif')
ax.text(0.5, 0.91, "Scaled for 16×16 Matrix Operations (256 Processing Elements) | 48-Cycle Autonomous Execution",
        ha='center', va='center', fontsize=10.5, color='#475569', fontfamily='sans-serif')

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
        "hdr_color": "#0284c7", "box_bg": "#f8fafc", "border_col": "#0369a1"
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
        "hdr_color": "#d97706", "box_bg": "#fffbeb", "border_col": "#b45309"
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
        "hdr_color": "#16a34a", "box_bg": "#f0fdf4", "border_col": "#15803d"
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
        "hdr_color": "#7c3aed", "box_bg": "#faf5ff", "border_col": "#6d28d9"
    }
]

box_w = 0.20
box_h = 0.30

for st in states:
    bx = st["x"] - box_w / 2
    by = st["y"] - box_h / 2
    
    # Outer box
    rect_bg = patches.FancyBboxPatch((bx, by), box_w, box_h,
                                     boxstyle="round,pad=0.012,rounding_size=0.02",
                                     linewidth=1.8, edgecolor=st["border_col"],
                                     facecolor=st["box_bg"], zorder=2)
    ax.add_patch(rect_bg)
    
    # Header bar
    hdr_h = 0.075
    rect_hdr = patches.FancyBboxPatch((bx, by + box_h - hdr_h), box_w, hdr_h,
                                      boxstyle="round,pad=0.012,rounding_size=0.02",
                                      linewidth=0, facecolor=st["hdr_color"], zorder=3)
    ax.add_patch(rect_hdr)
    
    # State name & code
    ax.text(st["x"], by + box_h - 0.024, f"{st['name']} ({st['code']})",
            ha='center', va='center', fontsize=10, fontweight='bold', color='#ffffff', zorder=4)
    ax.text(st["x"], by + box_h - 0.052, st["dur"],
            ha='center', va='center', fontsize=7.5, fontweight='bold', color='#f8fafc', zorder=4)
    
    # Description
    ax.text(st["x"], by + box_h - 0.105, st["desc"],
            ha='center', va='center', fontsize=8, color='#334155', zorder=4)
    
    # Divider line
    ax.plot([bx + 0.015, bx + box_w - 0.015], [by + 0.12, by + 0.12],
            color='#cbd5e1', lw=1, zorder=4)
    
    # Outputs label
    ax.text(bx + 0.02, by + 0.098, "Control Outputs:", fontsize=7.2, fontweight='bold', color='#64748b', zorder=4)
    
    # Output signals
    sig_strs = [f"{k}={v}" for k, v in st["outputs"]]
    line1 = f"{sig_strs[0]}  {sig_strs[1]}  {sig_strs[2]}"
    line2 = f"{sig_strs[3]}  {sig_strs[4]}"
    ax.text(st["x"], by + 0.062, line1, ha='center', va='center', fontsize=7.5, color='#0f172a', fontfamily='monospace', zorder=4)
    ax.text(st["x"], by + 0.028, line2, ha='center', va='center', fontsize=7.5, color='#0f172a', fontfamily='monospace', zorder=4)

# Transition Arrows (High contrast dark grey #334155 with colored labels)
# 1. IDLE -> LOAD
ax.annotate('', xy=(0.28, 0.58), xytext=(0.23, 0.58),
            arrowprops=dict(arrowstyle="->", lw=2.2, color='#0284c7', mutation_scale=15), zorder=5)
ax.text(0.255, 0.615, "start == 1", ha='center', va='center', fontsize=8.5, fontweight='bold',
        color='#0284c7', bbox=dict(boxstyle='round,pad=0.2', facecolor='#ffffff', edgecolor='#0284c7', lw=0.8))

# 2. LOAD -> COMPUTE
ax.annotate('', xy=(0.54, 0.58), xytext=(0.48, 0.58),
            arrowprops=dict(arrowstyle="->", lw=2.2, color='#d97706', mutation_scale=15), zorder=5)
ax.text(0.51, 0.615, "1 Cycle\n(Unconditional)", ha='center', va='center', fontsize=8, fontweight='bold',
        color='#d97706', bbox=dict(boxstyle='round,pad=0.2', facecolor='#ffffff', edgecolor='#d97706', lw=0.8))

# 3. COMPUTE -> DONE
ax.annotate('', xy=(0.79, 0.58), xytext=(0.74, 0.58),
            arrowprops=dict(arrowstyle="->", lw=2.2, color='#16a34a', mutation_scale=15), zorder=5)
ax.text(0.765, 0.615, "cycle_count ==\n3N-2 (46)", ha='center', va='center', fontsize=8, fontweight='bold',
        color='#16a34a', bbox=dict(boxstyle='round,pad=0.2', facecolor='#ffffff', edgecolor='#16a34a', lw=0.8))

# 4. COMPUTE self loop
ax.annotate('', xy=(0.62, 0.73), xytext=(0.66, 0.73),
            arrowprops=dict(arrowstyle="->", lw=2, color='#16a34a',
                            connectionstyle="arc3,rad=-1.7", mutation_scale=14), zorder=5)
ax.text(0.64, 0.815, "cycle_count < 46\n(count++)", ha='center', va='center', fontsize=8,
        fontweight='bold', color='#16a34a')

# 5. DONE -> LOAD (Loopback underneath)
ax.annotate('', xy=(0.38, 0.41), xytext=(0.89, 0.41),
            arrowprops=dict(arrowstyle="->", lw=2.2, color='#7c3aed',
                            connectionstyle="arc3,rad=-0.25", mutation_scale=16), zorder=5)
ax.text(0.635, 0.315, "start == 1 (Launch New Computation Without Hardware Reset)",
        ha='center', va='center', fontsize=8.5, fontweight='bold', color='#7c3aed',
        bbox=dict(boxstyle='round,pad=0.35', facecolor='#ffffff', edgecolor='#7c3aed', lw=1.2), zorder=6)

# Bottom Specification Table Panel (Clean White Card)
panel_bg = patches.FancyBboxPatch((0.04, 0.035), 0.92, 0.22,
                                  boxstyle="round,pad=0.015,rounding_size=0.015",
                                  linewidth=1.2, edgecolor='#cbd5e1', facecolor='#f8fafc', zorder=2)
ax.add_patch(panel_bg)

ax.text(0.065, 0.22, "16×16 HARDWARE ACCELERATOR SYSTEM SPECIFICATIONS & METRICS",
        fontsize=10, fontweight='bold', color='#0f172a', zorder=3)

bullets = [
    "• MATRIX DIMENSIONS: N = 16 (16×16 Dense INT8 Matrix Multiplication, 256 Total Elements per Matrix)",
    "• PROCESSING ELEMENTS: 256 PEs in 2D spatial mesh (each containing 8-bit MAC + horizontal/vertical forwarding registers)",
    "• ACCELERATOR TIMING: 1 Load Cycle + 47 Compute Cycles (3N-1) = 48 Cycles Total Latency (480 ns @ 100 MHz clock)",
    "• HARDWARE THROUGHPUT: 2 × 16³ = 8,192 Operations per 48 cycles ≈ 17.06 Giga-Operations Per Second (GOPS) @ 100 MHz",
    "• CONTROLLER SIGNALS: Fully autonomous handshake via 'start' pulse and single-cycle 'done' notification flag"
]

y_pos = 0.18
for bullet in bullets:
    ax.text(0.065, y_pos, bullet, fontsize=8, color='#334155', zorder=3)
    y_pos -= 0.032

plt.tight_layout()
plt.savefig(os.path.join(assets_dir, "fsm_diagram.png"), dpi=300, facecolor='#ffffff')
plt.close()
print("1. fsm_diagram.png updated with clean white background.")

# =============================================================================
# 2. SINGLE PE WAVEFORM FOR 16x16 MULTIPLICATION (16-CYCLE ACCUMULATION)
# =============================================================================
fig, axs = plt.subplots(7, 1, figsize=(12, 7.5), sharex=True, dpi=300)
fig.patch.set_facecolor('#ffffff')
plt.subplots_adjust(hspace=0.45, top=0.92, bottom=0.08, left=0.12, right=0.96)

cycles = 19
t = np.arange(cycles)

# Values for 16-cycle MAC: a_in = [1..16], b_in = [2..2] (constant 2 for clear visual math)
clk_sig = [i % 2 for i in range(cycles)]
rst_sig = [1 if i == 0 else 0 for i in range(cycles)]
en_sig  = [1 if 1 <= i <= 16 else 0 for i in range(cycles)]
a_in_sig= [0 if i == 0 or i > 16 else (i * 3) - 10 for i in range(cycles)] # signed variations
b_in_sig= [0 if i == 0 or i > 16 else (2 if i % 2 == 0 else -1) for i in range(cycles)]

# Calculate theoretical acc, a_out, b_out
acc_val = 0
acc_sig = [0] * cycles
a_out_sig = [0] * cycles
b_out_sig = [0] * cycles

for i in range(1, cycles):
    if en_sig[i]:
        acc_val += (a_in_sig[i] * b_in_sig[i])
        acc_sig[i] = acc_val
        a_out_sig[i] = a_in_sig[i]
        b_out_sig[i] = b_in_sig[i]
    else:
        acc_sig[i] = acc_val
        a_out_sig[i] = 0
        b_out_sig[i] = 0

def plot_step_sig(ax, t, val, label, color='#1f77b4', is_bus=False):
    t_step = np.repeat(t, 2)[1:]
    val_step = np.repeat(val, 2)[:-1]
    ax.step(t_step, val_step, where='post', color=color, linewidth=1.8)
    ax.set_ylabel(label, rotation=0, labelpad=40, va='center', fontweight='bold', fontsize=8.5, color='#0f172a')
    ax.grid(True, linestyle=':', alpha=0.5, color='#94a3b8')
    if is_bus:
        ymin = min(val_step)
        ymax = max(val_step)
        margin = max(abs(ymax - ymin) * 0.25, 2)
        ax.set_ylim(ymin - margin, ymax + margin)
        for i in range(len(t)-1):
            if val[i] != 0 or i in [1, 2, 16]:
                ax.text(t[i]+0.5, val[i], str(val[i]), ha='center', va='bottom', fontsize=7, color=color, fontweight='bold')
    else:
        ax.set_ylim(-0.2, 1.2)

plot_step_sig(axs[0], t, [i % 2 for i in range(cycles)], 'clk', color='#334155')
plot_step_sig(axs[1], t, rst_sig, 'rst', color='#dc2626')
plot_step_sig(axs[2], t, en_sig, 'en', color='#16a34a')
plot_step_sig(axs[3], t, a_in_sig, 'a_in', color='#0284c7', is_bus=True)
plot_step_sig(axs[4], t, b_in_sig, 'b_in', color='#9333ea', is_bus=True)
plot_step_sig(axs[5], t, a_out_sig, 'a_out (fwd)', color='#0369a1', is_bus=True)
plot_step_sig(axs[6], t, acc_sig, 'acc (sum)', color='#ea580c', is_bus=True)

axs[6].set_xlabel("Clock Cycle Index (16 Clock Cycles of Dot-Product Multiply-Accumulation)", fontweight='bold', fontsize=9.5, color='#0f172a')
axs[0].set_title("Single Processing Element (PE) Waveform — 16-Cycle Vector Dot-Product (acc <= acc + a_in * b_in)", fontweight='bold', fontsize=11, color='#0f172a')

plt.savefig(os.path.join(assets_dir, "pe_16x16_waveform.png"), dpi=300, facecolor='#ffffff')
plt.close()
print("2. pe_16x16_waveform.png generated successfully.")

# =============================================================================
# 3. 16x16 GRID OUTPUT WAVE-FRONT PROGRESSION WAVEFORM
# =============================================================================
fig, axs = plt.subplots(6, 1, figsize=(13, 7.5), sharex=True, dpi=300)
fig.patch.set_facecolor('#ffffff')
plt.subplots_adjust(hspace=0.45, top=0.92, bottom=0.08, left=0.14, right=0.96)

total_cycles = 50
t = np.arange(total_cycles)

# Representative PE output completions along diagonal: (r, c) reaches final product at cycle r + c + N
# PE(0,0): completes at cycle 0 + 0 + 16 = 16
# PE(3,3): completes at cycle 3 + 3 + 16 = 22
# PE(7,7): completes at cycle 7 + 7 + 16 = 30
# PE(11,11): completes at cycle 11 + 11 + 16 = 38
# PE(15,15): completes at cycle 15 + 15 + 16 = 46
# done asserts at cycle 47/48

pe00_acc = [0 if i < 1 else min(i * 12, 192) for i in range(total_cycles)]
pe33_acc = [0 if i < 7 else min((i-6) * 12, 192) for i in range(total_cycles)]
pe77_acc = [0 if i < 15 else min((i-14) * 12, 192) for i in range(total_cycles)]
pe11_acc = [0 if i < 23 else min((i-22) * 12, 192) for i in range(total_cycles)]
pe15_acc = [0 if i < 31 else min((i-30) * 12, 192) for i in range(total_cycles)]
done_sig = [1 if i >= 47 else 0 for i in range(total_cycles)]

plot_step_sig(axs[0], t, [i % 2 for i in range(total_cycles)], 'clk', color='#334155')
plot_step_sig(axs[1], t, pe00_acc, 'PE[0][0]\n(Row 0, Col 0)', color='#0284c7', is_bus=True)
plot_step_sig(axs[2], t, pe33_acc, 'PE[3][3]\n(Row 3, Col 3)', color='#0d9488', is_bus=True)
plot_step_sig(axs[3], t, pe77_acc, 'PE[7][7]\n(Row 7, Col 7)', color='#16a34a', is_bus=True)
plot_step_sig(axs[4], t, pe15_acc, 'PE[15][15]\n(Corner PE)', color='#d97706', is_bus=True)
plot_step_sig(axs[5], t, done_sig, 'done (valid)', color='#7c3aed', is_bus=False)

axs[5].set_xlabel("Simulation Clock Cycles (Total Latency: 48 Cycles @ 100 MHz)", fontweight='bold', fontsize=9.5, color='#0f172a')
axs[0].set_title("16×16 Systolic Array Spatial Wave-Front Diagonal Progression Waveform", fontweight='bold', fontsize=11, color='#0f172a')

plt.savefig(os.path.join(assets_dir, "systolic_16x16_waveform.png"), dpi=300, facecolor='#ffffff')
plt.close()
print("3. systolic_16x16_waveform.png generated successfully.")

print("All asset updates completed.")
