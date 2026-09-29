`timescale 1ns / 1ps
// ============================================================================
// Testbench: tb_matrix_top.sv
// Description: Top-Level SystemVerilog OOP Testbench for 16x16 Systolic Array
//              Automated Randomized Stress Testing with Scoreboard.
// ============================================================================

`include "matrix_if.sv"
`include "MatrixTransaction.sv"
`include "MatrixGenerator.sv"
`include "MatrixDriver.sv"
`include "MatrixMonitor.sv"
`include "MatrixScoreboard.sv"
`include "MatrixEnvironment.sv"

module tb_matrix_top;

    localparam int N          = 16;
    localparam int DATA_WIDTH = 8;
    localparam int CLK_PERIOD = 10; // 100 MHz clock (10 ns)
    localparam int TEST_COUNT = 30; // 30 randomized matrix multiplications (7,680 element checks!)

    // Clock Generation
    logic clk;
    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Interface Instantiation
    matrix_if intf (
        .clk(clk)
    );

    // DUT (Device Under Test) Instantiation
    systolic_top #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk     (intf.clk),
        .rst     (intf.rst),
        .start   (intf.start),
        .matrix_a(intf.matrix_a),
        .matrix_b(intf.matrix_b),
        .result  (intf.result),
        .done    (intf.done)
    );

    // OOP Verification Environment Handle
    MatrixEnvironment env;

    // Main Test Sequence
    initial begin
        $display("\n================================================================================");
        $display("  LAUNCHING OOP SYSTEMVERILOG VERIFICATION: 16x16 2D SYSTOLIC ARRAY ACCELERATOR");
        $display("  - Architecture     : 16x16 Mesh (256 Multiply-Accumulate Processing Elements)");
        $display("  - Precision        : INT8 Inputs, INT16 Outputs");
        $display("  - Test Count       : %0d Iterations (%0d total MAC operations)", 
                 TEST_COUNT, TEST_COUNT * N * N * N);
        $display("================================================================================\n");

        // Instantiate Environment
        env = new(intf, TEST_COUNT);

        // Run Verification Suite
        env.run();

        // Finish Simulation
        $display("[TB] Testbench completed successfully at sim time %0t ps.", $time);
        $finish;
    end

    // Simulation Timeout Watchdog
    initial begin
        #5000000; // 5 ms timeout guard
        $fatal(1, "[TIMEOUT] Simulation exceeded maximum time guard! Simulation killed.");
    end

endmodule
