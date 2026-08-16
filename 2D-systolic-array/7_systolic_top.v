// ============================================================
// systolic_top.v — Top-Level Wrapper for Systolic Array System
// ============================================================
// Connects all the pieces together:
//
//   ┌───────────────────────────────────────────────┐
//   │              systolic_top                      │
//   │                                                │
//   │  ┌────────────┐                                │
//   │  │ Controller │──► load_en, shift_en,          │
//   │  │    FSM     │    array_en, array_rst, done   │
//   │  └────────────┘                                │
//   │        │                                       │
//   │  ┌─────▼──────┐   ┌──────────────┐            │
//   │  │ Skew Buf A │──►│              │            │
//   │  │ (rows)     │   │   N×N        │            │
//   │  └────────────┘   │   Systolic   │──► result  │
//   │  ┌────────────┐   │   Array      │            │
//   │  │ Skew Buf B │──►│              │            │
//   │  │ (columns)  │   └──────────────┘            │
//   │  └────────────┘                                │
//   └───────────────────────────────────────────────┘
//
// USAGE:
//   1. Load matrix_a and matrix_b on the inputs
//   2. Pulse 'start' HIGH for one cycle
//   3. Wait for 'done' to go HIGH
//   4. Read results from result[i][j]
// ============================================================

module systolic_top #(
    parameter N = 4,                  // Matrix dimension (N×N)
    parameter DATA_WIDTH = 8          // Bit width of each element
)(
    input  wire clk,
    input  wire rst,
    input  wire start,                // Pulse to begin computation

    // --- Input matrices (flat N×N arrays) ---
    input  wire signed [DATA_WIDTH-1:0] matrix_a [0:N-1][0:N-1],
    input  wire signed [DATA_WIDTH-1:0] matrix_b [0:N-1][0:N-1],

    // --- Output: result matrix C = A × B ---
    output wire signed [2*DATA_WIDTH-1:0] result [0:N-1][0:N-1],

    // --- Status ---
    output wire done
);

    // ================================================================
    // INTERNAL SIGNALS
    // ================================================================

    // Controller outputs
    wire load_en;
    wire shift_en;
    wire array_en;
    wire array_rst;

    // Skewed data outputs (fed into the systolic array)
    wire signed [DATA_WIDTH-1:0] a_skewed [0:N-1];  // One per row
    wire signed [DATA_WIDTH-1:0] b_skewed [0:N-1];  // One per column

    // Transposed B matrix for column-wise skewing
    // The B skew buffer skews by ROW, but we need B skewed by COLUMN.
    // So we transpose B first: b_transposed[j][i] = matrix_b[i][j]
    // Then skewing by row on the transposed matrix = skewing by column on the original.
    reg signed [DATA_WIDTH-1:0] matrix_b_transposed [0:N-1][0:N-1];

    integer ti, tj;
    always @(*) begin
        for (ti = 0; ti < N; ti = ti + 1)
            for (tj = 0; tj < N; tj = tj + 1)
                matrix_b_transposed[ti][tj] = matrix_b[tj][ti];
    end

    // ================================================================
    // CONTROLLER FSM
    // ================================================================
    controller #(
        .N(N)
    ) ctrl (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .load_en  (load_en),
        .shift_en (shift_en),
        .array_en (array_en),
        .array_rst(array_rst),
        .done     (done)
    );

    // ================================================================
    // SKEW BUFFER FOR MATRIX A (rows)
    // ================================================================
    // A values flow LEFT → RIGHT through the array
    // Row i is delayed by i clock cycles
    skew_buffer #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH)
    ) skew_a (
        .clk       (clk),
        .rst       (rst),
        .load      (load_en),
        .shift_en  (shift_en),
        .matrix_in (matrix_a),
        .data_out  (a_skewed)
    );

    // ================================================================
    // SKEW BUFFER FOR MATRIX B (columns)
    // ================================================================
    // B values flow TOP → BOTTOM through the array
    // Column j is delayed by j clock cycles
    // We use the TRANSPOSED B so that row-skewing = column-skewing
    skew_buffer #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH)
    ) skew_b (
        .clk       (clk),
        .rst       (rst),
        .load      (load_en),
        .shift_en  (shift_en),
        .matrix_in (matrix_b_transposed),
        .data_out  (b_skewed)
    );

    // ================================================================
    // SYSTOLIC ARRAY (N×N PEs)
    // ================================================================
    systolic_array #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH)
    ) array_inst (
        .clk    (clk),
        .rst    (array_rst),
        .en     (array_en),
        .a_in   (a_skewed),
        .b_in   (b_skewed),
        .result (result)
    );

endmodule
