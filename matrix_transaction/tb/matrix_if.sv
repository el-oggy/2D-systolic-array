`timescale 1ns / 1ps
// ============================================================================
// Interface: matrix_if.sv
// Description: SystemVerilog Verification Interface for 16x16 2D Systolic Array
// ============================================================================

interface matrix_if (
    input logic clk
);

    localparam int N          = 16;
    localparam int DATA_WIDTH = 8;

    // Pin-level signals
    logic                          rst;
    logic                          start;
    logic signed [DATA_WIDTH-1:0]   matrix_a [0:N-1][0:N-1];
    logic signed [DATA_WIDTH-1:0]   matrix_b [0:N-1][0:N-1];
    logic signed [2*DATA_WIDTH-1:0] result   [0:N-1][0:N-1];
    logic                          done;

    // Driver Clocking Block (Synchronous Drive)
    clocking cb_drv @(posedge clk);
        default input #1ns output #1ns;
        output rst;
        output start;
        output matrix_a;
        output matrix_b;
        input  done;
        input  result;
    endclocking

    // Monitor Clocking Block (Synchronous Sample)
    clocking cb_mon @(posedge clk);
        default input #1ns;
        input rst;
        input start;
        input matrix_a;
        input matrix_b;
        input result;
        input done;
    endclocking

    // Modports
    modport DRV (clocking cb_drv, input clk);
    modport MON (clocking cb_mon, input clk);
    modport DUT (
        input  clk,
        input  rst,
        input  start,
        input  matrix_a,
        input  matrix_b,
        output result,
        output done
    );

endinterface : matrix_if
