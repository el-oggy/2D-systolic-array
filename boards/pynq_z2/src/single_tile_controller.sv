`timescale 1ns / 1ps
`default_nettype none

// Low-overhead controller for the AXI tile engine. The host driver schedules
// M/N/K tiles, so this block executes exactly one tile and does not synthesize
// the generic multi-loop address generator into each AXI engine.
module single_tile_controller #(
    parameter int ARRAY_ROWS = 16,
    parameter int ARRAY_COLS = 16,
    parameter int TILE_K = 16,
    parameter bit WAIT_FOR_CAPTURE = 1'b0,
    parameter bit ACTIVE_EXTENT_OUTPUTS = 1'b0
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire soft_reset,
    input wire [15:0] m_dim,
    input wire [15:0] k_dim,
    input wire [15:0] n_dim,
    input wire [7:0] active_m_in,
    input wire [7:0] active_n_in,
    output wire busy,
    output wire done,
    output wire load_en,
    output wire shift_en,
    output wire array_en,
    output wire clr_acc,
    output wire c_capture,
    input  wire capture_done,
    output wire active_mask [0:ARRAY_ROWS-1][0:ARRAY_COLS-1],
    output wire [15:0] curr_mt,
    output wire [15:0] curr_nt,
    output wire [15:0] curr_kt,
    output wire [7:0] actual_m,
    output wire [7:0] actual_k,
    output wire [7:0] actual_n,
    output logic [31:0] cycles_counter,
    output logic [31:0] tiles_counter
);
    typedef enum logic [2:0] {
        ST_IDLE, ST_LOAD, ST_COMPUTE, ST_CHECK, ST_CAPTURE, ST_NEXT, ST_DONE
    } state_t;
    state_t state, next_state;

    logic [7:0] m_reg, k_reg, n_reg;
    logic [7:0] act_m_reg, act_n_reg;
    logic row_active_q [0:ARRAY_ROWS-1];
    logic col_active_q [0:ARRAY_COLS-1];
    localparam int MAX_COMPUTE_CYCLES = ARRAY_ROWS + ARRAY_COLS + TILE_K - 1;
    localparam int CNT_WIDTH = $clog2(MAX_COMPUTE_CYCLES + 1);
    logic [CNT_WIDTH-1:0] compute_cnt;
    logic [CNT_WIDTH-1:0] compute_terminal_count;
    wire [7:0] effective_m = (m_reg < act_m_reg) ? m_reg : act_m_reg;
    wire [7:0] effective_n = (n_reg < act_n_reg) ? n_reg : act_n_reg;

    function automatic [7:0] bound_dim(input [15:0] value, input integer physical);
        if (value == 0)
            bound_dim = physical[7:0];
        else if (value > physical)
            bound_dim = physical[7:0];
        else
            bound_dim = value[7:0];
    endfunction

    always_comb begin
        next_state = state;
        case (state)
            ST_IDLE: if (start) next_state = ST_LOAD;
            ST_LOAD: next_state = ST_COMPUTE;
            ST_COMPUTE: if (compute_cnt == compute_terminal_count) next_state = ST_CHECK;
            ST_CHECK: next_state = ST_CAPTURE;
            ST_CAPTURE: begin
                if (!WAIT_FOR_CAPTURE || capture_done)
                    next_state = ST_NEXT;
            end
            ST_NEXT: next_state = ST_DONE;
            ST_DONE: if (start) next_state = ST_LOAD;
            default: next_state = ST_IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n || soft_reset) begin
            state <= ST_IDLE;
            m_reg <= ARRAY_ROWS[7:0];
            k_reg <= TILE_K[7:0];
            n_reg <= ARRAY_COLS[7:0];
            act_m_reg <= ARRAY_ROWS[7:0];
            act_n_reg <= ARRAY_COLS[7:0];
            compute_cnt <= '0;
            compute_terminal_count <= '0;
            for (int r = 0; r < ARRAY_ROWS; r = r + 1)
                row_active_q[r] <= 1'b1;
            for (int c = 0; c < ARRAY_COLS; c = c + 1)
                col_active_q[c] <= 1'b1;
        end else begin
            state <= next_state;
            if ((state == ST_IDLE || state == ST_DONE) && start) begin
                m_reg <= bound_dim(m_dim, ARRAY_ROWS);
                k_reg <= bound_dim(k_dim, TILE_K);
                n_reg <= bound_dim(n_dim, ARRAY_COLS);
                act_m_reg <= (active_m_in == 0 || active_m_in > ARRAY_ROWS) ? ARRAY_ROWS[7:0] : active_m_in;
                act_n_reg <= (active_n_in == 0 || active_n_in > ARRAY_COLS) ? ARRAY_COLS[7:0] : active_n_in;
                for (int r = 0; r < ARRAY_ROWS; r = r + 1)
                    row_active_q[r] <= (active_m_in == 0 || active_m_in > ARRAY_ROWS || active_m_in > r);
                for (int c = 0; c < ARRAY_COLS; c = c + 1)
                    col_active_q[c] <= (active_n_in == 0 || active_n_in > ARRAY_COLS || active_n_in > c);
            end

            if (state == ST_LOAD) begin
                compute_cnt <= '0;
                // Register the last active wavefront count one cycle before
                // compute. This removes the dimension-add/compare chain from
                // the counter-enable path without adding a compute cycle.
                compute_terminal_count <= effective_m + effective_n + k_reg - 8'd2;
            end else if (state == ST_COMPUTE) begin
                compute_cnt <= compute_cnt + 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n || soft_reset) begin
            cycles_counter <= '0;
            tiles_counter <= '0;
        end else if (start && (state == ST_IDLE || state == ST_DONE)) begin
            cycles_counter <= '0;
            tiles_counter <= '0;
        end else if (busy) begin
            cycles_counter <= cycles_counter + 1'b1;
            if (state == ST_COMPUTE && compute_cnt == compute_terminal_count)
                tiles_counter <= tiles_counter + 1'b1;
        end
    end

    genvar r, c;
    generate
        for (r = 0; r < ARRAY_ROWS; r = r + 1) begin : gen_active_rows
            for (c = 0; c < ARRAY_COLS; c = c + 1) begin : gen_active_cols
                assign active_mask[r][c] = row_active_q[r] && col_active_q[c];
            end
        end
    endgenerate

    assign busy = (state != ST_IDLE) && (state != ST_DONE);
    assign done = (state == ST_DONE);
    assign load_en = (state == ST_LOAD);
    assign shift_en = (state == ST_COMPUTE);
    assign array_en = (state == ST_COMPUTE);
    assign clr_acc = (state == ST_LOAD);
    assign c_capture = (state == ST_CAPTURE);
    assign actual_m = ACTIVE_EXTENT_OUTPUTS ? effective_m : m_reg;
    assign actual_k = k_reg;
    assign actual_n = ACTIVE_EXTENT_OUTPUTS ? effective_n : n_reg;
    assign curr_mt = '0;
    assign curr_nt = '0;
    assign curr_kt = '0;
endmodule

`default_nettype wire
