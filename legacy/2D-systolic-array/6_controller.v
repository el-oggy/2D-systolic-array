// ============================================================
// controller.v — FSM Controller for the Systolic Array
// ============================================================
// Manages the phases of operation:
//
//   IDLE ──► LOAD ──► COMPUTE ──► DONE
//
// Timing breakdown for COMPUTE phase:
//   - 1 cycle:  skew buffer latency (first shift outputs appear)
//   - 2N-1 cycles: data feeding from skew buffers
//   - N-1 cycles: pipeline drain (last data propagates through PEs)
//   Total = 1 + (2N-1) + (N-1) = 3N - 1 compute cycles
// ============================================================

module controller #(
    parameter N = 4                   // Array dimension
)(
    input  wire clk,
    input  wire rst,
    input  wire start,                // Pulse HIGH to begin computation

    output reg  load_en,              // Load data into skew buffers
    output reg  shift_en,             // Shift data out of skew buffers
    output reg  array_en,             // Enable PEs in the systolic array
    output reg  array_rst,            // Reset PEs (clear accumulators)
    output reg  done                  // HIGH when results are valid
);

    // State definitions
    localparam STATE_IDLE    = 2'd0;
    localparam STATE_LOAD    = 2'd1;
    localparam STATE_COMPUTE = 2'd2;
    localparam STATE_DONE    = 2'd3;

    // Total compute cycles:
    // - Skew buffer outputs 2N-1 values, but first output has 1-cycle latency
    // - After last skew buffer output, data still needs to propagate through PEs
    // - PE[N-1][N-1] receives its last data (N-1) cycles after PE[0][0]
    //   due to PE pass-through delay
    // Total = (2N-1) + N = 3N - 1
    localparam COMPUTE_CYCLES = 3*N - 1;

    reg [1:0] state, next_state;
    reg [7:0] cycle_count;

    // State register
    always @(posedge clk) begin
        if (rst)
            state <= STATE_IDLE;
        else
            state <= next_state;
    end

    // Next state logic
    always @(*) begin
        next_state = state;
        case (state)
            STATE_IDLE:
                if (start) next_state = STATE_LOAD;
            STATE_LOAD:
                next_state = STATE_COMPUTE;
            STATE_COMPUTE:
                if (cycle_count == COMPUTE_CYCLES - 1)
                    next_state = STATE_DONE;
            STATE_DONE:
                if (start) next_state = STATE_LOAD;
            default: next_state = STATE_IDLE;
        endcase
    end

    // Cycle counter
    always @(posedge clk) begin
        if (rst || state != STATE_COMPUTE)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    // Output logic
    always @(*) begin
        load_en   = 1'b0;
        shift_en  = 1'b0;
        array_en  = 1'b0;
        array_rst = 1'b0;
        done      = 1'b0;

        case (state)
            STATE_IDLE: begin
                array_rst = 1'b1;
            end
            STATE_LOAD: begin
                load_en   = 1'b1;
                array_rst = 1'b1;
            end
            STATE_COMPUTE: begin
                shift_en = 1'b1;
                array_en = 1'b1;
            end
            STATE_DONE: begin
                done = 1'b1;
            end
        endcase
    end

endmodule
