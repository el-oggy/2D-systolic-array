// ============================================================
// systolic_2x2_tb.v — Testbench for 2×2 Systolic Array
// ============================================================
// We multiply:
//   A = |1  2|    B = |5  6|
//       |3  4|        |7  8|
//
//   C = A × B = |1*5+2*7  1*6+2*8| = |19  22|
//               |3*5+4*7  3*6+4*8|   |43  50|
//
// This testbench MANUALLY feeds skewed inputs so you can
// see exactly how data flows through the array.
//
// Skewed A (fed from left):       Skewed B (fed from top):
//   Cycle:  0   1   2             Cycle:  0   1   2
//   Row 0:  1   2   0             Col 0:  5   7   0
//   Row 1:  0   3   4             Col 1:  0   6   8
//
// Timeline of what each PE computes:
//   Cycle 0: PE00: acc=0+1*5=5    PE01: idle    PE10: idle    PE11: idle
//   Cycle 1: PE00: acc=5+2*7=19✓  PE01: 1*6=6  PE10: 3*5=15  PE11: idle
//   Cycle 2: PE00: done           PE01: 6+2*8=22✓  PE10: 15+4*7=43✓  PE11: 3*6=18
//   Cycle 3:                                                          PE11: 18+4*8=50✓
// ============================================================

`timescale 1ns / 1ps

module systolic_2x2_tb;

    // ---- Parameters ----
    parameter N = 2;
    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10;

    // Total compute cycles needed = 2*N - 1 = 3 for 2×2
    parameter COMPUTE_CYCLES = 2*N - 1;

    // ---- Signals ----
    reg  clk, rst, en;
    reg  signed [DATA_WIDTH-1:0] a_in [0:N-1];
    reg  signed [DATA_WIDTH-1:0] b_in [0:N-1];
    wire signed [2*DATA_WIDTH-1:0] result [0:N-1][0:N-1];

    // ---- Instantiate the 2×2 Systolic Array ----
    systolic_array #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .a_in(a_in),
        .b_in(b_in),
        .result(result)
    );

    // ---- Clock Generator ----
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Dump waveforms for GTKWave ----
    initial begin
        $dumpfile("systolic_2x2_tb.vcd");
        $dumpvars(0, systolic_2x2_tb);
    end

    // ---- Expected Results ----
    // C = A × B = |19  22|
    //             |43  50|

    // ---- Test Stimulus ----
    integer cycle;
    initial begin
        $display("================================================");
        $display("  2×2 Systolic Array Testbench");
        $display("  A = |1 2|  B = |5 6|  C = |19 22|");
        $display("      |3 4|      |7 8|      |43 50|");
        $display("================================================\n");

        // ---- RESET ----
        rst = 1;
        en  = 0;
        a_in[0] = 0; a_in[1] = 0;
        b_in[0] = 0; b_in[1] = 0;

        @(posedge clk);
        @(posedge clk);
        rst = 0;
        en  = 1;

        $display("Feeding SKEWED inputs into the array:\n");
        $display("Cycle | a_in[0] a_in[1] | b_in[0] b_in[1] | PE00.acc PE01.acc PE10.acc PE11.acc");
        $display("------|-----------------|-----------------|------------------------------------");

        // ============================================
        // CYCLE 0: Feed first values
        // ============================================
        // A row 0 starts: a[0][0]=1, A row 1 delayed: 0
        // B col 0 starts: b[0][0]=5, B col 1 delayed: 0
        a_in[0] = 8'sd1;  a_in[1] = 8'sd0;
        b_in[0] = 8'sd5;  b_in[1] = 8'sd0;
        @(posedge clk);
        #1;
        $display("  0   |   %2d      %2d    |   %2d      %2d    |  %4d    %4d    %4d    %4d",
                 a_in[0], a_in[1], b_in[0], b_in[1],
                 result[0][0], result[0][1], result[1][0], result[1][1]);

        // ============================================
        // CYCLE 1: Second values
        // ============================================
        // A row 0: a[0][1]=2, A row 1 starts: a[1][0]=3
        // B col 0: b[1][0]=7, B col 1 starts: b[0][1]=6
        a_in[0] = 8'sd2;  a_in[1] = 8'sd3;
        b_in[0] = 8'sd7;  b_in[1] = 8'sd6;
        @(posedge clk);
        #1;
        $display("  1   |   %2d      %2d    |   %2d      %2d    |  %4d    %4d    %4d    %4d",
                 a_in[0], a_in[1], b_in[0], b_in[1],
                 result[0][0], result[0][1], result[1][0], result[1][1]);

        // ============================================
        // CYCLE 2: Last values
        // ============================================
        // A row 0: done (0), A row 1: a[1][1]=4
        // B col 0: done (0), B col 1: b[1][1]=8
        a_in[0] = 8'sd0;  a_in[1] = 8'sd4;
        b_in[0] = 8'sd0;  b_in[1] = 8'sd8;
        @(posedge clk);
        #1;
        $display("  2   |   %2d      %2d    |   %2d      %2d    |  %4d    %4d    %4d    %4d",
                 a_in[0], a_in[1], b_in[0], b_in[1],
                 result[0][0], result[0][1], result[1][0], result[1][1]);

        // ============================================
        // Wait 1 more cycle for last PE to finish
        // ============================================
        a_in[0] = 0; a_in[1] = 0;
        b_in[0] = 0; b_in[1] = 0;
        @(posedge clk);
        #1;

        // ---- Disable and check results ----
        en = 0;

        $display("\n================================================");
        $display("  RESULTS:");
        $display("  C[0][0] = %0d (expected 19)", result[0][0]);
        $display("  C[0][1] = %0d (expected 22)", result[0][1]);
        $display("  C[1][0] = %0d (expected 43)", result[1][0]);
        $display("  C[1][1] = %0d (expected 50)", result[1][1]);
        $display("================================================");

        // ---- Verify ----
        if (result[0][0] == 19 && result[0][1] == 22 &&
            result[1][0] == 43 && result[1][1] == 50) begin
            $display("  >>> ALL PASS! Matrix multiplication correct! <<<");
        end else begin
            $display("  >>> FAIL! Check the waveform in GTKWave <<<");
        end
        $display("================================================");

        // Wait a bit then finish
        @(posedge clk);
        @(posedge clk);
        $finish;
    end

endmodule
