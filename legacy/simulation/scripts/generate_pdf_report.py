import os
import sys
import shutil
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image, KeepTogether, HRFlowable, PageBreak
)
from reportlab.pdfgen import canvas

# Dynamically resolve directories relative to this script
script_dir = os.path.dirname(os.path.abspath(__file__))
simulation_dir = os.path.abspath(os.path.join(script_dir, ".."))
workspace_dir = os.path.abspath(os.path.join(simulation_dir, ".."))
assets_dir = os.path.join(simulation_dir, "assets")

pdf_output_path = os.path.join(workspace_dir, "2D_Systolic_Array_Vivado_Complete_Guide.pdf")
pdf_output_path_local = os.path.join(simulation_dir, "2D_Systolic_Array_Vivado_Complete_Guide.pdf")

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
            self.drawString(54, letter[1] - 36, "2D Systolic Array Hardware Accelerator — Vivado Simulation & Hardware Guide (Scaled 16x16)")
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
        fontSize=20,
        leading=24,
        textColor=colors.HexColor('#0f2942'),
        spaceAfter=6
    )
    
    subtitle_style = ParagraphStyle(
        'DocSubTitle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=11,
        leading=15,
        textColor=colors.HexColor('#2b6cb0'),
        spaceAfter=12
    )

    h1_style = ParagraphStyle(
        'Heading1_Custom',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=13,
        leading=17,
        textColor=colors.HexColor('#0f2942'),
        spaceBefore=12,
        spaceAfter=6,
        keepWithNext=True
    )

    h2_style = ParagraphStyle(
        'Heading2_Custom',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=10.5,
        leading=14,
        textColor=colors.HexColor('#1a5276'),
        spaceBefore=8,
        spaceAfter=5,
        keepWithNext=True
    )

    body_style = ParagraphStyle(
        'Body_Custom',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=9,
        leading=13,
        textColor=colors.HexColor('#222222'),
        spaceAfter=5
    )

    code_style = ParagraphStyle(
        'Code_Custom',
        parent=styles['Normal'],
        fontName='Courier',
        fontSize=7.5,
        leading=10.5,
        textColor=colors.HexColor('#1e293b'),
        backColor=colors.HexColor('#f1f5f9'),
        borderPadding=5,
        spaceAfter=6
    )

    callout_style = ParagraphStyle(
        'Callout',
        parent=styles['Normal'],
        fontName='Helvetica-Oblique',
        fontSize=8.5,
        leading=12,
        textColor=colors.HexColor('#0f2942'),
        backColor=colors.HexColor('#e6f0fa'),
        borderPadding=6,
        spaceAfter=6
    )

    story = []

    # -------------------------------------------------------------------------
    # COVER / HEADER TITLE
    # -------------------------------------------------------------------------
    story.append(Paragraph("2D Systolic Array Matrix Accelerator", title_style))
    story.append(Paragraph("Comprehensive Vivado Simulation & FPGA Hardware Implementation Guide (Scaled to 16×16 Grid)", subtitle_style))
    story.append(HRFlowable(width="100%", thickness=1.5, color=colors.HexColor('#0f2942'), spaceAfter=10))

    # Meta Table
    meta_data = [
        [Paragraph("<b>Target Flow:</b> AMD Vivado 2025.1 / 2024.x", body_style),
         Paragraph("<b>FPGA Board:</b> Digilent Basys 3 (Artix-7 XC7A35T)", body_style)],
        [Paragraph("<b>Precision:</b> INT8 Signed Inputs, INT16 Outputs", body_style),
         Paragraph("<b>Architecture:</b> 16×16 2D Mesh (256 Processing Elements)", body_style)],
        [Paragraph("<b>Clock Frequency:</b> 100 MHz (10 ns period)", body_style),
         Paragraph("<b>Total Latency:</b> 48 Cycles (480 ns) | 17.06 GOPS", body_style)]
    ]
    meta_table = Table(meta_data, colWidths=[250, 254])
    meta_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), colors.HexColor('#f8fafc')),
        ('BOX', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
        ('INNERGRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#e2e8f0')),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]))
    story.append(meta_table)
    story.append(Spacer(1, 10))

    # -------------------------------------------------------------------------
    # CHAPTER 1: ARCHITECTURE OVERVIEW
    # -------------------------------------------------------------------------
    story.append(Paragraph("1. Architectural Overview & Mathematical Formulation", h1_style))
    story.append(Paragraph(
        "The 2D Systolic Array is a rhythmic, spatial compute architecture designed for high-throughput, energy-efficient "
        "Dense Matrix Multiplication (GEMM). Data streams flow continuously through a 2-dimensional grid of Processing Elements (PEs), "
        "reusing operands horizontally and vertically to minimize memory bandwidth bottlenecks.",
        body_style
    ))

    math_text = (
        "For matrix multiplication <b>C = A × B</b> where A and B are 16×16 matrices:<br/>"
        "&nbsp;&nbsp;&nbsp;&nbsp;<b>C[i][j] = &sum;<sub>k=0</sub><sup>15</sup> ( A[i][k] &times; B[k][j] )</b><br/>"
        "Each PE[i][j] accumulates products over time while forwarding A elements to its right neighbor and B elements to its bottom neighbor."
    )
    story.append(Paragraph(math_text, callout_style))

    story.append(Paragraph("1.1 Core Hardware Components", h2_style))
    comp_table_data = [
        [Paragraph("<b>Component</b>", body_style), Paragraph("<b>File</b>", body_style), Paragraph("<b>Function & Key Architectural Role</b>", body_style)],
        [Paragraph("<b>Global Package</b>", body_style), Paragraph("<code>systolic_pkg.sv</code>", body_style), Paragraph("Centralized parameters, derived timing constants (N=16, 256 PEs), and FSM state enums.", body_style)],
        [Paragraph("<b>Processing Element (PE)</b>", body_style), Paragraph("<code>processing_element.sv</code>", body_style), Paragraph("Multiply-Accumulate (MAC) core: <code>acc <= acc + (a_in * b_in)</code> with 1-cycle horizontal (<code>a_out</code>) and vertical (<code>b_out</code>) forwarding registers.", body_style)],
        [Paragraph("<b>Systolic Array Mesh</b>", body_style), Paragraph("<code>systolic_array.sv</code>", body_style), Paragraph("2D grid of 16×16 PEs (256 units) with boundary edge wiring and inter-PE interconnect buses.", body_style)],
        [Paragraph("<b>Skew Buffer</b>", body_style), Paragraph("<code>skew_buffer.sv</code>", body_style), Paragraph("Parallel-to-serial delay-line buffer (31 stages). Staggers row <i>i</i> by <i>i</i> cycles so wavefronts align perfectly.", body_style)],
        [Paragraph("<b>FSM Controller</b>", body_style), Paragraph("<code>controller.sv</code>", body_style), Paragraph("State machine sequencing <code>IDLE &rarr; LOAD &rarr; COMPUTE &rarr; DONE</code> over <b>3N - 1 = 47</b> clock cycles.", body_style)],
        [Paragraph("<b>Top System</b>", body_style), Paragraph("<code>systolic_top.sv</code>", body_style), Paragraph("Integrates FSM, Skew Buffer A (rows), Skew Buffer B (transposed cols), and the 16×16 PE array.", body_style)]
    ]
    comp_table = Table(comp_table_data, colWidths=[100, 110, 294])
    comp_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f2942')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
    ]))
    story.append(comp_table)
    story.append(Spacer(1, 8))

    # Architecture Image
    arch_img_path = os.path.join(assets_dir, "systolic_16x16_architecture.png")
    if os.path.exists(arch_img_path):
        story.append(Paragraph("<b>Figure 1: 16×16 2D Systolic Array Hardware Architecture (256 PEs)</b>", h2_style))
        story.append(Image(arch_img_path, width=6.8*inch, height=3.6*inch))
        story.append(Spacer(1, 8))

    # FSM Image
    fsm_img_path = os.path.join(assets_dir, "fsm_diagram.png")
    if os.path.exists(fsm_img_path):
        story.append(Paragraph("<b>Figure 2: FSM Controller State Transitions & Control Outputs</b>", h2_style))
        story.append(Image(fsm_img_path, width=6.8*inch, height=3.6*inch))
        story.append(Spacer(1, 8))

    # -------------------------------------------------------------------------
    # CHAPTER 2: STEP-BY-STEP SIMULATION & VERIFICATION TIERS
    # -------------------------------------------------------------------------
    story.append(Paragraph("2. Progressive Multi-Tier Simulation Suite", h1_style))
    story.append(Paragraph(
        "Verification is conducted in six progressive tiers to guarantee correctness at the atomic PE level, "
        "interconnect mesh, buffering, and at scaled 4×4, 8×8, and 16×16 grid dimensions.",
        body_style
    ))

    # Simulation summary table
    sim_summary_data = [
        [Paragraph("<b>Step / Testbench</b>", body_style), Paragraph("<b>Grid Size</b>", body_style), Paragraph("<b>PE Count</b>", body_style), Paragraph("<b>Compute Cycles</b>", body_style), Paragraph("<b>Total Latency</b>", body_style), Paragraph("<b>Vivado Status</b>", body_style)],
        [Paragraph("<b>Step 1:</b> <code>tb_step1_pe.sv</code>", body_style), Paragraph("1×1", body_style), Paragraph("1 PE", body_style), Paragraph("3 cycles", body_style), Paragraph("4 cycles", body_style), Paragraph("<font color='green'><b>PASS (100%)</b></font>", body_style)],
        [Paragraph("<b>Step 2:</b> <code>tb_step2_systolic_2x2.sv</code>", body_style), Paragraph("2×2", body_style), Paragraph("4 PEs", body_style), Paragraph("5 cycles", body_style), Paragraph("6 cycles", body_style), Paragraph("<font color='green'><b>PASS (100%)</b></font>", body_style)],
        [Paragraph("<b>Step 3:</b> <code>tb_step3_skew_buffer.sv</code>", body_style), Paragraph("Buffer", body_style), Paragraph("—", body_style), Paragraph("7 stages", body_style), Paragraph("8 cycles", body_style), Paragraph("<font color='green'><b>PASS (100%)</b></font>", body_style)],
        [Paragraph("<b>Step 4:</b> <code>tb_step4_systolic_4x4.sv</code>", body_style), Paragraph("4×4", body_style), Paragraph("16 PEs", body_style), Paragraph("11 cycles", body_style), Paragraph("12 cycles", body_style), Paragraph("<font color='green'><b>PASS (100%)</b></font>", body_style)],
        [Paragraph("<b>Step 5:</b> <code>tb_step5_systolic_8x8.sv</code>", body_style), Paragraph("8×8", body_style), Paragraph("64 PEs", body_style), Paragraph("23 cycles", body_style), Paragraph("24 cycles", body_style), Paragraph("<font color='green'><b>PASS (100%)</b></font>", body_style)],
        [Paragraph("<b>Step 6:</b> <code>tb_step6_systolic_16x16.sv</code>", body_style), Paragraph("16×16", body_style), Paragraph("256 PEs", body_style), Paragraph("47 cycles", body_style), Paragraph("48 cycles", body_style), Paragraph("<font color='green'><b>PASS (100%)</b></font>", body_style)],
    ]
    sim_table = Table(sim_summary_data, colWidths=[120, 60, 64, 80, 80, 100])
    sim_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f2942')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
    ]))
    story.append(sim_table)
    story.append(Spacer(1, 10))

    # STEP 6 RESULTS TABLE
    story.append(Paragraph("2.1 Scaled 16×16 Accelerator Test Results (<code>tb_step6_systolic_16x16.sv</code>)", h2_style))
    res16_data = [
        [Paragraph("<b>Test Suite</b>", body_style), Paragraph("<b>Input Matrices</b>", body_style), Paragraph("<b>Expected Golden Equation</b>", body_style), Paragraph("<b>Simulation Results</b>", body_style), Paragraph("<b>Verification Status</b>", body_style)],
        [Paragraph("<b>Test 1</b>", body_style), Paragraph("A = [-63..64], B = Identity (I<sub>16</sub>)", body_style), Paragraph("C = A &times; I<sub>16</sub> = A", body_style), Paragraph("All 256/256 elements equal Matrix A", body_style), Paragraph("<font color='green'><b>PASS (256/256)</b></font>", body_style)],
        [Paragraph("<b>Test 2</b>", body_style), Paragraph("A = [-63..64], B = 2 &times; I<sub>16</sub>", body_style), Paragraph("C = A &times; 2I<sub>16</sub> = 2A", body_style), Paragraph("All 256/256 elements doubled", body_style), Paragraph("<font color='green'><b>PASS (256/256)</b></font>", body_style)],
        [Paragraph("<b>Test 3</b>", body_style), Paragraph("Arbitrary dense signed INT8 matrices", body_style), Paragraph("C[i][j] = &sum; A[i][k] &times; B[k][j]", body_style), Paragraph("Full dot product match vs golden model", body_style), Paragraph("<font color='green'><b>PASS (256/256)</b></font>", body_style)]
    ]
    res16_table = Table(res16_data, colWidths=[55, 120, 115, 134, 80])
    res16_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f2942')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cbd5e1')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f8fafc')]),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
    ]))
    story.append(res16_table)
    story.append(Spacer(1, 10))

    # -------------------------------------------------------------------------
    # CHAPTER 3: HARDWARE DEPLOYMENT ON BASYS 3 FPGA
    # -------------------------------------------------------------------------
    story.append(Paragraph("3. Hardware Deployment on Digilent Basys 3 FPGA", h1_style))
    story.append(Paragraph(
        "To run on real hardware (Xilinx Artix-7 <b>XC7A35T-1CPG236C</b>), we encapsulate the 16×16 systolic array inside "
        "<code>basys3_demo_16x16_top.sv</code> with on-chip ROM matrices, switch-based 16-row / 16-col selector, and a 4-digit 7-segment display.",
        body_style
    ))

    b3_table_data = [
        [Paragraph("<b>Board Pin / Port</b>", body_style), Paragraph("<b>Signal</b>", body_style), Paragraph("<b>Physical Function / Hardware Mapping</b>", body_style)],
        [Paragraph("<b>W5</b>", body_style), Paragraph("<code>clk</code>", body_style), Paragraph("100 MHz onboard master oscillator.", body_style)],
        [Paragraph("<b>U18 (btnC)</b>", body_style), Paragraph("<code>rst</code>", body_style), Paragraph("Center push button: Synchronous array reset.", body_style)],
        [Paragraph("<b>T18 (btnU)</b>", body_style), Paragraph("<code>start</code>", body_style), Paragraph("Top push button: Pulses start to launch matrix computation.", body_style)],
        [Paragraph("<b>sw[3:0]</b>", body_style), Paragraph("<code>sel_col</code>", body_style), Paragraph("Select output column index (0 to 15, 4 bits) to display.", body_style)],
        [Paragraph("<b>sw[7:4]</b>", body_style), Paragraph("<code>sel_row</code>", body_style), Paragraph("Select output row index (0 to 15, 4 bits) to display.", body_style)],
        [Paragraph("<b>sw[9:8]</b>", body_style), Paragraph("<code>sw[9:8]</code>", body_style), Paragraph("Preset selector: 00=Identity, 01=Scalar 2I, 10=Dense Signed GEMM.", body_style)],
        [Paragraph("<b>U16 (led[0])</b>", body_style), Paragraph("<code>done</code>", body_style), Paragraph("Lights up when matrix computation is finished and results are valid.", body_style)],
        [Paragraph("<b>E19 (led[1])</b>", body_style), Paragraph("<code>busy</code>", body_style), Paragraph("Lights up during 48-cycle active computation pipeline.", body_style)],
        [Paragraph("<b>W7..V7, U2..W4</b>", body_style), Paragraph("<code>seg, an</code>", body_style), Paragraph("Displays the 16-bit result element C[row][col] in Hexadecimal.", body_style)]
    ]
    b3_table = Table(b3_table_data, colWidths=[100, 80, 324])
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

    # Build PDF
    doc.build(story, canvasmaker=NumberedCanvas)
    
    # Copy to simulation dir as well
    shutil.copy(pdf_output_path, pdf_output_path_local)
    print(f"PDF successfully generated at: {pdf_output_path}")
    print(f"PDF copy created at: {pdf_output_path_local}")

if __name__ == '__main__':
    build_pdf()
