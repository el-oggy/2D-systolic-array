// ============================================================
// PE.v — Processing Element for a Systolic Array
// ============================================================
// This is the basic building block. Each PE does ONE thing:
//   acc = acc + (a_in * b_in)
// and passes a_in to the right, b_in downward.
// ============================================================

module PE #(
    parameter DATA_WIDTH = 8          // Width of each input (a and b)
)(
    input  wire clk,                  // Clock
    input  wire rst,                  // Synchronous reset (active high)
    input  wire en,                   // Enable signal

    // --- Data flowing LEFT → RIGHT (matrix A values) ---
    input  wire signed [DATA_WIDTH-1:0] a_in,   // From left neighbor
    output reg  signed [DATA_WIDTH-1:0] a_out,  // To right neighbor

    // --- Data flowing TOP → BOTTOM (matrix B values) ---
    input  wire signed [DATA_WIDTH-1:0] b_in,   // From top neighbor
    output reg  signed [DATA_WIDTH-1:0] b_out,  // To bottom neighbor

    // --- Accumulated result (stays in this PE) ---
    // 2*DATA_WIDTH bits to prevent overflow
    // e.g., 8-bit × 8-bit = 16-bit product, accumulated over N cycles
    output reg  signed [2*DATA_WIDTH-1:0] acc
);

    always @(posedge clk) begin
        if (rst) begin
            // Reset: clear everything
            a_out <= 0;
            b_out <= 0;
            acc   <= 0;
        end
        else if (en) begin
            // ---- THE CORE OPERATION ----
            // Multiply a_in and b_in, add to running total
            acc <= acc + (a_in * b_in);

            // ---- PASS-THROUGH ----
            // Forward a_in to the right neighbor (delayed by 1 clock)
            a_out <= a_in;
            // Forward b_in to the bottom neighbor (delayed by 1 clock)
            b_out <= b_in;
        end
        // If en=0: all registers hold their current value
    end

endmodule
