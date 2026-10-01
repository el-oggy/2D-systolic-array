`timescale 1ns / 1ps
// ============================================================================
// Module: processing_element.sv
// Description: Basic Processing Element (PE) for 2D Systolic Array
// 
// Operation:
//   - Performs Multiply-Accumulate (MAC): acc <= acc + (a_in * b_in)
//   - Passes 'a_in' horizontally (to right neighbor) delayed by 1 cycle
//   - Passes 'b_in' vertically (to bottom neighbor) delayed by 1 cycle
//   - Synchronous reset clears acc, a_out, and b_out
//
// Synthesis & Resource Mapping Notes:
//   - On Xilinx Zynq-7000 (XC7Z020 on PYNQ-Z2), there are 220 physical DSP48E1 slices.
//   - For a 16x16 array, there are 256 PEs (256 multipliers).
//   - Mapping 8x8 signed multipliers into Slice LUTs (~30 LUTs/PE) is the optimal strategy
//     because mapping 256 multipliers to DSPs would exceed the 220 DSP limit.
//   - To explicitly force DSP48E1 mapping for smaller arrays (e.g. 8x8) or larger FPGAs:
//       (* use_dsp = "yes" *) reg signed [2*DATA_WIDTH-1:0] acc;
// ============================================================================

module processing_element #(
    parameter DATA_WIDTH = 8
)(
    input  wire                          clk,
    input  wire                          rst,
    input  wire                          en,

    // Left-to-Right Data Stream (Matrix A)
    input  wire signed [DATA_WIDTH-1:0]   a_in,
    output reg  signed [DATA_WIDTH-1:0]   a_out,

    // Top-to-Bottom Data Stream (Matrix B)
    input  wire signed [DATA_WIDTH-1:0]   b_in,
    output reg  signed [DATA_WIDTH-1:0]   b_out,

    // Accumulated Result Output
    output reg  signed [2*DATA_WIDTH-1:0] acc
);

    always_ff @(posedge clk) begin
        if (rst) begin
            a_out <= '0;
            b_out <= '0;
            acc   <= '0;
        end else if (en) begin
            // MAC unit
            acc   <= acc + (a_in * b_in);
            
            // Systolic forwarding registers
            a_out <= a_in;
            b_out <= b_in;
        end
    end

endmodule
