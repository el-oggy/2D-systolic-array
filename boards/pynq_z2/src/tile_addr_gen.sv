`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: tile_addr_gen
// Description: Computes sub-tile coordinates, boundary limits, and zero-padding
//              flags for arbitrary matrix dimensions (M, K, N).
// ============================================================================

module tile_addr_gen #(
    parameter int ARRAY_ROWS = 16,
    parameter int ARRAY_COLS = 16,
    parameter int TILE_K     = 16
)(
    input  wire        clk,
    input  wire        rst_n,

    // Matrix logical dimensions
    input  wire [15:0] m_dim,
    input  wire [15:0] k_dim,
    input  wire [15:0] n_dim,

    // Current tile loop indices
    input  wire [15:0] mt_idx,
    input  wire [15:0] nt_idx,
    input  wire [15:0] kt_idx,

    // Current step within tile (0 to TILE_K-1)
    input  wire [7:0]  k_step,

    // Effective active sub-tile bounds
    output logic [7:0] actual_m,
    output logic [7:0] actual_k,
    output logic [7:0] actual_n,

    // Valid / zero-padding masks
    output logic       pad_a [0:ARRAY_ROWS-1],
    output logic       pad_b [0:ARRAY_COLS-1],
    output logic       is_last_k_tile,
    output logic       is_last_tile
);

    localparam int ROW_SHIFT = (ARRAY_ROWS == 16) ? 4 : $clog2(ARRAY_ROWS);
    localparam int COL_SHIFT = (ARRAY_COLS == 16) ? 4 : $clog2(ARRAY_COLS);
    localparam int K_SHIFT   = (TILE_K == 16)     ? 4 : $clog2(TILE_K);

    // Calculate tile counts via bit shifts for power-of-2 mesh dimensions
    wire [15:0] num_m_tiles = (m_dim + ARRAY_ROWS - 1) >> ROW_SHIFT;
    wire [15:0] num_n_tiles = (n_dim + ARRAY_COLS - 1) >> COL_SHIFT;
    wire [15:0] num_k_tiles = (k_dim + TILE_K - 1)     >> K_SHIFT;

    // Base coordinate offsets (16-bit matches m_dim/n_dim/k_dim)
    wire [15:0] m_start = 16'(mt_idx << ROW_SHIFT);
    wire [15:0] n_start = 16'(nt_idx << COL_SHIFT);
    wire [15:0] k_start = 16'(kt_idx << K_SHIFT);

    wire [15:0] rem_m = (m_dim > m_start) ? (m_dim - m_start) : 16'd0;
    wire [15:0] rem_n = (n_dim > n_start) ? (n_dim - n_start) : 16'd0;
    wire [15:0] rem_k = (k_dim > k_start) ? (k_dim - k_start) : 16'd0;

    wire [7:0] rem_m_byte = rem_m[7:0];
    wire [7:0] rem_n_byte = rem_n[7:0];
    wire [7:0] rem_k_byte = rem_k[7:0];

    // Compute actual valid elements in this tile
    always_comb begin
        actual_m = (rem_m >= ARRAY_ROWS) ? ARRAY_ROWS[7:0] : rem_m_byte;
        actual_n = (rem_n >= ARRAY_COLS) ? ARRAY_COLS[7:0] : rem_n_byte;
        actual_k = (rem_k >= TILE_K)     ? TILE_K[7:0]     : rem_k_byte;

        // End conditions
        is_last_k_tile = (kt_idx == num_k_tiles - 1);
        is_last_tile   = (mt_idx == num_m_tiles - 1) &&
                         (nt_idx == num_n_tiles - 1) &&
                         is_last_k_tile;
    end

    // Zero-padding flags: pad when index exceeds boundary or k_step exceeds actual_k
    genvar pa_r, pb_c;
    generate
        for (pa_r = 0; pa_r < ARRAY_ROWS; pa_r = pa_r + 1) begin : gen_pad_a
            assign pad_a[pa_r] = (pa_r >= actual_m) || (k_step >= actual_k);
        end
        for (pb_c = 0; pb_c < ARRAY_COLS; pb_c = pb_c + 1) begin : gen_pad_b
            assign pad_b[pb_c] = (pb_c >= actual_n) || (k_step >= actual_k);
        end
    endgenerate

endmodule

`default_nettype wire
