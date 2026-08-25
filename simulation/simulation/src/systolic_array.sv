`timescale 1ns / 1ps
// ============================================================================
// Module: systolic_array.sv
// Description: N x N 2D Systolic Array Mesh
//
// Interconnect Architecture:
//   - Array of N x N Processing Elements (PEs)
//   - Horizontal bus: a_in[row] connects to column 0, forwarded rightwards
//   - Vertical bus:   b_in[col] connects to row 0, forwarded downwards
//   - Result:         Each PE[i][j] holds output C[i][j]
// ============================================================================

module systolic_array #(
    parameter N          = 4,
    parameter DATA_WIDTH = 8
)(
    input  wire                               clk,
    input  wire                               rst,
    input  wire                               en,

    // Left edge inputs (one per row)
    input  wire signed [DATA_WIDTH-1:0]       a_in [0:N-1],

    // Top edge inputs (one per column)
    input  wire signed [DATA_WIDTH-1:0]       b_in [0:N-1],

    // Matrix result: result[row][col]
    output wire signed [2*DATA_WIDTH-1:0]     result [0:N-1][0:N-1]
);

    // Internal interconnect routing wires
    // a_wire[row][col]: enters PE[row][col] from left
    // b_wire[row][col]: enters PE[row][col] from top
    wire signed [DATA_WIDTH-1:0] a_wire [0:N-1][0:N];   // N rows, N+1 columns
    wire signed [DATA_WIDTH-1:0] b_wire [0:N][0:N-1];   // N+1 rows, N columns

    // Connect external boundary inputs
    genvar idx;
    generate
        for (idx = 0; idx < N; idx = idx + 1) begin : gen_boundary_inputs
            assign a_wire[idx][0] = a_in[idx];
            assign b_wire[0][idx] = b_in[idx];
        end
    endgenerate

    // Instantiate 2D mesh of PEs
    genvar r, c;
    generate
        for (r = 0; r < N; r = r + 1) begin : gen_rows
            for (c = 0; c < N; c = c + 1) begin : gen_cols
                processing_element #(
                    .DATA_WIDTH(DATA_WIDTH)
                ) pe_inst (
                    .clk   (clk),
                    .rst   (rst),
                    .en    (en),
                    .a_in  (a_wire[r][c]),
                    .a_out (a_wire[r][c+1]),
                    .b_in  (b_wire[r][c]),
                    .b_out (b_wire[r+1][c]),
                    .acc   (result[r][c])
                );
            end
        end
    endgenerate

endmodule
