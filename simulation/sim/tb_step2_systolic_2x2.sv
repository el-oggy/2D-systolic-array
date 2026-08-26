`timescale 1ns / 1ps
// ============================================================================
// Testbench: tb_step2_systolic_2x2.sv (STEP 2: 2x2 Systolic Array Grid Test)
// ============================================================================
// Matrices to multiply:
//   Matrix A = [ 2  1 ]      Matrix B = [ 1  2 ]
//              [ 0  3 ]                 [ 3  0 ]
//
// Expected Mathematical Result:
//   C[0][0] = (2*1) + (1*3) = 2 + 3 = 5
//   C[0][1] = (2*2) + (1*0) = 4 + 0 = 4
//   C[1][0] = (0*1) + (3*3) = 0 + 9 = 9
//   C[1][1] = (0*2) + (3*0) = 0 + 0 = 0
//
//   Matrix C = [ 5  4 ]
//              [ 9  0 ]
//
// Staggered Data Feed Pattern:
//   Cycle 0: Row 0 gets 2, Col 0 gets 1  (Row 1 & Col 1 waiting)
//   Cycle 1: Row 0 gets 1, Col 0 gets 3, Row 1 gets 0, Col 1 gets 2
//   Cycle 2: Row 1 gets 3, Col 1 gets 0
//   Cycle 3: Pipeline drain
// ============================================================================

module tb_step2_systolic_2x2;

    parameter N          = 2;
    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10;

    // Clock & Control
    logic                          clk;
    logic                          rst;
    logic                          en;

    // Array Inputs & Outputs (Arrays)
    logic signed [DATA_WIDTH-1:0]   a_in [0:N-1];
    logic signed [DATA_WIDTH-1:0]   b_in [0:N-1];
    wire  signed [2*DATA_WIDTH-1:0] result [0:N-1][0:N-1];

    // ========================================================================
    // CLEAR, READABLE SIGNAL ALIASES FOR VIVADO WAVEFORM VIEWER
    // ========================================================================
    wire signed [DATA_WIDTH-1:0]   row0_from_left   = a_in[0];
    wire signed [DATA_WIDTH-1:0]   row1_from_left   = a_in[1];
    wire signed [DATA_WIDTH-1:0]   col0_from_top    = b_in[0];
    wire signed [DATA_WIDTH-1:0]   col1_from_top    = b_in[1];

    wire signed [2*DATA_WIDTH-1:0] PE00_top_left    = result[0][0]; // Target: 5
    wire signed [2*DATA_WIDTH-1:0] PE01_top_right   = result[0][1]; // Target: 4
    wire signed [2*DATA_WIDTH-1:0] PE10_bottom_left = result[1][0]; // Target: 9
    wire signed [2*DATA_WIDTH-1:0] PE11_bottom_right= result[1][1]; // Target: 0

    // Instantiate 2x2 Systolic Array
    systolic_array #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk   (clk),
        .rst   (rst),
        .en    (en),
        .a_in  (a_in),
        .b_in  (b_in),
        .result(result)
    );

    // Clock Generator (10ns period -> 100MHz)
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Waveform Dump for GTKWave
    initial begin
        $dumpfile("tb_step2_systolic_2x2.vcd");
        $dumpvars(0, tb_step2_systolic_2x2);
    end

    initial begin
        $display("\n=======================================================================");
        $display("  [STEP 2 SIMULATION] 2x2 Systolic Array Grid Test");
        $display("  Multiplying Matrix A x Matrix B:");
        $display("    Matrix A = | 2  1 |     Matrix B = | 1  2 |");
        $display("               | 0  3 |                | 3  0 |");
        $display("    Expected C = | 5  4 |");
        $display("                 | 9  0 |");
        $display("=======================================================================\n");

        // Step 1: Reset
        rst     = 1'b1;
        en      = 1'b0;
        a_in[0] = '0; a_in[1] = '0;
        b_in[0] = '0; b_in[1] = '0;

        repeat(2) @(posedge clk);
        rst     = 1'b0;
        en      = 1'b1;

        $display("Cycle | row0_in row1_in | col0_in col1_in | PE00(5) PE01(4) PE10(9) PE11(0) | Status");
        $display("------|-----------------|-----------------|---------------------------------|-------");

        // --------------------------------------------------------------------
        // Cycle 0: First wavefront begins
        // Row 0 feeds 2, Col 0 feeds 1
        // --------------------------------------------------------------------
        a_in[0] = 8'sd2;  a_in[1] = 8'sd0;
        b_in[0] = 8'sd1;  b_in[1] = 8'sd0;
        @(posedge clk);
        #1;
        $display("  0   |   %3d     %3d   |   %3d     %3d   |  %4d    %4d    %4d    %4d  | PE00 computes 2*1=2",
                 row0_from_left, row1_from_left, col0_from_top, col1_from_top,
                 PE00_top_left, PE01_top_right, PE10_bottom_left, PE11_bottom_right);

        // --------------------------------------------------------------------
        // Cycle 1: Second wavefront
        // Row 0 feeds 1, Col 0 feeds 3, Row 1 feeds 0, Col 1 feeds 2
        // --------------------------------------------------------------------
        a_in[0] = 8'sd1;  a_in[1] = 8'sd0;
        b_in[0] = 8'sd3;  b_in[1] = 8'sd2;
        @(posedge clk);
        #1;
        $display("  1   |   %3d     %3d   |   %3d     %3d   |  %4d    %4d    %4d    %4d  | PE00 hits 5 [DONE!]",
                 row0_from_left, row1_from_left, col0_from_top, col1_from_top,
                 PE00_top_left, PE01_top_right, PE10_bottom_left, PE11_bottom_right);

        // --------------------------------------------------------------------
        // Cycle 2: Third wavefront
        // Row 1 feeds 3, Col 1 feeds 0
        // --------------------------------------------------------------------
        a_in[0] = 8'sd0;  a_in[1] = 8'sd3;
        b_in[0] = 8'sd0;  b_in[1] = 8'sd0;
        @(posedge clk);
        #1;
        $display("  2   |   %3d     %3d   |   %3d     %3d   |  %4d    %4d    %4d    %4d  | PE01 hits 4, PE10 hits 9 [DONE!]",
                 row0_from_left, row1_from_left, col0_from_top, col1_from_top,
                 PE00_top_left, PE01_top_right, PE10_bottom_left, PE11_bottom_right);

        // --------------------------------------------------------------------
        // Cycle 3: Final drain
        // --------------------------------------------------------------------
        a_in[0] = 8'sd0;  a_in[1] = 8'sd0;
        b_in[0] = 8'sd0;  b_in[1] = 8'sd0;
        @(posedge clk);
        #1;
        $display("  3   |   %3d     %3d   |   %3d     %3d   |  %4d    %4d    %4d    %4d  | PE11 hits 0 [DONE!]",
                 row0_from_left, row1_from_left, col0_from_top, col1_from_top,
                 PE00_top_left, PE01_top_right, PE10_bottom_left, PE11_bottom_right);

        en = 1'b0;

        $display("\n=======================================================================");
        $display("  FINAL RESULTS CHECK:");
        $display("  Expected Matrix C: [ 5   4 ]");
        $display("                     [ 9   0 ]");
        $display("  Actual Matrix C:   [ %1d   %1d ]", PE00_top_left, PE01_top_right);
        $display("                     [ %1d   %1d ]", PE10_bottom_left, PE11_bottom_right);

        if (PE00_top_left == 5 && PE01_top_right == 4 &&
            PE10_bottom_left == 9 && PE11_bottom_right == 0) begin
            $display("  >>> [STEP 2 PASS] 2x2 Systolic Array verified with 100%% accuracy! <<<");
        end else begin
            $display("  >>> [STEP 2 FAIL] Output mismatch! <<<");
        end
        $display("=======================================================================\n");

        repeat(2) @(posedge clk);
        $finish;
    end

endmodule
