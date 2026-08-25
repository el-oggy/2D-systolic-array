import os
import sys
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image, KeepTogether, HRFlowable, PageBreak
)
from reportlab.pdfgen import canvas

assets_dir = r"c:\Users\adars\OneDrive\Desktop\vs-code\simulation\assets"
pdf_output_path = r"c:\Users\adars\OneDrive\Desktop\vs-code\2D_Systolic_Array_Vivado_Complete_Guide.pdf"
pdf_output_path_local = r"c:\Users\adars\OneDrive\Desktop\vs-code\simulation\2D_Systolic_Array_Vivado_Complete_Guide.pdf"

class NumberedCanvas(canvas.Canvas):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_header_footer(num_pages)
            super().showPage()
        super().save()

    def draw_header_footer(self, page_count):
        self.saveState()
        self.setFont("Helvetica", 8)
        self.setFillColor(colors.HexColor("#555555"))
        
        # Header (pages > 1)
        if self._pageNumber > 1:
            self.drawString(54, letter[1] - 36, "2D Systolic Array Hardware Accelerator — Vivado Simulation & Hardware Guide")
            self.setStrokeColor(colors.HexColor("#cccccc"))
            self.setLineWidth(0.5)
            self.line(54, letter[1] - 42, letter[0] - 54, letter[1] - 42)
        
        # Footer
        footer_text = f"Page {self._pageNumber} of {page_count}"
        self.drawRightString(letter[0] - 54, 36, footer_text)
        self.drawString(54, 36, "CONFIDENTIAL & PROPRIETARY — FPGA & RTL DESIGN MANUAL")
        self.setStrokeColor(colors.HexColor("#cccccc"))
        self.setLineWidth(0.5)
        self.line(54, 48, letter[0] - 54, 48)
        
        self.restoreState()

