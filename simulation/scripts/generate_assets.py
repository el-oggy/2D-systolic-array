import os
import matplotlib.pyplot as plt
import numpy as np

# Create assets directory
assets_dir = r"c:\Users\adars\OneDrive\Desktop\vs-code\simulation\assets"
os.makedirs(assets_dir, exist_ok=True)

# -----------------------------------------------------------------------------
# 1. Processing Element (PE) Timing Waveform
# -----------------------------------------------------------------------------
fig, axs = plt.subplots(6, 1, figsize=(10, 6), sharex=True)
fig.patch.set_facecolor('#ffffff')
plt.subplots_adjust(hspace=0.4, top=0.92, bottom=0.1, left=0.15, right=0.95)

time = np.array([0, 1, 2, 3, 4, 5, 6, 7])
clk = [0, 1, 0, 1, 0, 1, 0, 1]

# Step wave functions
def plot_digital(ax, t, val, label, color='#1f77b4', is_bus=False):
    t_step = np.repeat(t, 2)[1:]
    val_step = np.repeat(val, 2)[:-1]
    ax.step(t_step, val_step, where='post', color=color, linewidth=2)
    ax.set_ylabel(label, rotation=0, labelpad=35, va='center', fontweight='bold', fontsize=9)
    ax.grid(True, linestyle=':', alpha=0.6)
    ax.set_ylim(-0.2, max(val_step)*1.2 if is_bus and max(val_step) > 0 else 1.2)
    if is_bus:
        for i in range(len(t)-1):
            if val[i] != 0 or i in [2, 3, 4]:
                ax.text(t[i]+0.5, val[i]*0.5 if val[i]>0 else 0.5, str(val[i]), 
                        ha='center', va='center', fontsize=8, color='#003366', fontweight='bold')

# Signals for PE
t = np.arange(8)
clk_sig = [0, 1, 0, 1, 0, 1, 0, 1]
rst_sig = [1, 1, 0, 0, 0, 0, 0, 0]
en_sig  = [0, 0, 1, 1, 1, 0, 0, 0]
a_in_sig= [0, 0, 1, 2, 3, 0, 0, 0]
b_in_sig= [0, 0, 7, 10, 13, 0, 0, 0]
acc_sig = [0, 0, 7, 27, 66, 66, 66, 66]

plot_digital(axs[0], t, [0, 1, 0, 1, 0, 1, 0, 1], 'clk', color='#333333')
plot_digital(axs[1], t, rst_sig, 'rst', color='#d62728')
plot_digital(axs[2], t, en_sig, 'en', color='#2ca02c')
plot_digital(axs[3], t, a_in_sig, 'a_in', color='#1f77b4', is_bus=True)
plot_digital(axs[4], t, b_in_sig, 'b_in', color='#9467bd', is_bus=True)
plot_digital(axs[5], t, acc_sig, 'acc', color='#ff7f0e', is_bus=True)

axs[5].set_xlabel("Clock Cycles / Simulation Time Steps", fontweight='bold')
axs[0].set_title("Single Processing Element (PE) Simulation Waveform (1*7 + 2*10 + 3*13 = 66)", fontweight='bold', fontsize=11)

plt.savefig(os.path.join(assets_dir, "pe_waveform.png"), dpi=300, bbox_inches='tight')
plt.close()

# -----------------------------------------------------------------------------
# 2. Skew Buffer Delay Stagger Diagram
# -----------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(9, 4))
fig.patch.set_facecolor('#ffffff')

cycles = ['Cycle 0', 'Cycle 1', 'Cycle 2', 'Cycle 3', 'Cycle 4']
rows = ['Row 0 (delay 0)', 'Row 1 (delay 1)', 'Row 2 (delay 2)']

data = np.array([
    [1, 2, 3, 0, 0],
    [0, 4, 5, 6, 0],
    [0, 0, 7, 8, 9]
])

cax = ax.matshow(data, cmap='Blues', alpha=0.8)

for i in range(len(rows)):
    for j in range(len(cycles)):
        val = data[i, j]
        color = 'black' if val == 0 else 'white' if val > 4 else 'black'
        text_str = f"Data = {val}" if val != 0 else "0 (idle)"
        ax.text(j, i, text_str, ha='center', va='center', fontweight='bold', fontsize=10, color=color)

