`timescale 1ns / 1ps
// ============================================================================
// Testbench: tb_step2_systolic_2x2.sv (STEP 2: 2x2 Systolic Array Grid Test)
// ============================================================================
// Purpose:
//   Tests the 2D spatial interconnect and wave-front propagation on a 2x2 grid.
//   Manually provides cycle-by-cycle skewed inputs to observe the internal flow:
//
// Matrices:
//   A = [1 2]      B = [5 6]      Expected C = A x B = [19 22]
//       [3 4]          [7 8]                           [43 50]
//
// Skew Pattern:
//   Row 0: a[0][0]=1, a[0][1]=2, 0        Col 0: b[0][0]=5, b[1][0]=7, 0
//   Row 1: 0,         a[1][0]=3, a[1][1]=4 Col 1: 0,         b[0][1]=6, b[1][1]=8
// ============================================================================

module tb_step2_systolic_2x2;

    parameter N          = 2;
    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10;

    logic                          clk;
    logic                          rst;
    logic                          en;
    logic signed [DATA_WIDTH-1:0]   a_in [0:N-1];
    logic signed [DATA_WIDTH-1:0]   b_in [0:N-1];
    wire  signed [2*DATA_WIDTH-1:0] result [0:N-1][0:N-1];

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

    // Clock Generator
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Waveform Dump
    initial begin
        $dumpfile("tb_step2_systolic_2x2.vcd");
        $dumpvars(0, tb_step2_systolic_2x2);
    end

    initial begin
        $display("\n=======================================================");
        $display("  [STEP 2 SIMULATION] 2x2 Systolic Array Grid Test");
        $display("=======================================================\n");

        // Reset
        rst     = 1'b1;
        en      = 1'b0;
        a_in[0] = '0; a_in[1] = '0;
        b_in[0] = '0; b_in[1] = '0;

        repeat(2) @(posedge clk);
        rst     = 1'b0;
        en      = 1'b1;

        $display("Cycle | a_in[0] a_in[1] | b_in[0] b_in[1] | C[0][0] C[0][1] C[1][0] C[1][1]");
        $display("------|-----------------|-----------------|--------------------------------");

        // Cycle 0
        a_in[0] = 8'sd1;  a_in[1] = 8'sd0;
        b_in[0] = 8'sd5;  b_in[1] = 8'sd0;
        @(posedge clk);
        #1;
        $display("  0   |   %3d     %3d   |   %3d     %3d   |  %4d    %4d    %4d    %4d",
                 a_in[0], a_in[1], b_in[0], b_in[1],
                 result[0][0], result[0][1], result[1][0], result[1][1]);

        // Cycle 1
        a_in[0] = 8'sd2;  a_in[1] = 8'sd3;
        b_in[0] = 8'sd7;  b_in[1] = 8'sd6;
        @(posedge clk);
        #1;
        $display("  1   |   %3d     %3d   |   %3d     %3d   |  %4d    %4d    %4d    %4d",
                 a_in[0], a_in[1], b_in[0], b_in[1],
                 result[0][0], result[0][1], result[1][0], result[1][1]);

        // Cycle 2
        a_in[0] = 8'sd0;  a_in[1] = 8'sd4;
        b_in[0] = 8'sd0;  b_in[1] = 8'sd8;
        @(posedge clk);
        #1;
        $display("  2   |   %3d     %3d   |   %3d     %3d   |  %4d    %4d    %4d    %4d",
                 a_in[0], a_in[1], b_in[0], b_in[1],
                 result[0][0], result[0][1], result[1][0], result[1][1]);

        // Cycle 3: Pipeline drain
        a_in[0] = 8'sd0;  a_in[1] = 8'sd0;
        b_in[0] = 8'sd0;  b_in[1] = 8'sd0;
        @(posedge clk);
        #1;
        $display("  3   |   %3d     %3d   |   %3d     %3d   |  %4d    %4d    %4d    %4d",
                 a_in[0], a_in[1], b_in[0], b_in[1],
                 result[0][0], result[0][1], result[1][0], result[1][1]);

        en = 1'b0;

        $display("\n-------------------------------------------------------");
        $display("  Expected Matrix C: [19  22]");
        $display("                     [43  50]");
        $display("  Actual Matrix C:   [%2d  %2d]", result[0][0], result[0][1]);
        $display("                     [%2d  %2d]", result[1][0], result[1][1]);

        if (result[0][0] == 19 && result[0][1] == 22 &&
            result[1][0] == 43 && result[1][1] == 50) begin
            $display("  >>> [STEP 2 PASS] 2x2 Systolic Array verified! <<<");
        end else begin
            $display("  >>> [STEP 2 FAIL] Output mismatch! <<<");
        end
        $display("-------------------------------------------------------\n");

        repeat(2) @(posedge clk);
        $finish;
    end

endmodule
