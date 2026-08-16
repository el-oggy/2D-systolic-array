// ============================================================
// pe_tb.v — Testbench for a SINGLE Processing Element
// ============================================================
// This testbench feeds a_in and b_in values into one PE
// and shows you how it accumulates the result cycle by cycle.
//
// We simulate what PE[0][0] does during a 3x3 matrix multiply:
//   Cycle 0: a_in=1, b_in=7   → acc = 0 + 1*7  = 7
//   Cycle 1: a_in=2, b_in=10  → acc = 7 + 2*10  = 27
//   Cycle 2: a_in=3, b_in=13  → acc = 27 + 3*13 = 66
//
// Expected final acc = 66 = C[0][0] ✓
// ============================================================

`timescale 1ns / 1ps

module pe_tb;

    // ---- Parameters ----
    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10;       // 10ns clock → 100MHz

    // ---- Signals ----
    reg  clk, rst, en;
    reg  signed [DATA_WIDTH-1:0] a_in, b_in;
    wire signed [DATA_WIDTH-1:0] a_out, b_out;
    wire signed [2*DATA_WIDTH-1:0] acc;

    // ---- Instantiate the PE (Unit Under Test) ----
    PE #(.DATA_WIDTH(DATA_WIDTH)) uut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .a_in(a_in),
        .b_in(b_in),
        .a_out(a_out),
        .b_out(b_out),
        .acc(acc)
    );

    // ---- Clock Generator ----
    // Toggles every 5ns → 10ns period → 100MHz
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Dump waveforms for GTKWave ----
    initial begin
        $dumpfile("pe_tb.vcd");     // Output file for GTKWave
        $dumpvars(0, pe_tb);        // Dump ALL signals in this module
    end

    // ---- Test Stimulus ----
    initial begin
        // ==============================
        // PHASE 1: Reset
        // ==============================
        $display("========================================");
        $display("  Single PE Testbench");
        $display("  Simulating PE[0][0] of 3x3 matmul");
        $display("========================================");

        rst  = 1;       // Assert reset
        en   = 0;       // Disable computation
        a_in = 0;
        b_in = 0;

        // Hold reset for 2 clock cycles
        @(posedge clk);
        @(posedge clk);
        rst = 0;        // Release reset
        en  = 1;        // Enable computation

        $display("\nTime  | a_in | b_in | a_in*b_in | acc (expected)");
        $display("------|------|------|-----------|---------------");

        // ==============================
        // PHASE 2: Feed data (3 cycles)
        // ==============================

        // Cycle 0: A[0][0]=1, B[0][0]=7
        a_in = 8'sd1;   // sd = signed decimal
        b_in = 8'sd7;
        @(posedge clk);
        #1; // Small delay so $display reads the updated values
        $display("%4t  |  %2d  |  %2d  |    %4d   | %4d (exp: 7)", 
                 $time, a_in, b_in, a_in*b_in, acc);

        // Cycle 1: A[0][1]=2, B[1][0]=10
        a_in = 8'sd2;
        b_in = 8'sd10;
        @(posedge clk);
        #1;
        $display("%4t  |  %2d  |  %2d  |    %4d   | %4d (exp: 27)",
                 $time, a_in, b_in, a_in*b_in, acc);

        // Cycle 2: A[0][2]=3, B[2][0]=13
        a_in = 8'sd3;
        b_in = 8'sd13;
        @(posedge clk);
        #1;
        $display("%4t  |  %2d  |  %2d  |    %4d   | %4d (exp: 66)",
                 $time, a_in, b_in, a_in*b_in, acc);

        // ==============================
        // PHASE 3: Disable and check
        // ==============================
        en   = 0;        // Stop computing
        a_in = 0;
        b_in = 0;

        // Wait a couple more cycles to see that acc holds its value
        @(posedge clk);
        @(posedge clk);

        $display("\n========================================");
        if (acc == 66) begin
            $display("  ✓ PASS! Final acc = %0d (expected 66)", acc);
            $display("  C[0][0] = 1*7 + 2*10 + 3*13 = 66");
        end else begin
            $display("  ✗ FAIL! Final acc = %0d (expected 66)", acc);
        end
        $display("========================================");

        // Also verify pass-through worked
        $display("\nPass-through check:");
        $display("  Last a_out = %0d (should be 3 = last a_in)", a_out);
        $display("  Last b_out = %0d (should be 13 = last b_in)", b_out);

        $finish;
    end

endmodule