ax.set_xticks(range(len(cycles)))
ax.set_xticklabels(cycles, fontweight='bold', fontsize=10)
ax.set_yticks(range(len(rows)))
ax.set_yticklabels(rows, fontweight='bold', fontsize=10)
ax.set_title("Skew Buffer Row-Staggering Sequence (3x3 Matrix)", fontweight='bold', fontsize=12, pad=15)

plt.savefig(os.path.join(assets_dir, "skew_buffer_diagram.png"), dpi=300, bbox_inches='tight')
plt.close()

# -----------------------------------------------------------------------------
# 3. 2x2 Systolic Spatial Propagation Waveform
# -----------------------------------------------------------------------------
fig, axs = plt.subplots(5, 1, figsize=(10, 6), sharex=True)
fig.patch.set_facecolor('#ffffff')
plt.subplots_adjust(hspace=0.4, top=0.92, bottom=0.1, left=0.15, right=0.95)

t = np.arange(6)
pe00_acc = [0, 5, 19, 19, 19, 19]
pe01_acc = [0, 0, 6, 22, 22, 22]
pe10_acc = [0, 0, 15, 43, 43, 43]
pe11_acc = [0, 0, 0, 18, 50, 50]

plot_digital(axs[0], t, [0, 1, 0, 1, 0, 1], 'clk', color='#333333')
plot_digital(axs[1], t, pe00_acc, 'PE[0][0]\nacc (C00)', color='#1f77b4', is_bus=True)
plot_digital(axs[2], t, pe01_acc, 'PE[0][1]\nacc (C01)', color='#2ca02c', is_bus=True)
plot_digital(axs[3], t, pe10_acc, 'PE[1][0]\nacc (C10)', color='#9467bd', is_bus=True)
plot_digital(axs[4], t, pe11_acc, 'PE[1][1]\nacc (C11)', color='#d62728', is_bus=True)

axs[4].set_xlabel("Clock Cycle Index", fontweight='bold')
axs[0].set_title("2x2 Systolic Array Grid Accumulation Progression (C = [[19, 22], [43, 50]])", fontweight='bold', fontsize=11)

plt.savefig(os.path.join(assets_dir, "systolic_2x2_waveform.png"), dpi=300, bbox_inches='tight')
plt.close()

# -----------------------------------------------------------------------------
# 4. Top-Level FSM Controller State Machine
# -----------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(10, 3.2))
fig.patch.set_facecolor('#ffffff')
ax.axis('off')

# Box definitions
boxes = [
    ("STATE_IDLE (0)\narray_rst=1, done=0\nWait for 'start'", 0.1, 0.5, '#e0f2fe', '#0284c7'),
    ("STATE_LOAD (1)\nload_en=1, array_rst=1\nLoad Skew Buffers", 0.38, 0.5, '#fef3c7', '#d97706'),
    ("STATE_COMPUTE (2)\nshift_en=1, array_en=1\nFeed & Propagate (3N-1 cyc)", 0.68, 0.5, '#dcfce7', '#16a34a'),
    ("STATE_DONE (3)\ndone=1\nResults Valid", 0.93, 0.5, '#f3e8ff', '#9333ea'),
]

for label, x, y, bg, border in boxes:
    ax.text(x, y, label, ha='center', va='center',
            bbox=dict(boxstyle='round,pad=0.6', facecolor=bg, edgecolor=border, linewidth=2),
            fontweight='bold', fontsize=9)

# Arrows
ax.annotate('', xy=(0.28, 0.5), xytext=(0.20, 0.5), arrowprops=dict(arrowstyle="->", lw=2, color='#333333'))
ax.text(0.24, 0.56, "start=1", ha='center', fontsize=8, fontweight='bold')

ax.annotate('', xy=(0.54, 0.5), xytext=(0.48, 0.5), arrowprops=dict(arrowstyle="->", lw=2, color='#333333'))
ax.text(0.51, 0.56, "1 cycle", ha='center', fontsize=8, fontweight='bold')

ax.annotate('', xy=(0.84, 0.5), xytext=(0.80, 0.5), arrowprops=dict(arrowstyle="->", lw=2, color='#333333'))
ax.text(0.82, 0.56, "count=3N-2", ha='center', fontsize=8, fontweight='bold')

ax.set_title("Systolic Array FSM Controller Architecture & State Transitions", fontweight='bold', fontsize=12, pad=10)
plt.savefig(os.path.join(assets_dir, "fsm_diagram.png"), dpi=300, bbox_inches='tight')
plt.close()

print("All asset diagrams generated successfully.")
