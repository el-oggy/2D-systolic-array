`timescale 1ns / 1ps
// ============================================================================
// Module: systolic_top.sv
// Description: Top-Level Integration of 2D Systolic Array Accelerator
//
// Block Diagram:
//   ┌────────────────────────────────────────────────────────┐
//   │                      systolic_top                      │
//   │                                                        │
//   │  ┌────────────┐                                        │
//   │  │ Controller │──► load_en, shift_en,                  │
//   │  │    FSM     │    array_en, array_rst, done           │
//   │  └────────────┘                                        │
//   │        │                                               │
//   │  ┌─────▼──────┐     ┌──────────────┐                   │
//   │  │ Skew Buf A │────►│              │                   │
//   │  │ (rows)     │     │   N x N      │                   │
//   │  └────────────┘     │   Systolic   │──► result[N-1:0]  │
//   │  ┌────────────┐     │   Array      │                   │
//   │  │ Skew Buf B │────►│              │                   │
//   │  │ (transposed│     └──────────────┘                   │
//   │  │  for cols) │                                        │
//   │  └────────────┘                                        │
//   └────────────────────────────────────────────────────────┘
// ============================================================================

module systolic_top #(
    parameter N          = 4,
    parameter DATA_WIDTH = 8
)(
    input  wire                               clk,
    input  wire                               rst,
    input  wire                               start,

    // Flat Input Matrices (N x N)
    input  wire signed [DATA_WIDTH-1:0]       matrix_a [0:N-1][0:N-1],
    input  wire signed [DATA_WIDTH-1:0]       matrix_b [0:N-1][0:N-1],

    // Output Result Matrix: C = A x B
    output wire signed [2*DATA_WIDTH-1:0]     result [0:N-1][0:N-1],

    // Status Flag
    output wire                               done
);

    // Controller control lines
    wire load_en;
    wire shift_en;
    wire array_en;
    wire array_rst;

    // Staggered skew outputs fed into the array
    wire signed [DATA_WIDTH-1:0] a_skewed [0:N-1];
    wire signed [DATA_WIDTH-1:0] b_skewed [0:N-1];

    // Transposed Matrix B for column-wise skewing
    reg signed [DATA_WIDTH-1:0] matrix_b_transposed [0:N-1][0:N-1];

    integer ti, tj;
    always_comb begin
        for (ti = 0; ti < N; ti = ti + 1) begin
            for (tj = 0; tj < N; tj = tj + 1) begin
                matrix_b_transposed[ti][tj] = matrix_b[tj][ti];
            end
        end
    end

    // FSM Controller Instance
    controller #(
        .N(N)
    ) u_controller (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .load_en  (load_en),
        .shift_en (shift_en),
        .array_en (array_en),
        .array_rst(array_rst),
        .done     (done)
    );

    // Skew Buffer for Matrix A (Row Staggering)
    skew_buffer #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_skew_a (
        .clk       (clk),
        .rst       (rst),
        .load      (load_en),
        .shift_en  (shift_en),
        .matrix_in (matrix_a),
        .data_out  (a_skewed)
    );

    // Skew Buffer for Matrix B (Column Staggering via Transpose)
    skew_buffer #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_skew_b (
        .clk       (clk),
        .rst       (rst),
        .load      (load_en),
        .shift_en  (shift_en),
        .matrix_in (matrix_b_transposed),
        .data_out  (b_skewed)
    );

    // Systolic Array N x N Mesh
    systolic_array #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_systolic_array (
        .clk    (clk),
        .rst    (array_rst),
        .en     (array_en),
        .a_in   (a_skewed),
        .b_in   (b_skewed),
        .result (result)
    );

endmodule
