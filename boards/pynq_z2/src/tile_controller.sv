`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: tile_controller
// Description: Multi-Loop Output-Stationary Tiling FSM with Zero-Padding,
//              In-Place Partial-Sum Accumulation Across K Tiles, and Active-Region Sizing.
// ============================================================================

module tile_controller #(
    parameter int ARRAY_ROWS = 16,
    parameter int ARRAY_COLS = 16,
    parameter int TILE_K     = 16
)(
    input  wire                               clk,
    input  wire                               rst_n,

    // Execution control
    input  wire                               start,
    input  wire                               soft_reset,

    // Matrix dimensions
    input  wire [15:0]                        m_dim,
    input  wire [15:0]                        k_dim,
    input  wire [15:0]                        n_dim,

    // Active region configuration
    input  wire [7:0]                         active_m_in,
    input  wire [7:0]                         active_n_in,

    // Status signals
    output logic                              busy,
    output logic                              done,

    // Systolic array and skew buffer control
    output logic                              load_en,
    output logic                              shift_en,
    output logic                              array_en,
    output logic                              clr_acc,
    output logic                              c_capture,
    output wire                               active_mask [0:ARRAY_ROWS-1][0:ARRAY_COLS-1],

    // Sub-tile coordinates and valid bounds
    output logic [15:0]                       curr_mt,
    output logic [15:0]                       curr_nt,
    output logic [15:0]                       curr_kt,
    output wire  [7:0]                        actual_m,
    output wire  [7:0]                        actual_k,
    output wire  [7:0]                        actual_n,

    // Hardware measurement counters
    output logic [31:0]                       cycles_counter,
    output logic [31:0]                       tiles_counter
);

    typedef enum logic [2:0] {
        ST_IDLE      = 3'd0,
        ST_LOAD      = 3'd1,
        ST_COMPUTE   = 3'd2,
        ST_CHECK_K   = 3'd3,
        ST_CAPTURE   = 3'd4,
        ST_NEXT_TILE = 3'd5,
        ST_DONE      = 3'd6
    } state_t;

    state_t state, next_state;

    // Registered matrix config
    logic [15:0] m_reg, k_reg, n_reg;
    logic [7:0]  act_m_reg, act_n_reg;

    localparam int ROW_SHIFT = (ARRAY_ROWS == 16) ? 4 : $clog2(ARRAY_ROWS);
    localparam int COL_SHIFT = (ARRAY_COLS == 16) ? 4 : $clog2(ARRAY_COLS);
    localparam int K_SHIFT   = (TILE_K == 16)     ? 4 : $clog2(TILE_K);

    // Tile counters
    logic [15:0] mt_reg, nt_reg, kt_reg;
    wire  [15:0] num_m_tiles = (m_reg + ARRAY_ROWS - 1) >> ROW_SHIFT;
    wire  [15:0] num_n_tiles = (n_reg + ARRAY_COLS - 1) >> COL_SHIFT;
    wire  [15:0] num_k_tiles = (k_reg + TILE_K - 1)     >> K_SHIFT;

    // Compute cycle counter for systolic wavefront
    localparam int MAX_COMPUTE_CYCLES = ARRAY_ROWS + ARRAY_COLS + TILE_K - 1;
    localparam int CNT_WIDTH          = $clog2(MAX_COMPUTE_CYCLES + 1);
    logic [CNT_WIDTH-1:0] compute_cnt;
    logic [7:0] compute_cycle_limit;
    wire [7:0] effective_m = (actual_m < act_m_reg) ? actual_m : act_m_reg;
    wire [7:0] effective_n = (actual_n < act_n_reg) ? actual_n : act_n_reg;
    wire [7:0] calc_cycle_limit = (effective_m + effective_n + actual_k > 0)
        ? (effective_m + effective_n + actual_k - 1'b1) : 8'd1;

    // A systolic wavefront needs M + N + K - 1 active shifts. Register the limit
    // during ST_LOAD/ST_IDLE to eliminate long combinational arithmetic from ST_COMPUTE.
    always_ff @(posedge clk) begin
        if (!rst_n || soft_reset) begin
            compute_cycle_limit <= 8'd47;
        end else if (state == ST_IDLE || state == ST_LOAD || state == ST_CHECK_K || state == ST_NEXT_TILE) begin
            compute_cycle_limit <= calc_cycle_limit;
        end
    end

    // Instantiate address generator
    wire is_last_k;
    wire is_last_overall;
    wire pad_a_dummy [0:ARRAY_ROWS-1];
    wire pad_b_dummy [0:ARRAY_COLS-1];

    tile_addr_gen #(
        .ARRAY_ROWS (ARRAY_ROWS),
        .ARRAY_COLS (ARRAY_COLS),
        .TILE_K     (TILE_K)
    ) u_addr_gen (
        .clk            (clk),
        .rst_n          (rst_n),
        .m_dim          (m_reg),
        .k_dim          (k_reg),
        .n_dim          (n_reg),
        .mt_idx         (mt_reg),
        .nt_idx         (nt_reg),
        .kt_idx         (kt_reg),
        .k_step         (8'd0),
        .actual_m       (actual_m),
        .actual_k       (actual_k),
        .actual_n       (actual_n),
        .pad_a          (pad_a_dummy),
        .pad_b          (pad_b_dummy),
        .is_last_k_tile (is_last_k),
        .is_last_tile   (is_last_overall)
    );

    // Active mask generation via genvar continuous assignment
    genvar ar, ac;
    generate
        for (ar = 0; ar < ARRAY_ROWS; ar = ar + 1) begin : gen_act_r
            for (ac = 0; ac < ARRAY_COLS; ac = ac + 1) begin : gen_act_c
                assign active_mask[ar][ac] = (ar < act_m_reg) && (ac < act_n_reg);
            end
        end
    endgenerate

    // Performance counters
    always_ff @(posedge clk) begin
        if (!rst_n || soft_reset) begin
            cycles_counter <= '0;
            tiles_counter  <= '0;
        end else if (start && (state == ST_IDLE || state == ST_DONE)) begin
            cycles_counter <= '0;
            tiles_counter  <= '0;
        end else if (busy) begin
            cycles_counter <= cycles_counter + 1;
            if (state == ST_COMPUTE && compute_cnt == compute_cycle_limit - 1'b1) begin
                tiles_counter <= tiles_counter + 1;
            end
        end
    end

    // Sequential State Register & Counters
    always_ff @(posedge clk) begin
        if (!rst_n || soft_reset) begin
            state       <= ST_IDLE;
            m_reg       <= '0;
            k_reg       <= '0;
            n_reg       <= '0;
            act_m_reg   <= ARRAY_ROWS[7:0];
            act_n_reg   <= ARRAY_COLS[7:0];
            mt_reg      <= '0;
            nt_reg      <= '0;
            kt_reg      <= '0;
            compute_cnt <= '0;
        end else begin
            state <= next_state;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        m_reg     <= (m_dim == 0) ? 16'd16 : m_dim;
                        k_reg     <= (k_dim == 0) ? 16'd16 : k_dim;
                        n_reg     <= (n_dim == 0) ? 16'd16 : n_dim;
                        act_m_reg <= (active_m_in == 0 || active_m_in > ARRAY_ROWS) ? ARRAY_ROWS[7:0] : active_m_in;
                        act_n_reg <= (active_n_in == 0 || active_n_in > ARRAY_COLS) ? ARRAY_COLS[7:0] : active_n_in;
                        mt_reg    <= '0;
                        nt_reg    <= '0;
                        kt_reg    <= '0;
                    end
                end

                ST_LOAD: begin
                    compute_cnt <= '0;
                end

                ST_COMPUTE: begin
                    compute_cnt <= compute_cnt + 1;
                end

                ST_CHECK_K: begin
                    if (!is_last_k) begin
                        kt_reg <= kt_reg + 1;
                    end
                end

                ST_CAPTURE: begin
                    // 1 cycle result latching into c_buf
                end

                ST_NEXT_TILE: begin
                    kt_reg <= '0;
                    if (nt_reg + 1 < num_n_tiles) begin
                        nt_reg <= nt_reg + 1;
                    end else begin
                        nt_reg <= '0;
                        mt_reg <= mt_reg + 1;
                    end
                end

                ST_DONE: begin
                    // A new command may be accepted directly from DONE.
                    // Reload the shape and reset all tile coordinates just
                    // as the IDLE start path does.
                    if (start) begin
                        m_reg     <= (m_dim == 0) ? 16'd16 : m_dim;
                        k_reg     <= (k_dim == 0) ? 16'd16 : k_dim;
                        n_reg     <= (n_dim == 0) ? 16'd16 : n_dim;
                        act_m_reg <= (active_m_in == 0 || active_m_in > ARRAY_ROWS) ? ARRAY_ROWS[7:0] : active_m_in;
                        act_n_reg <= (active_n_in == 0 || active_n_in > ARRAY_COLS) ? ARRAY_COLS[7:0] : active_n_in;
                        mt_reg    <= '0;
                        nt_reg    <= '0;
                        kt_reg    <= '0;
                    end
                end

                default: ;
            endcase
        end
    end

    // Next State Logic
    always_comb begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                if (start) next_state = ST_LOAD;
            end

            ST_LOAD: begin
                next_state = ST_COMPUTE;
            end

            ST_COMPUTE: begin
                if (compute_cnt == compute_cycle_limit - 1'b1)
                    next_state = ST_CHECK_K;
            end

            ST_CHECK_K: begin
                if (is_last_k)
                    next_state = ST_CAPTURE;
                else
                    next_state = ST_LOAD;
            end

            ST_CAPTURE: begin
                next_state = ST_NEXT_TILE;
            end

            ST_NEXT_TILE: begin
                if (is_last_overall)
                    next_state = ST_DONE;
                else
                    next_state = ST_LOAD;
            end

            ST_DONE: begin
                if (start) next_state = ST_LOAD;
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // Output assignments
    assign busy       = (state != ST_IDLE) && (state != ST_DONE);
    assign done       = (state == ST_DONE);
    assign load_en    = (state == ST_LOAD);
    assign shift_en   = (state == ST_COMPUTE);
    assign array_en   = (state == ST_COMPUTE);
    assign clr_acc    = (state == ST_LOAD) && (kt_reg == 16'd0);
    assign c_capture  = (state == ST_CAPTURE);
    assign curr_mt    = mt_reg;
    assign curr_nt    = nt_reg;
    assign curr_kt    = kt_reg;

endmodule

`default_nettype wire
