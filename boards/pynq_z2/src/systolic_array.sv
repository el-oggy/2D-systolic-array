`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: systolic_array
// Description: Parameterized 2D Systolic Array Mesh with Active-Region Gating,
//              32-bit Signed Accumulators, and Selectable MAC Implementation.
// ============================================================================

module systolic_array #(
    parameter int ARRAY_ROWS = 16,
    parameter int ARRAY_COLS = 16,
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32,
    parameter     MAC_IMPL   = "DSP",
    parameter int DSP_PE_LIMIT = ARRAY_ROWS * ARRAY_COLS,
    parameter bit MASK_AT_INGRESS = 1'b0,
    parameter bit TRACK_OVERFLOW = 1'b1
)(
    input  wire                               clk,
    input  wire                               rst_n,
    input  wire                               clr_acc,
    input  wire                               array_en,
    input  wire                               active_mask [0:ARRAY_ROWS-1][0:ARRAY_COLS-1],

    // West edge inputs (Matrix A rows)
    input  wire signed [DATA_WIDTH-1:0]       a_in        [0:ARRAY_ROWS-1],

    // North edge inputs (Matrix B columns)
    input  wire signed [DATA_WIDTH-1:0]       b_in        [0:ARRAY_COLS-1],

    // 2D Matrix Result (signed 32-bit INT32)
    output wire signed [ACC_WIDTH-1:0]        c_out       [0:ARRAY_ROWS-1][0:ARRAY_COLS-1],

    // Global sticky overflow indicator
    output wire                               overflow
);

    // Horizontal routing wires: a_wire[r][c] enters PE[r][c] from left
    wire signed [DATA_WIDTH-1:0] a_wire [0:ARRAY_ROWS-1][0:ARRAY_COLS];

    // Vertical routing wires:   b_wire[r][c] enters PE[r][c] from top
    wire signed [DATA_WIDTH-1:0] b_wire [0:ARRAY_ROWS][0:ARRAY_COLS-1];

    // Per-PE overflow signals
    wire pe_overflow [0:ARRAY_ROWS-1][0:ARRAY_COLS-1];

    // Connect boundary inputs
    genvar idx;
    generate
        for (idx = 0; idx < ARRAY_ROWS; idx = idx + 1) begin : gen_west_inputs
            if (MASK_AT_INGRESS)
                // The integrated skew buffers already zero-pad rows outside
                // actual_m, so no replicated active-mask decode is needed.
                assign a_wire[idx][0] = a_in[idx];
            else
                assign a_wire[idx][0] = a_in[idx];
        end
        for (idx = 0; idx < ARRAY_COLS; idx = idx + 1) begin : gen_north_inputs
            if (MASK_AT_INGRESS)
                // The integrated skew buffers already zero-pad columns
                // outside actual_n.
                assign b_wire[0][idx] = b_in[idx];
            else
                assign b_wire[0][idx] = b_in[idx];
        end
    endgenerate

    // Instantiate 2D mesh of processing elements
    genvar r, c;
    generate
        for (r = 0; r < ARRAY_ROWS; r = r + 1) begin : gen_row
            for (c = 0; c < ARRAY_COLS; c = c + 1) begin : gen_col
                // In integrated mode, zero padding at the skew-buffer output
                // guarantees inactive cells receive zero products. Keep all
                // cells clocked to preserve forwarding and clear behavior.
                wire pe_en = MASK_AT_INGRESS ? array_en : (array_en & active_mask[r][c]);

                localparam PE_MAC_IMPL = (MAC_IMPL == "HYBRID")
                    ? ((r * ARRAY_COLS + c) < DSP_PE_LIMIT ? "DSP" : "LUT")
                    : MAC_IMPL;

                pe_mac #(
                    .DATA_WIDTH (DATA_WIDTH),
                    .ACC_WIDTH  (ACC_WIDTH),
                    .MAC_IMPL   (PE_MAC_IMPL),
                    .FREE_RUN_FORWARD(MASK_AT_INGRESS),
                    .TRACK_OVERFLOW(TRACK_OVERFLOW)
                ) u_pe (
                    .clk        (clk),
                    .rst_n      (rst_n),
                    .clr_acc    (clr_acc),
                    .en         (pe_en),
                    .a_i        (a_wire[r][c]),
                    .b_i        (b_wire[r][c]),
                    .a_o        (a_wire[r][c+1]),
                    .b_o        (b_wire[r+1][c]),
                    .acc_o      (c_out[r][c]),
                    .overflow_o (pe_overflow[r][c])
                );
            end
        end
    endgenerate

    // Hardware sticky overflow reduction across active elements
    wire [ARRAY_ROWS*ARRAY_COLS-1:0] overflow_flat;
    genvar ov_r, ov_c;
    generate
        for (ov_r = 0; ov_r < ARRAY_ROWS; ov_r = ov_r + 1) begin : gen_ov_r
            for (ov_c = 0; ov_c < ARRAY_COLS; ov_c = ov_c + 1) begin : gen_ov_c
                if (MASK_AT_INGRESS)
                    assign overflow_flat[ov_r * ARRAY_COLS + ov_c] = pe_overflow[ov_r][ov_c];
                else
                    assign overflow_flat[ov_r * ARRAY_COLS + ov_c] = active_mask[ov_r][ov_c] & pe_overflow[ov_r][ov_c];
            end
        end
    endgenerate

    assign overflow = |overflow_flat;

endmodule

`default_nettype wire
