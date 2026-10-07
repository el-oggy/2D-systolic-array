`timescale 1ns / 1ps
`default_nettype none

// Supplies the row/column start offsets required by the systolic mesh.
// Only TILE_K data words are stored per row/column. A shared compute-cycle
// counter supplies the row/column skew delay, avoiding a TILE_K+ROWS-1 (or
// TILE_K+COLS-1) register chain for every stream.
module skew_buffers #(
    parameter int ARRAY_ROWS = 16,
    parameter int ARRAY_COLS = 16,
    parameter int TILE_K     = 16,
    parameter int DATA_WIDTH = 8
)(
    input  wire                               clk,
    input  wire                               rst_n,
    input  wire                               load_en,
    input  wire                               shift_en,
    input  wire [7:0]                         actual_m,
    input  wire [7:0]                         actual_k,
    input  wire [7:0]                         actual_n,
    input  wire signed [DATA_WIDTH-1:0]       a_tile_in [0:ARRAY_ROWS-1][0:TILE_K-1],
    input  wire signed [DATA_WIDTH-1:0]       b_tile_in [0:TILE_K-1][0:ARRAY_COLS-1],
    output logic signed [DATA_WIDTH-1:0]      a_skewed_o [0:ARRAY_ROWS-1],
    output logic signed [DATA_WIDTH-1:0]      b_skewed_o [0:ARRAY_COLS-1]
);

    localparam int COUNT_WIDTH = $clog2(ARRAY_ROWS + ARRAY_COLS + TILE_K + 1);
    logic [COUNT_WIDTH-1:0] compute_cycle;
    (* shreg_extract = "yes" *) logic signed [DATA_WIDTH-1:0] a_shift [0:ARRAY_ROWS-1][0:TILE_K-1];
    (* shreg_extract = "yes" *) logic signed [DATA_WIDTH-1:0] b_shift [0:ARRAY_COLS-1][0:TILE_K-1];

    integer r, k_a;
    integer c, k_b;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            compute_cycle <= '0;
            for (r = 0; r < ARRAY_ROWS; r = r + 1) begin
                a_skewed_o[r] <= '0;
                for (k_a = 0; k_a < TILE_K; k_a = k_a + 1)
                    a_shift[r][k_a] <= '0;
            end
            for (c = 0; c < ARRAY_COLS; c = c + 1) begin
                b_skewed_o[c] <= '0;
                for (k_b = 0; k_b < TILE_K; k_b = k_b + 1)
                    b_shift[c][k_b] <= '0;
            end
        end else if (load_en) begin
            compute_cycle <= '0;
            for (r = 0; r < ARRAY_ROWS; r = r + 1) begin
                a_skewed_o[r] <= '0;
                for (k_a = 0; k_a < TILE_K; k_a = k_a + 1)
                    // Mask the narrow stream output, rather than every bit
                    // of the parallel tile load. Invalid stored words never
                    // enter the mesh, avoiding thousands of replicated muxes.
                    a_shift[r][k_a] <= a_tile_in[r][k_a];
            end
            for (c = 0; c < ARRAY_COLS; c = c + 1) begin
                b_skewed_o[c] <= '0;
                for (k_b = 0; k_b < TILE_K; k_b = k_b + 1)
                    b_shift[c][k_b] <= b_tile_in[k_b][c];
            end
        end else if (shift_en) begin
            compute_cycle <= compute_cycle + 1'b1;
            for (r = 0; r < ARRAY_ROWS; r = r + 1) begin
                if (r < actual_m && compute_cycle >= r &&
                    compute_cycle < r + actual_k) begin
                    a_skewed_o[r] <= a_shift[r][0];
                    for (k_a = 0; k_a < TILE_K - 1; k_a = k_a + 1)
                        a_shift[r][k_a] <= a_shift[r][k_a + 1];
                    a_shift[r][TILE_K - 1] <= '0;
                end else begin
                    a_skewed_o[r] <= '0;
                end
            end
            for (c = 0; c < ARRAY_COLS; c = c + 1) begin
                if (c < actual_n && compute_cycle >= c &&
                    compute_cycle < c + actual_k) begin
                    b_skewed_o[c] <= b_shift[c][0];
                    for (k_b = 0; k_b < TILE_K - 1; k_b = k_b + 1)
                        b_shift[c][k_b] <= b_shift[c][k_b + 1];
                    b_shift[c][TILE_K - 1] <= '0;
                end else begin
                    b_skewed_o[c] <= '0;
                end
            end
        end else begin
            for (r = 0; r < ARRAY_ROWS; r = r + 1)
                a_skewed_o[r] <= '0;
            for (c = 0; c < ARRAY_COLS; c = c + 1)
                b_skewed_o[c] <= '0;
        end
    end

endmodule

`default_nettype wire
