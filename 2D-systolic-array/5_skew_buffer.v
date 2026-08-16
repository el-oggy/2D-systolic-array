// ============================================================
// skew_buffer.v — Input Skew Buffer for Systolic Array
// ============================================================
// 
// PROBLEM: In a systolic array, data must arrive at each PE at
// the right time. Row i of matrix A needs to be delayed by i
// clock cycles, and column j of matrix B by j cycles.
//
// SOLUTION: This module takes a FLAT matrix (all values at once)
// and outputs one skewed value per row/column per clock cycle.
//
// HOW IT WORKS:
// For N=3 and matrix A:
//   Row 0: delay=0 → outputs a[0][0], a[0][1], a[0][2], 0, 0
//   Row 1: delay=1 → outputs 0, a[1][0], a[1][1], a[1][2], 0
//   Row 2: delay=2 → outputs 0, 0, a[2][0], a[2][1], a[2][2]
//
// Internally, each row has a shift register. Row i's register
// is pre-loaded with i zeros followed by the actual data.
//
// The total feeding time is 2N-1 clock cycles.
// ============================================================

module skew_buffer #(
    parameter N = 4,                  // Matrix dimension
    parameter DATA_WIDTH = 8          // Bit width of each value
)(
    input  wire clk,
    input  wire rst,
    input  wire load,                 // Pulse HIGH to load matrix data
    input  wire shift_en,             // Pulse HIGH each cycle to shift data out

    // --- Matrix input (flat): N×N values loaded all at once ---
    // matrix_in[i][j] = element at row i, column j
    input  wire signed [DATA_WIDTH-1:0] matrix_in [0:N-1][0:N-1],

    // --- Skewed output: one value per row/column per clock ---
    output reg  signed [DATA_WIDTH-1:0] data_out [0:N-1]
);

    // ================================================================
    // SHIFT REGISTERS
    // ================================================================
    // Each row gets a shift register of length (2N-1).
    // Row i is loaded as: [0, 0, ...(i zeros), a[i][0], a[i][1], ..., a[i][N-1], 0, ...]
    // On each clock, we shift left and output the leftmost value.

    // Shift register depth = 2*N - 1 (total cycles to feed all data)
    localparam DEPTH = 2*N - 1;

    reg signed [DATA_WIDTH-1:0] shift_reg [0:N-1][0:DEPTH-1];

    integer r, c;

    always @(posedge clk) begin
        if (rst) begin
            // Clear everything
            for (r = 0; r < N; r = r + 1) begin
                data_out[r] <= 0;
                for (c = 0; c < DEPTH; c = c + 1) begin
                    shift_reg[r][c] <= 0;
                end
            end
        end
        else if (load) begin
            // Load matrix data into shift registers with skewing
            for (r = 0; r < N; r = r + 1) begin
                for (c = 0; c < DEPTH; c = c + 1) begin
                    // Position (c - r) maps to matrix column
                    // If c < r, it's a leading zero (delay)
                    // If c >= r and c < r+N, it's actual data
                    // If c >= r+N, it's a trailing zero
                    if (c >= r && c < r + N) begin
                        shift_reg[r][c] <= matrix_in[r][c - r];
                    end else begin
                        shift_reg[r][c] <= 0;
                    end
                end
            end
            // Output the first value immediately
            for (r = 0; r < N; r = r + 1) begin
                data_out[r] <= 0;  // Will be valid after first shift
            end
        end
        else if (shift_en) begin
            // Shift left: output shift_reg[r][0], then shift everything left
            for (r = 0; r < N; r = r + 1) begin
                data_out[r] <= shift_reg[r][0];
                for (c = 0; c < DEPTH - 1; c = c + 1) begin
                    shift_reg[r][c] <= shift_reg[r][c + 1];
                end
                shift_reg[r][DEPTH-1] <= 0;  // Fill with zero at the end
            end
        end
    end

    // ================================================================
    // EXAMPLE: N=3, Matrix A = |1 2 3|
    //                          |4 5 6|
    //                          |7 8 9|
    //
    // After LOAD, shift registers contain:
    //   Row 0: [1, 2, 3, 0, 0]  (no delay)
    //   Row 1: [0, 4, 5, 6, 0]  (1 cycle delay)
    //   Row 2: [0, 0, 7, 8, 9]  (2 cycle delay)
    //
    // SHIFT outputs (data_out[0], data_out[1], data_out[2]):
    //   Cycle 0: 1, 0, 0
    //   Cycle 1: 2, 4, 0
    //   Cycle 2: 3, 5, 7
    //   Cycle 3: 0, 6, 8
    //   Cycle 4: 0, 0, 9
    //
    // This is exactly the skewing pattern we need!
    // ================================================================

endmodule
