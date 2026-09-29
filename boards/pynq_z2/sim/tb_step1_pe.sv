`timescale 1ns / 1ps
// ============================================================================
// Testbench: tb_step1_pe.sv (STEP 1: Single Processing Element Verification)
// ============================================================================
// Purpose:
//   Validates the atomic building block of the systolic array:
//   1. Reset behavior (acc = 0, a_out = 0, b_out = 0)
//   2. Multiply-Accumulate computation: acc = acc + (a_in * b_in)
//   3. Systolic forwarding: a_out <= a_in (1-cycle delay), b_out <= b_in (1-cycle delay)
//   4. Enable signal behavior (registers hold when en = 0)
//
// Calculation:
//   Simulates PE[0][0] computing dot product: [1, 2, 3] . [7, 10, 13]
//   Cycle 0: 1 * 7  = 7
//   Cycle 1: 2 * 10 = 20  -> acc = 7 + 20 = 27
//   Cycle 2: 3 * 13 = 39  -> acc = 27 + 39 = 66
// ============================================================================

module tb_step1_pe;

    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10; // 100 MHz clock

    // DUT Signals
    logic                          clk;
    logic                          rst;
    logic                          en;
    logic signed [DATA_WIDTH-1:0]   a_in;
    logic signed [DATA_WIDTH-1:0]   b_in;
    wire  signed [DATA_WIDTH-1:0]   a_out;
    wire  signed [DATA_WIDTH-1:0]   b_out;
    wire  signed [2*DATA_WIDTH-1:0] acc;

    // Instantiate Unit Under Test (UUT)
    processing_element #(
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk  (clk),
        .rst  (rst),
        .en   (en),
        .a_in (a_in),
        .b_in (b_in),
        .a_out(a_out),
        .b_out(b_out),
        .acc  (acc)
    );

    // Clock Generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Waveform Dump
    initial begin
        $dumpfile("tb_step1_pe.vcd");
        $dumpvars(0, tb_step1_pe);
    end

    // Test Sequence
    initial begin
        $display("\n=======================================================");
        $display("  [STEP 1 SIMULATION] Processing Element (PE) Unit Test");
        $display("=======================================================\n");

        // Phase 1: Reset
        rst  = 1'b1;
        en   = 1'b0;
        a_in = '0;
        b_in = '0;

        repeat(2) @(posedge clk);
        rst  = 1'b0;
        en   = 1'b1;

        $display("Time(ns) | a_in | b_in | a_in*b_in | acc | a_out | b_out | Status");
        $display("---------|------|------|-----------|-----|-------|-------|-------");

        // Cycle 0: a=1, b=7
        a_in = 8'sd1;
        b_in = 8'sd7;
        @(posedge clk);
        #1;
        $display("%8t |  %3d |  %3d |    %4d   | %3d |  %3d  |  %3d  | %s", 
                 $time, a_in, b_in, a_in*b_in, acc, a_out, b_out, (acc == 7) ? "OK" : "ERROR");

        // Cycle 1: a=2, b=10
        a_in = 8'sd2;
        b_in = 8'sd10;
        @(posedge clk);
        #1;
        $display("%8t |  %3d |  %3d |    %4d   | %3d |  %3d  |  %3d  | %s", 
                 $time, a_in, b_in, a_in*b_in, acc, a_out, b_out, (acc == 27 && a_out == 1 && b_out == 7) ? "OK" : "ERROR");

        // Cycle 2: a=3, b=13
        a_in = 8'sd3;
        b_in = 8'sd13;
        @(posedge clk);
        #1;
        $display("%8t |  %3d |  %3d |    %4d   | %3d |  %3d  |  %3d  | %s", 
                 $time, a_in, b_in, a_in*b_in, acc, a_out, b_out, (acc == 66 && a_out == 2 && b_out == 10) ? "OK" : "ERROR");

        // Phase 3: Hold State Check (en = 0)
        en   = 1'b0;
        a_in = 8'sd0;
        b_in = 8'sd0;
        @(posedge clk);
        #1;
        $display("%8t |  %3d |  %3d |    %4d   | %3d |  %3d  |  %3d  | %s (Hold Mode)", 
                 $time, a_in, b_in, a_in*b_in, acc, a_out, b_out, (acc == 66 && a_out == 3 && b_out == 13) ? "OK" : "ERROR");

        $display("\n-------------------------------------------------------");
        if (acc == 66 && a_out == 3 && b_out == 13) begin
            $display("  >>> [STEP 1 PASS] Single PE functionality verified! <<<");
        end else begin
            $display("  >>> [STEP 1 FAIL] Unexpected values encountered! <<<");
        end
        $display("-------------------------------------------------------\n");

        repeat(2) @(posedge clk);
        $finish;
    end

endmodule