def build_pdf():
    doc = SimpleDocTemplate(
        pdf_output_path,
        pagesize=letter,
        leftMargin=54,
        rightMargin=54,
        topMargin=54,
        bottomMargin=54
    )

    styles = getSampleStyleSheet()
    
    # Custom styles
    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=22,
        leading=26,
        textColor=colors.HexColor('#0f2942'),
        spaceAfter=6
    )
    
    subtitle_style = ParagraphStyle(
        'DocSubTitle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=12,
        leading=16,
        textColor=colors.HexColor('#2b6cb0'),
        spaceAfter=15
    )

    h1_style = ParagraphStyle(
        'Heading1_Custom',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=14,
        leading=18,
        textColor=colors.HexColor('#0f2942'),
        spaceBefore=14,
        spaceAfter=8,
        keepWithNext=True
    )

    h2_style = ParagraphStyle(
        'Heading2_Custom',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=11,
        leading=15,
        textColor=colors.HexColor('#1a5276'),
        spaceBefore=10,
        spaceAfter=6,
        keepWithNext=True
    )

    body_style = ParagraphStyle(
        'Body_Custom',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=9.5,
        leading=13.5,
        textColor=colors.HexColor('#222222'),
        spaceAfter=6
    )

    code_style = ParagraphStyle(
        'Code_Custom',
        parent=styles['Normal'],
        fontName='Courier',
        fontSize=8,
        leading=10.5,
        textColor=colors.HexColor('#111827'),
        backColor=colors.HexColor('#f3f4f6'),
        borderPadding=6,
        spaceAfter=6
    )

    callout_style = ParagraphStyle(
        'Callout_Custom',
        parent=styles['Normal'],
        fontName='Helvetica-Oblique',
        fontSize=9,
        leading=13,
        textColor=colors.HexColor('#1e3a8a'),
        backColor=colors.HexColor('#eff6ff'),
        borderColor=colors.HexColor('#3b82f6'),
        borderWidth=1,
        borderPadding=6,
        spaceAfter=8
    )

    story = []

    # -------------------------------------------------------------------------
    # COVER / HEADER
    # -------------------------------------------------------------------------
    story.append(Paragraph("2D Systolic Array Hardware Accelerator", title_style))
    story.append(Paragraph("Architecture, Step-by-Step Vivado Simulation, Tcl Automation & Basys 3 FPGA Deployment", subtitle_style))
    story.append(HRFlowable(width="100%", thickness=2, color=colors.HexColor('#0f2942'), spaceAfter=12))

    # Meta Info Table
    meta_data = [
        [Paragraph("<b>Target Device:</b> Xilinx Artix-7 (XC7A35T-1CPG236C / Basys 3)", body_style),
         Paragraph("<b>Design Standard:</b> SystemVerilog (IEEE 1800)", body_style)],
        [Paragraph("<b>EDA Tools:</b> AMD Xilinx Vivado (XSim / xvlog / xelab)", body_style),
         Paragraph("<b>Clock Frequency:</b> 100 MHz (10 ns period)", body_style)],
        [Paragraph("<b>Array Dimension:</b> Parametric N×N (Configured for 4×4)", body_style),
         Paragraph("<b>Data Precision:</b> 8-bit Signed Int (16-bit Acc)", body_style)]
    ]
    meta_table = Table(meta_data, colWidths=[250, 250])
    meta_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), colors.HexColor('#f8fafc')),
        ('BOX', (0, 0), (-1, -1), 1, colors.HexColor('#cbd5e1')),
        ('INNERGRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#e2e8f0')),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]))
    story.append(meta_table)
    story.append(Spacer(1, 10))

    # Executive Summary Box
    summary_text = (
        "<b>Executive Summary:</b> This manual provides the complete technical design, verification methodology, "
        "and hardware implementation steps for a high-throughput 2D Systolic Array matrix multiplier. "
        "It details the root-cause fixes for common Vivado errors (unpacked array port syntax, timescale mismatch, "
        "unconstrained I/O DRC), demonstrates 4-step progressive simulation with full waveform analysis, "
        "and details Vivado Tcl automation alongside an interactive Basys 3 hardware demo."
    )
    story.append(Paragraph(summary_text, callout_style))
    story.append(Spacer(1, 6))

    # -------------------------------------------------------------------------
    # CHAPTER 1: SYSTEM ARCHITECTURE
    # -------------------------------------------------------------------------
    story.append(Paragraph("1. Hardware Architecture & Mathematical Principles", h1_style))
    story.append(Paragraph(
        "A systolic array is a specialized spatial hardware accelerator where identical Processing Elements (PEs) "
        "are rhythmically computed and passed through a 2D grid. Unlike traditional von Neumann architectures that "
        "repeatedly fetch operands from memory, a systolic array reuses data horizontally and vertically across the grid.",
        body_style
    ))

    # Mathematical Formula
    math_text = (
        "For matrix multiplication <b>C = A × B</b> where A and B are N×N matrices:<br/>"
        "&nbsp;&nbsp;&nbsp;&nbsp;<b>C[i][j] = &sum;<sub>k=0</sub><sup>N-1</sup> ( A[i][k] &times; B[k][j] )</b><br/>"
        "Each PE[i][j] accumulates products over time while forwarding A elements to its right neighbor and B elements to its bottom neighbor."
    )
    story.append(Paragraph(math_text, callout_style))

    story.append(Paragraph("1.1 Core Components", h2_style))
    comp_table_data = [
        [Paragraph("<b>Component</b>", body_style), Paragraph("<b>File</b>", body_style), Paragraph("<b>Function & Key Architectural Role</b>", body_style)],
        [Paragraph("<b>Processing Element (PE)</b>", body_style), Paragraph("<code>processing_element.sv</code>", body_style), Paragraph("Multiply-Accumulate (MAC) core: <code>acc <= acc + (a_in * b_in)</code> with 1-cycle horizontal (<code>a_out</code>) and vertical (<code>b_out</code>) forwarding registers.", body_style)],
        [Paragraph("<b>Systolic Array Mesh</b>", body_style), Paragraph("<code>systolic_array.sv</code>", body_style), Paragraph("2D grid of N×N PEs with boundary edge wiring and inter-PE interconnect buses.", body_style)],
        [Paragraph("<b>Skew Buffer</b>", body_style), Paragraph("<code>skew_buffer.sv</code>", body_style), Paragraph("Parallel-to-serial delay-line buffer. Staggers row <i>i</i> by <i>i</i> clock cycles so wavefronts align perfectly inside the array.", body_style)],
        [Paragraph("<b>FSM Controller</b>", body_style), Paragraph("<code>controller.sv</code>", body_style), Paragraph("State machine sequencing <code>IDLE &rarr; LOAD &rarr; COMPUTE &rarr; DONE</code> over <b>3N - 1</b> clock cycles.", body_style)],
        [Paragraph("<b>Top System</b>", body_style), Paragraph("<code>systolic_top.sv</code>", body_style), Paragraph("Integrates FSM, Skew Buffer A (rows), Skew Buffer B (transposed cols), and the N×N PE array.", body_style)]
    ]
    comp_table = Table(comp_table_data, colWidths=[110, 110, 280])
    comp_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f2942')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]))
    story.append(comp_table)
    story.append(Spacer(1, 8))

    # FSM Image
    if os.path.exists(os.path.join(assets_dir, "fsm_diagram.png")):
        story.append(Paragraph("<b>Figure 1: FSM Controller State Transitions & Timing Flow</b>", h2_style))
        story.append(Image(os.path.join(assets_dir, "fsm_diagram.png"), width=6.8*inch, height=2.1*inch))
        story.append(Spacer(1, 8))

    # -------------------------------------------------------------------------
    # CHAPTER 2: STEP-BY-STEP SIMULATION & WAVEFORMS
    # -------------------------------------------------------------------------
    story.append(Paragraph("2. Progressive Step-by-Step Simulation & Waveforms", h1_style))
    story.append(Paragraph(
        "Verification is conducted in four modular, progressive tiers to isolate and guarantee correct behavior "
        "at the unit, interconnect, buffer, and full-system levels.",
        body_style
    ))

    # STEP 1
    story.append(Paragraph("Step 1: Single Processing Element Verification (<code>tb_step1_pe.sv</code>)", h2_style))
    story.append(Paragraph(
        "Validates the atomic MAC unit. Feed A=[1, 2, 3] and B=[7, 10, 13]:<br/>"
        "&bull; Cycle 0: 1 &times; 7 = 7 &rarr; acc = 7<br/>"
        "&bull; Cycle 1: 2 &times; 10 = 20 &rarr; acc = 7 + 20 = 27 (a_out=1, b_out=7)<br/>"
        "&bull; Cycle 2: 3 &times; 13 = 39 &rarr; acc = 27 + 39 = <b>66</b> (a_out=2, b_out=10)<br/>"
        "&bull; Cycle 3: en=0 &rarr; acc holds 66, a_out=3, b_out=13. <b>[100% PASS]</b>",
        body_style
    ))

    if os.path.exists(os.path.join(assets_dir, "pe_waveform.png")):
        story.append(Image(os.path.join(assets_dir, "pe_waveform.png"), width=6.8*inch, height=3.8*inch))
        story.append(Spacer(1, 8))

    # STEP 2
    story.append(Paragraph("Step 2: 2×2 Systolic Array Grid Test (<code>tb_step2_systolic_2x2.sv</code>)", h2_style))
    story.append(Paragraph(
        "Verifies horizontal/vertical inter-PE wave-front propagation with 2×2 matrices:<br/>"
        "A = [[1, 2], [3, 4]], B = [[5, 6], [7, 8]] &rarr; <b>Expected C = [[19, 22], [43, 50]]</b>",
        body_style
    ))

    # 2x2 Table
    t2_data = [
        [Paragraph("<b>Cycle</b>", body_style), Paragraph("<b>a_in[0], a_in[1]</b>", body_style), Paragraph("<b>b_in[0], b_in[1]</b>", body_style), Paragraph("<b>PE[0][0]</b>", body_style), Paragraph("<b>PE[0][1]</b>", body_style), Paragraph("<b>PE[1][0]</b>", body_style), Paragraph("<b>PE[1][1]</b>", body_style)],
        [Paragraph("0", body_style), Paragraph("1, 0", body_style), Paragraph("5, 0", body_style), Paragraph("5 (1&times;5)", body_style), Paragraph("0 (idle)", body_style), Paragraph("0 (idle)", body_style), Paragraph("0 (idle)", body_style)],
        [Paragraph("1", body_style), Paragraph("2, 3", body_style), Paragraph("7, 6", body_style), Paragraph("<b>19</b> (done)", body_style), Paragraph("6 (1&times;6)", body_style), Paragraph("15 (3&times;5)", body_style), Paragraph("0 (idle)", body_style)],
        [Paragraph("2", body_style), Paragraph("0, 4", body_style), Paragraph("0, 8", body_style), Paragraph("19", body_style), Paragraph("<b>22</b> (done)", body_style), Paragraph("<b>43</b> (done)", body_style), Paragraph("18 (3&times;6)", body_style)],
        [Paragraph("3", body_style), Paragraph("0, 0", body_style), Paragraph("0, 0", body_style), Paragraph("19", body_style), Paragraph("22", body_style), Paragraph("43", body_style), Paragraph("<b>50</b> (done)", body_style)],
    ]
    t2_table = Table(t2_data, colWidths=[40, 80, 80, 75, 75, 75, 75])
    t2_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1a5276')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
    ]))
    story.append(t2_table)
    story.append(Spacer(1, 6))

    if os.path.exists(os.path.join(assets_dir, "systolic_2x2_waveform.png")):
        story.append(Image(os.path.join(assets_dir, "systolic_2x2_waveform.png"), width=6.8*inch, height=3.6*inch))
        story.append(Spacer(1, 8))

    # STEP 3
    story.append(Paragraph("Step 3: Skew Buffer Staggering Test (<code>tb_step3_skew_buffer.sv</code>)", h2_style))
    story.append(Paragraph(
        "Demonstrates automatic conversion from a flat matrix to a staggered temporal stream. "
        "Row 0 has 0-cycle delay, Row 1 has 1-cycle delay, Row <i>r</i> has <i>r</i>-cycle delay.",
        body_style
    ))
    if os.path.exists(os.path.join(assets_dir, "skew_buffer_diagram.png")):
        story.append(Image(os.path.join(assets_dir, "skew_buffer_diagram.png"), width=6.8*inch, height=2.4*inch))
        story.append(Spacer(1, 8))

    # STEP 4
    story.append(Paragraph("Step 4: Full System 4×4 Verification (<code>tb_step4_systolic_4x4.sv</code>)", h2_style))
    story.append(Paragraph(
        "Autonomous full-system verification. Top-level accepts 4×4 matrices A and B, pulses <code>start</code>, "
        "waits for FSM <code>done</code> flag, and compares all 16 output elements against an automated golden software model.",
        body_style
    ))

    res_table_data = [
        [Paragraph("<b>Test Suite</b>", body_style), Paragraph("<b>Input Stimulus</b>", body_style), Paragraph("<b>Golden Model Equation</b>", body_style), Paragraph("<b>Hardware Result</b>", body_style), Paragraph("<b>Status</b>", body_style)],
        [Paragraph("<b>Test 1</b>", body_style), Paragraph("A = [1..16], B = Identity (I)", body_style), Paragraph("C = A &times; I = A", body_style), Paragraph("C equals Matrix A (16/16 matches)", body_style), Paragraph("<font color='green'><b>PASS</b></font>", body_style)],
        [Paragraph("<b>Test 2</b>", body_style), Paragraph("A = [1..16], B = 2 &times; Identity (2I)", body_style), Paragraph("C = A &times; 2I = 2A", body_style), Paragraph("Every element exactly doubled", body_style), Paragraph("<font color='green'><b>PASS</b></font>", body_style)],
        [Paragraph("<b>Test 3</b>", body_style), Paragraph("Arbitrary dense 4×4 matrices", body_style), Paragraph("C = A &times; B (Dot Products)", body_style), Paragraph("All 16 dot-product values exact", body_style), Paragraph("<font color='green'><b>PASS</b></font>", body_style)]
    ]
    res_table = Table(res_table_data, colWidths=[55, 120, 115, 150, 60])
    res_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f2942')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]))
    story.append(res_table)
    story.append(Spacer(1, 10))

    # -------------------------------------------------------------------------
    # CHAPTER 3: VIVADO TCL SCRIPTING & AUTOMATION
    # -------------------------------------------------------------------------
    story.append(Paragraph("3. Vivado Tcl Scripting & CLI Automation Guide", h1_style))
    story.append(Paragraph(
        "Tcl (Tool Command Language) provides 100% deterministic, scriptable automation in Vivado without clicking through GUI menus. "
        "You can run simulation, synthesis, and bitstream generation directly from the Vivado Tcl Console or terminal.",
        body_style
    ))

    story.append(Paragraph("3.1 Complete Vivado Tcl Script (<code>run_sim.tcl</code>)", h2_style))
    tcl_code = (
        "# Set paths\n"
        "set root_dir [file normalize \"../..\"]\n"
        "create_project -in_memory -part xc7a35tcpg236-1\n\n"
        "# Add Design Sources & Set SystemVerilog\n"
        "add_files -fileset sources_1 [glob \"$root_dir/simulation/src/*.sv\"]\n"
        "set_property file_type SystemVerilog [get_files -of_objects [get_filesets sources_1]]\n\n"
        "# Add Testbenches\n"
        "add_files -fileset sim_1 [glob \"$root_dir/simulation/sim/*.sv\"]\n"
        "set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1]]\n\n"
        "# Set Top Module for Simulation & Launch\n"
        "set_property top tb_step4_systolic_4x4 [get_filesets sim_1]\n"
        "launch_simulation -mode behavioral\n"
        "run all"
    )
    story.append(Paragraph(tcl_code.replace("\n", "<br/>").replace(" ", "&nbsp;"), code_style))

    story.append(Paragraph("3.2 1-Click Fast CLI Simulation Commands (Batch Mode)", h2_style))
    cli_code = (
        ":: 1. Compile SystemVerilog RTL and Testbench\n"
        "xvlog.bat -sv -relax src\\processing_element.sv src\\systolic_array.sv src\\skew_buffer.sv src\\controller.sv src\\systolic_top.sv sim\\tb_step4_systolic_4x4.sv\n\n"
        ":: 2. Elaborate Design with 1ns/1ps Timescale\n"
        "xelab.bat -timescale 1ns/1ps -debug typical tb_step4_systolic_4x4 -s sim_step4\n\n"
        ":: 3. Run Simulation Snapshot\n"
        "xsim.bat sim_step4 -R"
    )
    story.append(Paragraph(cli_code.replace("\n", "<br/>").replace(" ", "&nbsp;"), code_style))
    story.append(Spacer(1, 8))

    # -------------------------------------------------------------------------
    # CHAPTER 4: BASYS 3 FPGA DEPLOYMENT
    # -------------------------------------------------------------------------
    story.append(Paragraph("4. Hardware Deployment on Digilent Basys 3 FPGA", h1_style))
    story.append(Paragraph(
        "To run on real hardware (Xilinx Artix-7 <b>XC7A35T-1CPG236C</b>), we wrap the systolic array with on-chip ROMs, "
        "a dynamic 4-digit 7-segment display multiplexer, and switch/button interfaces.",
        body_style
    ))

    b3_table_data = [
        [Paragraph("<b>Board Pin / Port</b>", body_style), Paragraph("<b>Signal</b>", body_style), Paragraph("<b>Physical Function / Hardware Mapping</b>", body_style)],
        [Paragraph("<b>W5</b>", body_style), Paragraph("<code>clk</code>", body_style), Paragraph("100 MHz onboard master oscillator.", body_style)],
        [Paragraph("<b>U18 (btnC)</b>", body_style), Paragraph("<code>rst</code>", body_style), Paragraph("Center push button: Synchronous array reset.", body_style)],
        [Paragraph("<b>T18 (btnU)</b>", body_style), Paragraph("<code>start</code>", body_style), Paragraph("Top push button: Pulses start to launch matrix computation.", body_style)],
        [Paragraph("<b>V17, V16 (sw[1:0])</b>", body_style), Paragraph("<code>sw[1:0]</code>", body_style), Paragraph("Preset selector: 00=Identity, 01=Scalar 2I, 10=General Dense Matrix.", body_style)],
        [Paragraph("<b>W15, V15 (sw[5:4])</b>", body_style), Paragraph("<code>sel_row</code>", body_style), Paragraph("Select output row (0 to 3) to display.", body_style)],
        [Paragraph("<b>W17, W16 (sw[3:2])</b>", body_style), Paragraph("<code>sel_col</code>", body_style), Paragraph("Select output column (0 to 3) to display.", body_style)],
        [Paragraph("<b>U16 (led[0])</b>", body_style), Paragraph("<code>done</code>", body_style), Paragraph("Lights up when matrix computation is finished and results are valid.", body_style)],
        [Paragraph("<b>W7..V7, U2..W4</b>", body_style), Paragraph("<code>seg, an</code>", body_style), Paragraph("Displays the 16-bit result element C[row][col] in Hexadecimal.", body_style)]
    ]
    b3_table = Table(b3_table_data, colWidths=[110, 90, 300])
    b3_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f2942')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
    ]))
    story.append(b3_table)
    story.append(Spacer(1, 8))

    # -------------------------------------------------------------------------
    # CHAPTER 5: TROUBLESHOOTING GUIDE
    # -------------------------------------------------------------------------
    story.append(Paragraph("5. Vivado Troubleshooting & Root-Cause Analysis", h1_style))
    trouble_data = [
        [Paragraph("<b>Error Code / Message</b>", body_style), Paragraph("<b>Root Cause</b>", body_style), Paragraph("<b>Permanent Resolution Applied</b>", body_style)],
        [Paragraph("<code>[VRFC 10-3642] port must not be declared to be an array</code>", body_style), Paragraph("Unpacked 1D/2D array ports were used in <code>.v</code> files (Verilog-2001 mode).", body_style), Paragraph("Upgraded all source files to <code>.sv</code> and enabled SystemVerilog mode in Vivado.", body_style)],
        [Paragraph("<code>[XSIM 43-4099] Module doesn't have a timescale</code>", body_style), Paragraph("Timescale was defined in testbench but missing in design source submodules.", body_style), Paragraph("Added <code>`timescale 1ns / 1ps</code> to every single module and testbench header.", body_style)],
        [Paragraph("<code>[DRC NSTD-1] / [DRC UCIO-1] Unconstrained Ports</code>", body_style), Paragraph("Attempted bitstream generation on raw top module with 256 physical I/O pins.", body_style), Paragraph("Created <code>basys3_demo_top.sv</code> with on-chip ROM, switch selectors, and 7-segment display.", body_style)]
    ]
    trouble_table = Table(trouble_data, colWidths=[140, 160, 200])
    trouble_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#b91c1c')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]))
    story.append(trouble_table)

    # Build PDF
    doc.build(story, canvasmaker=NumberedCanvas)
    
    # Also copy to local simulation dir
    import shutil
    shutil.copy(pdf_output_path, pdf_output_path_local)
    print(f"PDF successfully generated at: {pdf_output_path}")
    print(f"PDF copy created at: {pdf_output_path_local}")

if __name__ == '__main__':
    build_pdf()
