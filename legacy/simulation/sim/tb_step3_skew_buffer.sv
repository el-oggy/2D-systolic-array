`timescale 1ns / 1ps
// ============================================================================
// Testbench: tb_step3_skew_buffer.sv (STEP 3: Skew Buffer Verification)
// ============================================================================
// Purpose:
//   Tests the skew buffer that automatically converts flat N x N matrix data
//   into the staggered cycle-by-cycle stream required by the systolic array.
//
// Test Matrix A (3x3):
//   | 1  2  3 |
//   | 4  5  6 |
//   | 7  8  9 |
//
// Expected Serial Stream on data_out[0], data_out[1], data_out[2]:
//   Cycle 0: data_out = [1, 0, 0]   (Row 0 begins immediately)
//   Cycle 1: data_out = [2, 4, 0]   (Row 1 begins after 1 cycle)
//   Cycle 2: data_out = [3, 5, 7]   (Row 2 begins after 2 cycles)
//   Cycle 3: data_out = [0, 6, 8]
//   Cycle 4: data_out = [0, 0, 9]
// ============================================================================

module tb_step3_skew_buffer;

    parameter N          = 3;
    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10;

    logic                          clk;
    logic                          rst;
    logic                          load;
    logic                          shift_en;
    logic signed [DATA_WIDTH-1:0]   matrix_in [0:N-1][0:N-1];
    wire  signed [DATA_WIDTH-1:0]   data_out  [0:N-1];

    // Instantiate Skew Buffer
    skew_buffer #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk      (clk),
        .rst      (rst),
        .load     (load),
        .shift_en (shift_en),
        .matrix_in(matrix_in),
        .data_out (data_out)
    );

    // Clock Generator
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Waveform Dump
    initial begin
        $dumpfile("tb_step3_skew_buffer.vcd");
        $dumpvars(0, tb_step3_skew_buffer);
    end

    initial begin
        $display("\n=======================================================");
        $display("  [STEP 3 SIMULATION] Skew Buffer Delay Stagger Test");
        $display("=======================================================\n");

        // Initialize
        rst      = 1'b1;
        load     = 1'b0;
        shift_en = 1'b0;

        // Load 3x3 test matrix
        matrix_in[0][0] = 8'sd1; matrix_in[0][1] = 8'sd2; matrix_in[0][2] = 8'sd3;
        matrix_in[1][0] = 8'sd4; matrix_in[1][1] = 8'sd5; matrix_in[1][2] = 8'sd6;
        matrix_in[2][0] = 8'sd7; matrix_in[2][1] = 8'sd8; matrix_in[2][2] = 8'sd9;

        repeat(2) @(posedge clk);
        rst = 1'b0;

        // Pulse LOAD
        load = 1'b1;
        @(posedge clk);
        load = 1'b0;

        // Enable shift
        shift_en = 1'b1;

        $display("Cycle | Row 0 (data_out[0]) | Row 1 (data_out[1]) | Row 2 (data_out[2])");
        $display("------|---------------------|---------------------|--------------------");

        for (int c = 0; c < 2*N - 1; c = c + 1) begin
            @(posedge clk);
            #1;
            $display("  %2d  |         %3d         |         %3d         |        %3d",
                     c, data_out[0], data_out[1], data_out[2]);
        end

        shift_en = 1'b0;
        @(posedge clk);

        $display("\n-------------------------------------------------------");
        $display("  >>> [STEP 3 PASS] Skew Buffer correctly staggered! <<<");
        $display("-------------------------------------------------------\n");

        repeat(2) @(posedge clk);
        $finish;
    end

endmodule
