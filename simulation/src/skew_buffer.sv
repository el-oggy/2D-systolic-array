`timescale 1ns / 1ps
// ============================================================================
// Module: skew_buffer.sv
// Description: Input Skewing Buffer for 2D Systolic Array
//
// Functionality:
//   - Takes an N x N matrix loaded in parallel (flat)
//   - Introduces the required systolic pipeline delay:
//       Row 0: 0 cycles delay
//       Row 1: 1 cycle delay
//       ...
//       Row r: r cycles delay
//   - Total feeding depth is 2*N - 1 clock cycles.
//   - Shifts out 1 value per row on each cycle when shift_en is asserted.
// ============================================================================

module skew_buffer #(
    parameter N          = 4,
    parameter DATA_WIDTH = 8
)(
    input  wire                               clk,
    input  wire                               rst,
    input  wire                               load,
    input  wire                               shift_en,

    // Parallel Matrix Input: matrix_in[row][col]
    input  wire signed [DATA_WIDTH-1:0]       matrix_in [0:N-1][0:N-1],

    // Staggered Serial Output: one value per row per clock
    output reg  signed [DATA_WIDTH-1:0]       data_out [0:N-1]
);

    localparam DEPTH = 2*N - 1;

    // Shift register array: N rows x DEPTH columns
    reg signed [DATA_WIDTH-1:0] shift_reg [0:N-1][0:DEPTH-1];

    integer r, c;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (r = 0; r < N; r = r + 1) begin
                data_out[r] <= '0;
                for (c = 0; c < DEPTH; c = c + 1) begin
                    shift_reg[r][c] <= '0;
                end
            end
        end else if (load) begin
            for (r = 0; r < N; r = r + 1) begin
                data_out[r] <= '0;
                for (c = 0; c < DEPTH; c = c + 1) begin
                    if (c >= r && c < r + N) begin
                        shift_reg[r][c] <= matrix_in[r][c - r];
                    end else begin
                        shift_reg[r][c] <= '0;
                    end
                end
            end
        end else if (shift_en) begin
            for (r = 0; r < N; r = r + 1) begin
                data_out[r] <= shift_reg[r][0];
                for (c = 0; c < DEPTH - 1; c = c + 1) begin
                    shift_reg[r][c] <= shift_reg[r][c + 1];
                end
                shift_reg[r][DEPTH-1] <= '0;
            end
        end
    end

endmodule
