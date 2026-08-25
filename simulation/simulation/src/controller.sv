`timescale 1ns / 1ps
// ============================================================================
// Module: controller.sv
// Description: Finite State Machine (FSM) Controller for Systolic Array
//
// States:
//   - STATE_IDLE    (0): Waits for 'start' pulse; resets systolic array.
//   - STATE_LOAD    (1): Asserts 'load_en' to latch matrix inputs into skew buffers.
//   - STATE_COMPUTE (2): Asserts 'shift_en' and 'array_en' for (3N - 1) cycles.
//   - STATE_DONE    (3): Asserts 'done' flag when matrix C is fully computed.
// ============================================================================

module controller #(
    parameter N = 4
)(
    input  wire  clk,
    input  wire  rst,
    input  wire  start,

    output reg   load_en,
    output reg   shift_en,
    output reg   array_en,
    output reg   array_rst,
    output reg   done
);

    typedef enum logic [1:0] {
        STATE_IDLE    = 2'd0,
        STATE_LOAD    = 2'd1,
        STATE_COMPUTE = 2'd2,
        STATE_DONE    = 2'd3
    } state_t;

    state_t state, next_state;

    // Total cycles to skew + feed + propagate through N x N array
    localparam COMPUTE_CYCLES = 3*N - 1;
    reg [7:0] cycle_count;

    // State Register
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Next State Logic
    always_comb begin
        next_state = state;
        case (state)
            STATE_IDLE: begin
                if (start) next_state = STATE_LOAD;
            end
            STATE_LOAD: begin
                next_state = STATE_COMPUTE;
            end
            STATE_COMPUTE: begin
                if (cycle_count == COMPUTE_CYCLES - 1)
                    next_state = STATE_DONE;
            end
            STATE_DONE: begin
                if (start) next_state = STATE_LOAD;
            end
            default: next_state = STATE_IDLE;
        endcase
    end

    // Cycle Counter
    always_ff @(posedge clk) begin
        if (rst || state != STATE_COMPUTE) begin
            cycle_count <= 8'd0;
        end else begin
            cycle_count <= cycle_count + 8'd1;
        end
    end

    // Output Generation Logic
    always_comb begin
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
                shift_en  = 1'b1;
                array_en  = 1'b1;
            end
            STATE_DONE: begin
                done      = 1'b1;
            end
            default: begin
                array_rst = 1'b1;
            end
        endcase
    end

endmodule
