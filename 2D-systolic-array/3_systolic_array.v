// ============================================================
// systolic_array.v — N×N 2D Systolic Array
// ============================================================
// This module creates an N×N grid of Processing Elements (PEs)
// and wires them together:
//   - a_in flows LEFT → RIGHT (each PE passes to its right neighbor)
//   - b_in flows TOP → BOTTOM (each PE passes to its bottom neighbor)
//   - Each PE accumulates: acc = acc + a_in * b_in
//
// After 2N-1 clock cycles, each PE[i][j] holds C[i][j].
//
// IMPORTANT: This module expects ALREADY SKEWED inputs!
// (The skew buffers handle that — we'll add them later)
// ============================================================

module systolic_array #(
    parameter N = 4,                  // Array dimension (N×N PEs)
    parameter DATA_WIDTH = 8          // Bit width of each input value
)(
    input  wire clk,
    input  wire rst,
    input  wire en,

    // --- Inputs from the LEFT edge (one per row) ---
    // a_in[0] feeds row 0, a_in[1] feeds row 1, etc.
    input  wire signed [DATA_WIDTH-1:0] a_in [0:N-1],

    // --- Inputs from the TOP edge (one per column) ---
    // b_in[0] feeds column 0, b_in[1] feeds column 1, etc.
    input  wire signed [DATA_WIDTH-1:0] b_in [0:N-1],

    // --- Results: one per PE ---
    // result[i][j] = C[i][j] after computation completes
    output wire signed [2*DATA_WIDTH-1:0] result [0:N-1][0:N-1]
);

    // ================================================================
    // INTERNAL WIRES
    // ================================================================
    // These carry data BETWEEN PEs.
    //
    // a_wire[i][j] = the 'a' value entering PE[i][j] from the left
    //   - a_wire[i][0] = a_in[i] (external input, left edge)
    //   - a_wire[i][j] = a_out of PE[i][j-1] (for j > 0)
    //   - a_wire[i][N] = unused (falls off the right edge)
    //
    // b_wire[i][j] = the 'b' value entering PE[i][j] from the top
    //   - b_wire[0][j] = b_in[j] (external input, top edge)
    //   - b_wire[i][j] = b_out of PE[i-1][j] (for i > 0)
    //   - b_wire[N][j] = unused (falls off the bottom edge)

    wire signed [DATA_WIDTH-1:0] a_wire [0:N-1][0:N];   // N rows, N+1 columns
    wire signed [DATA_WIDTH-1:0] b_wire [0:N][0:N-1];   // N+1 rows, N columns

    // ================================================================
    // CONNECT EXTERNAL INPUTS TO THE EDGES
    // ================================================================
    genvar idx;
    generate
        for (idx = 0; idx < N; idx = idx + 1) begin : connect_inputs
            // A values enter from the LEFT edge (column 0 of a_wire)
            assign a_wire[idx][0] = a_in[idx];

            // B values enter from the TOP edge (row 0 of b_wire)
            assign b_wire[0][idx] = b_in[idx];
        end
    endgenerate

    // ================================================================
    // GENERATE THE N×N GRID OF PEs
    // ================================================================
    // This is where the magic happens!
    // We use nested generate loops to create N² PEs and wire them.
    //
    // Each PE[i][j]:
    //   - Reads a_in from a_wire[i][j]     (from left neighbor or edge)
    //   - Reads b_in from b_wire[i][j]     (from top neighbor or edge)
    //   - Writes a_out to a_wire[i][j+1]   (to right neighbor)
    //   - Writes b_out to b_wire[i+1][j]   (to bottom neighbor)
    //   - Stores result in result[i][j]

    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : row
            for (j = 0; j < N; j = j + 1) begin : col
                PE #(
                    .DATA_WIDTH(DATA_WIDTH)
                ) pe_inst (
                    .clk   (clk),
                    .rst   (rst),
                    .en    (en),

                    // A flows left → right
                    .a_in  (a_wire[i][j]),       // from left
                    .a_out (a_wire[i][j+1]),     // to right

                    // B flows top → bottom
                    .b_in  (b_wire[i][j]),       // from top
                    .b_out (b_wire[i+1][j]),     // to bottom

                    // Accumulated result
                    .acc   (result[i][j])
                );
            end
        end
    endgenerate

    // ================================================================
    // That's it! The wiring is automatic thanks to generate.
    //
    // Visually for N=3:
    //
    //     a_in[0]──►[PE00]──►[PE01]──►[PE02]──►(unused)
    //                 │        │        │
    //     a_in[1]──►[PE10]──►[PE11]──►[PE12]──►(unused)
    //                 │        │        │
    //     a_in[2]──►[PE20]──►[PE21]──►[PE22]──►(unused)
    //                 │        │        │
    //               (unused) (unused) (unused)
    //                 ▲        ▲        ▲
    //               b_in[0] b_in[1]  b_in[2]
    //               (fed from top)
    // ================================================================

endmodule
