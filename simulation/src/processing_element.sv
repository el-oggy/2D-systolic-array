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
