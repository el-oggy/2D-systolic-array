`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: accel_top
// Description: Top-Level Adaptive Systolic Array Matrix Accelerator for PYNQ-Z2.
//              Integrates:
//              - AXI4-Lite Slave Register File (axi_lite_regs)
//              - AXI4-Stream Slave Input Adapter (axis_in_adapter)
//              - Matrix A and B Tile Buffers (a_buf, b_buf)
//              - Adaptive Skew Buffers (skew_buffers)
//              - 2D Systolic Array Mesh (systolic_array) with MAC_IMPL selection
//              - Output Matrix C Buffer (c_buf)
//              - AXI4-Stream Master Output Adapter (axis_out_adapter)
//              - Tiling and Flow Controller (tile_controller)
// ============================================================================

module accel_top #(
    parameter int ARRAY_ROWS      = 16,
    parameter int ARRAY_COLS      = 16,
    parameter int TILE_K          = 16,
    parameter int DATA_WIDTH      = 8,
    parameter int ACC_WIDTH       = 32,
    parameter     MAC_IMPL        = "DSP", // "DSP", "LUT", "SHARED"
    parameter int DSP_PE_LIMIT    = ARRAY_ROWS * ARRAY_COLS,
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_DATA_WIDTH  = 32,
    parameter int AXIS_DATA_WIDTH = 32
)(
    // Primary clock and synchronous reset
    input  wire                                clk,
    input  wire                                rst_n,

    // AXI4-Lite Slave Interface (Control & Status)
    input  wire [AXI_ADDR_WIDTH-1:0]           s_axi_awaddr,
    input  wire [2:0]                          s_axi_awprot,
    input  wire                                s_axi_awvalid,
    output logic                               s_axi_awready,

    input  wire [AXI_DATA_WIDTH-1:0]           s_axi_wdata,
    input  wire [(AXI_DATA_WIDTH/8)-1:0]       s_axi_wstrb,
    input  wire                                s_axi_wvalid,
    output logic                               s_axi_wready,

    output logic [1:0]                         s_axi_bresp,
    output logic                               s_axi_bvalid,
    input  wire                                s_axi_bready,

    input  wire [AXI_ADDR_WIDTH-1:0]           s_axi_araddr,
    input  wire [2:0]                          s_axi_arprot,
    input  wire                                s_axi_arvalid,
    output logic                               s_axi_arready,

    output logic [AXI_DATA_WIDTH-1:0]          s_axi_rdata,
    output logic [1:0]                         s_axi_rresp,
    output logic                               s_axi_rvalid,
    input  wire                                s_axi_rready,

    // AXI4-Stream Slave Interface (Matrix Data In: A and B)
    input  wire [AXIS_DATA_WIDTH-1:0]          s_axis_tdata,
    input  wire [(AXIS_DATA_WIDTH/8)-1:0]      s_axis_tkeep,
    input  wire                                s_axis_tvalid,
    output logic                               s_axis_tready,
    input  wire                                s_axis_tlast,

    // AXI4-Stream Master Interface (Matrix Data Out: C)
    output logic [AXIS_DATA_WIDTH-1:0]         m_axis_tdata,
    output logic [(AXIS_DATA_WIDTH/8)-1:0]     m_axis_tkeep,
    output logic                               m_axis_tvalid,
    input  wire                                m_axis_tready,
    output logic                               m_axis_tlast,

    // Interrupt output to Zynq Processing System
    output logic                               interrupt
);

    // ------------------------------------------------------------------------
    // Internal Wires & Interconnect
    // ------------------------------------------------------------------------
    wire        ctrl_start;
    logic       core_start;
    wire        ctrl_soft_reset;
    wire        invalid_shape;
    wire [15:0] cfg_m_dim;
    wire [15:0] cfg_k_dim;
    wire [15:0] cfg_n_dim;
    wire [7:0]  cfg_active_m;
    wire [7:0]  cfg_active_n;
    wire        cfg_cache_mvm;
    wire        cfg_stream_target_manual;
    wire        cfg_stream_target;
    logic [15:0] run_m_dim, run_k_dim, run_n_dim;
    logic [7:0] run_active_m, run_active_n;
    logic        run_cache_mvm;

    // This keeps the banked full-vector output store large enough for
    // multi-tile workloads while balancing FF/LUT pressure on XC7Z020.
    localparam int MAX_MVM_ROWS = 224;
    localparam int MAX_MVM_K = 512;
    localparam int WEIGHT_CACHE_DEPTH = MAX_MVM_ROWS * MAX_MVM_K;
    localparam int WEIGHT_ADDR_WIDTH = $clog2(WEIGHT_CACHE_DEPTH);
    localparam int WEIGHT_ROWS_PER_BANK =
        (MAX_MVM_ROWS + ARRAY_ROWS - 1) / ARRAY_ROWS;
    localparam int WEIGHT_BANK_DEPTH = WEIGHT_ROWS_PER_BANK * MAX_MVM_K;
    localparam int WEIGHT_BANK_ADDR_WIDTH = $clog2(WEIGHT_BANK_DEPTH);
    localparam int MVM_RESULT_BANK_DEPTH =
        (MAX_MVM_ROWS + ARRAY_ROWS - 1) / ARRAY_ROWS;
    localparam int MVM_RESULT_BANK_ADDR_WIDTH = $clog2(MVM_RESULT_BANK_DEPTH);

    wire        fsm_busy;
    wire        fsm_done;
    wire        overflow_flag;
    wire [31:0] hw_cycles;
    wire [31:0] hw_tiles;
    logic [15:0] loaded_weight_m, loaded_weight_k, loaded_vector_k;
    logic [15:0] mvm_m_base, mvm_k_base;
    logic [WEIGHT_BANK_ADDR_WIDTH-1:0] mvm_weight_group_base;
    logic        mvm_stream_start;
    logic        mvm_wait_output;
    logic        mvm_done;
    logic        mvm_has_more_m_q;
    logic [31:0] mvm_cycle_count;
    wire         accelerator_done;
    wire         accelerator_busy;
    wire         axis_load_enable;

    wire        load_en;
    wire        shift_en;
    wire        array_en;
    wire        clr_acc;
    wire        c_capture;
    wire        active_mask [0:ARRAY_ROWS-1][0:ARRAY_COLS-1];

    wire [15:0] curr_mt;
    wire [15:0] curr_nt;
    wire [15:0] curr_kt;
    wire [7:0]  actual_m;
    wire [7:0]  actual_k;
    wire [7:0]  actual_n;
    wire [7:0]  active_m_limit = (run_active_m == 0 || run_active_m > ARRAY_ROWS)
        ? ARRAY_ROWS[7:0] : run_active_m;
    wire [7:0]  active_n_limit = (run_active_n == 0 || run_active_n > ARRAY_COLS)
        ? ARRAY_COLS[7:0] : run_active_n;
    wire [7:0]  skew_actual_m = (actual_m < active_m_limit) ? actual_m : active_m_limit;
    wire [7:0]  skew_actual_n = (actual_n < active_n_limit) ? actual_n : active_n_limit;

    // Buffer read/write signals
    wire        a_wr_en;
    wire [WEIGHT_ADDR_WIDTH-1:0] a_wr_addr;
    wire signed [DATA_WIDTH-1:0] a_wr_data;

    wire        b_wr_en;
    wire [8:0]  b_wr_addr;
    wire signed [DATA_WIDTH-1:0] b_wr_data;
    wire        a_commit;
    wire        b_commit;
    wire        a_rd_en;
    wire [7:0]  a_rd_addr;
    wire [7:0]  a_rd_data;
    wire        b_rd_en;
    wire [8:0]  b_rd_addr;
    wire [7:0]  b_rd_data;
    wire        a_active_bank;
    wire        b_active_bank;
    logic       a_loaded;
    logic       b_loaded;
    logic       prefetch_busy;
    logic [2:0] prefetch_state;
    logic       a_rd_pending;
    logic       b_rd_pending;
    logic       tile_active_seen;
    logic [7:0] a_pending_addr;
    logic [7:0] b_pending_tile_addr;
    logic [3:0] a_prefetch_row, a_prefetch_k;
    logic [3:0] b_prefetch_k, b_prefetch_col;
    logic [4:0] a_prefetch_rows, a_prefetch_k_limit;
    logic [4:0] b_prefetch_k_limit, b_prefetch_cols;
    logic       a_prefetch_done, b_prefetch_done;
    wire [WEIGHT_BANK_ADDR_WIDTH-1:0] weight_rd_addr =
        mvm_weight_group_base + mvm_k_base + a_prefetch_k;
    wire [7:0] weight_rd_data [0:ARRAY_ROWS-1];
    wire [WEIGHT_ADDR_WIDTH-1:0] a_packet_bytes;
    wire [9:0] b_packet_bytes;
    wire        packet_overflow;
    logic [31:0] cfg_weight_bytes_q;
    wire [31:0] cfg_weight_bytes = cfg_weight_bytes_q;
    wire        cfg_cache_shape_bad = (cfg_n_dim != 16'd1) || (cfg_m_dim == 0) ||
        (cfg_m_dim > MAX_MVM_ROWS) || (cfg_k_dim == 0) ||
        (cfg_k_dim > MAX_MVM_K) || (cfg_weight_bytes > WEIGHT_CACHE_DEPTH) ||
        !cfg_stream_target_manual;
    logic signed [31:0] mvm_result_tile [0:ARRAY_ROWS-1];
    // Keep the completed MVM vector in row-banked synchronous BRAM. A tile
    // commit writes one result per row bank, preserving the 16-row commit
    // cadence while relieving the large register and read-mux bank.
    wire signed [31:0] mvm_result_rd_data [0:ARRAY_ROWS-1];
    wire signed [31:0] mvm_result_wr_data [0:ARRAY_ROWS-1];
    wire signed [31:0] mvm_rd_data;
    wire [9:0] c_rd_addr;
    wire signed [ACC_WIDTH-1:0] c_rd_data;
    wire c_buf_capture_done;
    wire [31:0] axis_cycles = run_cache_mvm ? mvm_cycle_count : hw_cycles;
    wire        accelerator_overflow = overflow_flag || packet_overflow;
    wire [7:0] run_m_bound = (run_m_dim == 0 || run_m_dim > ARRAY_ROWS)
        ? ARRAY_ROWS[7:0] : run_m_dim[7:0];
    wire [7:0] run_k_bound = (run_k_dim == 0 || run_k_dim > TILE_K)
        ? TILE_K[7:0] : run_k_dim[7:0];
    wire [7:0] run_n_bound = (run_n_dim == 0 || run_n_dim > ARRAY_COLS)
        ? ARRAY_COLS[7:0] : run_n_dim[7:0];
    wire [7:0] run_active_m_bound = (run_active_m == 0 || run_active_m > ARRAY_ROWS)
        ? ARRAY_ROWS[7:0] : run_active_m;
    wire [7:0] run_active_n_bound = (run_active_n == 0 || run_active_n > ARRAY_COLS)
        ? ARRAY_COLS[7:0] : run_active_n;
    wire [15:0] mvm_m_remaining = run_m_dim - mvm_m_base;
    wire [15:0] mvm_k_remaining = run_k_dim - mvm_k_base;
    wire [7:0] run_tile_m_dim = run_cache_mvm
        ? ((mvm_m_remaining > ARRAY_ROWS) ? ARRAY_ROWS[7:0] : mvm_m_remaining[7:0])
        : run_m_bound;
    wire [7:0] run_tile_k_dim = run_cache_mvm
        ? ((mvm_k_remaining > TILE_K) ? TILE_K[7:0] : mvm_k_remaining[7:0])
        : run_k_bound;
    wire [7:0] run_tile_n_dim = run_cache_mvm ? 8'd1 : run_n_bound;
    wire [7:0] run_prefetch_m = (run_tile_m_dim < run_active_m_bound)
        ? run_tile_m_dim : run_active_m_bound;
    wire [7:0] run_prefetch_n = (run_tile_n_dim < run_active_n_bound)
        ? run_tile_n_dim : run_active_n_bound;
    // Parallel tile data wires
    logic signed [DATA_WIDTH-1:0] a_tile_wire [0:ARRAY_ROWS-1][0:TILE_K-1];
    logic signed [DATA_WIDTH-1:0] b_tile_wire [0:TILE_K-1][0:ARRAY_COLS-1];

    // Skewed systolic boundary inputs
    wire signed [DATA_WIDTH-1:0] a_skewed [0:ARRAY_ROWS-1];
    wire signed [DATA_WIDTH-1:0] b_skewed [0:ARRAY_COLS-1];

    // Systolic 2D array output
    wire signed [ACC_WIDTH-1:0] c_mesh_out [0:ARRAY_ROWS-1][0:ARRAY_COLS-1];

    wire                        stream_busy;
    wire                        stream_done;

    // Effective combined reset
    wire combined_rst_n = rst_n && !ctrl_soft_reset;

    localparam logic [2:0] PF_IDLE = 3'd0, PF_PREP = 3'd1,
                           PF_AB_REQ = 3'd2, PF_START = 3'd3,
                           PF_RUN = 3'd4, PF_COMMIT = 3'd5;

    // Keep the dimension product out of the prefetch/start combinational cone.
    // AXI-Lite commits M and K as separate writes, and START is a later write,
    // so this register has settled before a cache load or operation is accepted.
    always_ff @(posedge clk) begin
        if (!rst_n)
            cfg_weight_bytes_q <= 32'd256; // reset dimensions are 16 x 16
        else
            cfg_weight_bytes_q <= {16'd0, cfg_m_dim} * {16'd0, cfg_k_dim};
    end

    assign accelerator_done = run_cache_mvm ? mvm_done : fsm_done;
    assign accelerator_busy = fsm_busy || stream_busy || prefetch_busy || mvm_wait_output;
    assign axis_load_enable = !(cfg_cache_mvm && accelerator_busy);

    assign invalid_shape = (cfg_cache_mvm
                               ? cfg_cache_shape_bad
                               : ((cfg_m_dim > ARRAY_ROWS) || (cfg_k_dim > TILE_K) ||
                                  (cfg_n_dim > ARRAY_COLS))) ||
                           packet_overflow ||
                           ((prefetch_state == PF_IDLE) &&
                            (!a_loaded || !b_loaded ||
                             (cfg_cache_mvm && ((loaded_weight_m != cfg_m_dim) ||
                                                (loaded_weight_k != cfg_k_dim) ||
                                                (loaded_vector_k != cfg_k_dim)))));
    assign a_rd_en = (prefetch_state == PF_AB_REQ) && !a_prefetch_done && !run_cache_mvm;
    wire weight_rd_en = (prefetch_state == PF_AB_REQ) && !a_prefetch_done && run_cache_mvm;
    assign b_rd_en = (prefetch_state == PF_AB_REQ) && !b_prefetch_done;
    assign a_rd_addr = {a_prefetch_row, a_prefetch_k};
    assign b_rd_addr = run_cache_mvm
        ? (mvm_k_base + b_prefetch_k)
        : {1'b0, b_prefetch_k, b_prefetch_col};

    // Prefetch a legacy tile or autonomously walk a cached MVM over 16x16
    // tiles. In cached mode, the A cache persists across activation vectors;
    // partial row sums are accumulated across K tiles before one output stream.
    always_ff @(posedge clk) begin
        if (!combined_rst_n) begin
            prefetch_state <= PF_IDLE;
            prefetch_busy  <= 1'b0;
            core_start     <= 1'b0;
            run_cache_mvm  <= 1'b0;
            a_rd_pending   <= 1'b0;
            b_rd_pending   <= 1'b0;
            tile_active_seen <= 1'b0;
            a_pending_addr <= '0;
            b_pending_tile_addr <= '0;
            a_prefetch_row <= '0;
            a_prefetch_k <= '0;
            b_prefetch_k <= '0;
            b_prefetch_col <= '0;
            a_prefetch_rows <= '0;
            a_prefetch_k_limit <= '0;
            b_prefetch_k_limit <= '0;
            b_prefetch_cols <= '0;
            a_prefetch_done <= 1'b0;
            b_prefetch_done <= 1'b0;
            run_m_dim      <= 16'd16;
            run_k_dim      <= 16'd16;
            run_n_dim      <= 16'd16;
            run_active_m   <= ARRAY_ROWS[7:0];
            run_active_n   <= ARRAY_COLS[7:0];
            a_loaded       <= 1'b0;
            b_loaded       <= 1'b0;
            loaded_weight_m <= '0;
            loaded_weight_k <= '0;
            loaded_vector_k <= '0;
            mvm_m_base <= '0;
            mvm_k_base <= '0;
            mvm_weight_group_base <= '0;
            mvm_stream_start <= 1'b0;
            mvm_wait_output <= 1'b0;
            mvm_done <= 1'b0;
            mvm_has_more_m_q <= 1'b0;
            mvm_cycle_count <= '0;
            for (int r = 0; r < ARRAY_ROWS; r = r + 1)
                for (int k = 0; k < TILE_K; k = k + 1)
                    a_tile_wire[r][k] <= '0;
            for (int k = 0; k < TILE_K; k = k + 1)
                for (int c = 0; c < ARRAY_COLS; c = c + 1)
                    b_tile_wire[k][c] <= '0;
        end else begin
            core_start <= 1'b0;
            mvm_stream_start <= 1'b0;
            mvm_done <= 1'b0;

            if (a_commit) begin
                if (cfg_cache_mvm) begin
                    a_loaded <= (a_packet_bytes == cfg_weight_bytes) && !packet_overflow;
                    if ((a_packet_bytes == cfg_weight_bytes) && !packet_overflow) begin
                        loaded_weight_m <= cfg_m_dim;
                        loaded_weight_k <= cfg_k_dim;
                    end
                end else begin
                    a_loaded <= 1'b1;
                end
            end
            if (b_commit) begin
                if (cfg_cache_mvm) begin
                    b_loaded <= (b_packet_bytes == cfg_k_dim) && !packet_overflow;
                    if ((b_packet_bytes == cfg_k_dim) && !packet_overflow)
                        loaded_vector_k <= cfg_k_dim;
                end else begin
                    b_loaded <= 1'b1;
                end
            end

            if (ctrl_start) begin
                run_m_dim    <= cfg_m_dim;
                run_k_dim    <= cfg_k_dim;
                run_n_dim    <= cfg_n_dim;
                run_active_m <= cfg_cache_mvm ? ARRAY_ROWS[7:0] : cfg_active_m;
                run_active_n <= cfg_cache_mvm ? 8'd1 : cfg_active_n;
                run_cache_mvm <= cfg_cache_mvm;
                mvm_cycle_count <= '0;
                mvm_wait_output <= 1'b0;
            end

            if (run_cache_mvm && (prefetch_busy || fsm_busy || stream_busy || mvm_wait_output))
                mvm_cycle_count <= mvm_cycle_count + 1'b1;

            if (mvm_wait_output && stream_done) begin
                mvm_wait_output <= 1'b0;
                prefetch_busy <= 1'b0;
                prefetch_state <= PF_IDLE;
                mvm_done <= 1'b1;
            end

            // fsm_done is a level held in ST_DONE. Do not mistake that old
            // level for completion of the next tile while it is being
            // prefetched; arm the completion event only after the controller
            // has entered an active state for this tile.
            if (prefetch_state == PF_RUN && fsm_busy)
                tile_active_seen <= 1'b1;

            case (prefetch_state)
                PF_IDLE: begin
                    prefetch_busy <= 1'b0;
                    if (ctrl_start && !invalid_shape) begin
                        prefetch_busy  <= 1'b1;
                        prefetch_state <= PF_PREP;
                        run_cache_mvm  <= cfg_cache_mvm;
                        tile_active_seen <= 1'b0;
                        a_rd_pending   <= 1'b0;
                        b_rd_pending   <= 1'b0;
                        a_prefetch_row <= '0;
                        a_prefetch_k <= '0;
                        b_prefetch_k <= '0;
                        b_prefetch_col <= '0;
                        a_prefetch_done <= 1'b0;
                        b_prefetch_done <= 1'b0;
                        if (cfg_cache_mvm) begin
                            b_loaded <= 1'b0;
                            mvm_m_base <= '0;
                            mvm_k_base <= '0;
                            mvm_weight_group_base <= '0;
                        end else begin
                            a_loaded <= 1'b0;
                            b_loaded <= 1'b0;
                        end
                        for (int r = 0; r < ARRAY_ROWS; r = r + 1)
                            for (int k = 0; k < TILE_K; k = k + 1)
                                a_tile_wire[r][k] <= '0;
                        for (int k = 0; k < TILE_K; k = k + 1)
                            for (int c = 0; c < ARRAY_COLS; c = c + 1)
                                b_tile_wire[k][c] <= '0;
                    end
                end
                PF_PREP: begin
                    mvm_has_more_m_q <= (mvm_m_remaining > ARRAY_ROWS);
                    a_prefetch_row <= '0;
                    a_prefetch_k <= '0;
                    b_prefetch_k <= '0;
                    b_prefetch_col <= '0;
                    a_prefetch_rows <= run_prefetch_m[4:0];
                    a_prefetch_k_limit <= run_tile_k_dim[4:0];
                    b_prefetch_k_limit <= run_tile_k_dim[4:0];
                    b_prefetch_cols <= run_prefetch_n[4:0];
                    a_prefetch_done <= 1'b0;
                    b_prefetch_done <= 1'b0;
                    prefetch_state <= PF_AB_REQ;
                end
                PF_AB_REQ: begin
                    if (a_rd_pending) begin
                        if (run_cache_mvm) begin
                            for (int r = 0; r < ARRAY_ROWS; r = r + 1) begin
                                if (r < a_prefetch_rows)
                                    a_tile_wire[r][a_pending_addr[3:0]] <= weight_rd_data[r];
                            end
                        end else begin
                            a_tile_wire[a_pending_addr[7:4]][a_pending_addr[3:0]] <= a_rd_data;
                        end
                    end
                    if (b_rd_pending)
                        b_tile_wire[b_pending_tile_addr[7:4]][b_pending_tile_addr[3:0]] <= b_rd_data;

                    if (!a_prefetch_done) begin
                        a_rd_pending <= 1'b1;
                        if (run_cache_mvm) begin
                            a_pending_addr <= {4'd0, a_prefetch_k};
                            if ({1'b0, a_prefetch_k} + 5'd1 >= a_prefetch_k_limit) begin
                                a_prefetch_done <= 1'b1;
                                a_prefetch_k <= '0;
                            end else begin
                                a_prefetch_k <= a_prefetch_k + 1'b1;
                            end
                        end else begin
                            a_pending_addr <= {a_prefetch_row, a_prefetch_k};
                            if (({1'b0, a_prefetch_row} + 5'd1 >= a_prefetch_rows) &&
                                ({1'b0, a_prefetch_k} + 5'd1 >= a_prefetch_k_limit)) begin
                                a_prefetch_done <= 1'b1;
                            end
                            if ({1'b0, a_prefetch_k} + 5'd1 >= a_prefetch_k_limit) begin
                                a_prefetch_k <= '0;
                                if ({1'b0, a_prefetch_row} + 5'd1 < a_prefetch_rows)
                                    a_prefetch_row <= a_prefetch_row + 1'b1;
                            end else begin
                                a_prefetch_k <= a_prefetch_k + 1'b1;
                            end
                        end
                    end else begin
                        a_rd_pending <= 1'b0;
                    end

                    if (!b_prefetch_done) begin
                        b_rd_pending <= 1'b1;
                        b_pending_tile_addr <= {b_prefetch_k, b_prefetch_col};
                        if (({1'b0, b_prefetch_k} + 5'd1 >= b_prefetch_k_limit) &&
                            ({1'b0, b_prefetch_col} + 5'd1 >= b_prefetch_cols)) begin
                            b_prefetch_done <= 1'b1;
                        end
                        if ({1'b0, b_prefetch_col} + 5'd1 >= b_prefetch_cols) begin
                            b_prefetch_col <= '0;
                            if ({1'b0, b_prefetch_k} + 5'd1 < b_prefetch_k_limit)
                                b_prefetch_k <= b_prefetch_k + 1'b1;
                        end else begin
                            b_prefetch_col <= b_prefetch_col + 1'b1;
                        end
                    end else begin
                        b_rd_pending <= 1'b0;
                    end

                    if (a_prefetch_done && b_prefetch_done &&
                        !a_rd_pending && !b_rd_pending)
                        prefetch_state <= PF_START;
                end
                PF_START: begin
                    core_start     <= 1'b1;
                    prefetch_state <= PF_RUN;
                end
                PF_RUN: begin
                    if (fsm_done && tile_active_seen) begin
                        tile_active_seen <= 1'b0;
                        if (run_cache_mvm && (mvm_k_base + run_tile_k_dim < run_k_dim)) begin
                            mvm_k_base <= mvm_k_base + run_tile_k_dim;
                            prefetch_state <= PF_PREP;
                        end else if (run_cache_mvm) begin
                            // Commit this completed M tile before advancing.
                            // Streaming waits until all M tiles are resident.
                            prefetch_state <= PF_COMMIT;
                        end else begin
                            prefetch_busy  <= 1'b0;
                            prefetch_state <= PF_IDLE;
                        end
                    end
                end
                PF_COMMIT: begin
                    if (mvm_has_more_m_q) begin
                        mvm_m_base <= mvm_m_base + run_tile_m_dim;
                        mvm_k_base <= '0;
                        mvm_weight_group_base <= mvm_weight_group_base + run_k_dim;
                        prefetch_state <= PF_PREP;
                    end else begin
                        prefetch_busy <= 1'b0;
                        // The complete vector is available after this edge.
                        mvm_stream_start <= 1'b1;
                        mvm_wait_output <= 1'b1;
                        prefetch_state <= PF_RUN;
                    end
                end
                default: prefetch_state <= PF_IDLE;
            endcase
        end
    end

    // K tiles accumulate in this 16-row bank. Once the K reduction is complete,
    // PF_COMMIT copies the tile into mvm_result_bank; the full vector streams
    // only after all M tiles have been computed.
    always_ff @(posedge clk) begin
        if (combined_rst_n && run_cache_mvm && c_capture) begin
            for (int r = 0; r < ARRAY_ROWS; r = r + 1) begin
                if (r < run_tile_m_dim) begin
                    if (mvm_k_base == 0)
                        mvm_result_tile[r] <=
                            $signed(c_mesh_out[r][0]);
                    else
                        mvm_result_tile[r] <=
                            $signed(mvm_result_tile[r]) +
                            $signed(c_mesh_out[r][0]);
                end
            end
        end
    end

    for (genvar result_row = 0; result_row < ARRAY_ROWS; result_row = result_row + 1) begin : gen_mvm_result_write_data
        assign mvm_result_wr_data[result_row] = mvm_result_tile[result_row];
    end
    assign mvm_rd_data = mvm_result_rd_data[c_rd_addr[3:0]];

    // ------------------------------------------------------------------------
    // 1. AXI4-Lite Register Block
    // ------------------------------------------------------------------------
    axi_lite_regs #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH)
    ) u_regs (
        .s_axi_aclk      (clk),
        .s_axi_aresetn   (rst_n),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awprot    (s_axi_awprot),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),
        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wready    (s_axi_wready),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arprot    (s_axi_arprot),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arready   (s_axi_arready),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready),
        .ctrl_start      (ctrl_start),
        .ctrl_soft_reset (ctrl_soft_reset),
        .cfg_m_dim       (cfg_m_dim),
        .cfg_k_dim       (cfg_k_dim),
        .cfg_n_dim       (cfg_n_dim),
        .cfg_active_m    (cfg_active_m),
        .cfg_active_n    (cfg_active_n),
        .cfg_cache_mvm   (cfg_cache_mvm),
        .cfg_stream_target_manual (cfg_stream_target_manual),
        .cfg_stream_target (cfg_stream_target),
        .status_busy     (accelerator_busy),
        .status_done     (accelerator_done),
        .status_overflow (accelerator_overflow),
        .status_invalid  (invalid_shape),
        .status_a_loaded (a_loaded),
        .status_b_loaded (b_loaded),
        .hw_cycles       (axis_cycles),
        .hw_tiles        (hw_tiles)
    );

    // ------------------------------------------------------------------------
    // 2. AXI4-Stream Slave In Adapter
    // ------------------------------------------------------------------------
    axis_in_adapter #(
        .AXIS_DATA_WIDTH (AXIS_DATA_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .A_ADDR_WIDTH    (WEIGHT_ADDR_WIDTH),
        .B_ADDR_WIDTH    (9),
        .A_DEPTH_BYTES   (WEIGHT_CACHE_DEPTH),
        .B_DEPTH_BYTES   (MAX_MVM_K)
    ) u_axis_in (
        .clk           (clk),
        .rst_n         (combined_rst_n),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tkeep  (s_axis_tkeep),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        .load_enable   (axis_load_enable),
        .stream_target_manual (cfg_stream_target_manual),
        .stream_target (cfg_stream_target),
        .a_wr_en       (a_wr_en),
        .a_wr_addr     (a_wr_addr),
        .a_wr_data     (a_wr_data),
        .b_wr_en       (b_wr_en),
        .b_wr_addr     (b_wr_addr),
        .b_wr_data     (b_wr_data),
        .a_commit      (a_commit),
        .b_commit      (b_commit),
        .a_packet_bytes (a_packet_bytes),
        .b_packet_bytes (b_packet_bytes),
        .packet_overflow (packet_overflow),
        .load_active   (),
        .load_complete ()
    );

    // ------------------------------------------------------------------------
    // 3. Ping-pong tile buffers A and B
    // ------------------------------------------------------------------------
    ping_pong_bram #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(256), .ADDR_WIDTH(8)) u_a_pingpong (
        .clk(clk), .rst_n(combined_rst_n),
        .wr_en(a_wr_en && !cfg_cache_mvm), .wr_addr(a_wr_addr[7:0]),
        .wr_data(a_wr_data), .commit(a_commit && !cfg_cache_mvm),
        .rd_en(a_rd_en), .rd_addr(a_rd_addr), .rd_data(a_rd_data), .active_bank(a_active_bank)
    );
    ping_pong_bram #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(MAX_MVM_K), .ADDR_WIDTH(9)) u_b_pingpong (
        .clk(clk), .rst_n(combined_rst_n),
        .wr_en(b_wr_en), .wr_addr(b_wr_addr), .wr_data(b_wr_data), .commit(b_commit),
        .rd_en(b_rd_en), .rd_addr(b_rd_addr), .rd_data(b_rd_data), .active_bank(b_active_bank)
    );
    weight_bram_cache #(
        .MAX_ROWS       (MAX_MVM_ROWS),
        .MAX_K          (MAX_MVM_K),
        .ROW_BANKS      (ARRAY_ROWS),
        .DEPTH_BYTES    (WEIGHT_CACHE_DEPTH),
        .ADDR_WIDTH     (WEIGHT_ADDR_WIDTH),
        .BANK_DEPTH_BYTES (WEIGHT_BANK_DEPTH),
        .BANK_ADDR_WIDTH (WEIGHT_BANK_ADDR_WIDTH)
    ) u_weight_cache (
        .clk     (clk),
        .load_k  (cfg_k_dim),
        .wr_en   (a_wr_en && cfg_cache_mvm),
        .wr_addr (a_wr_addr),
        .wr_data (a_wr_data),
        .rd_en   (weight_rd_en),
        .rd_addr (weight_rd_addr),
        .rd_data (weight_rd_data)
    );

    mvm_result_bram #(
        .DATA_WIDTH (32),
        .BANKS      (ARRAY_ROWS),
        .DEPTH      (MVM_RESULT_BANK_DEPTH),
        .ADDR_WIDTH (MVM_RESULT_BANK_ADDR_WIDTH)
    ) u_mvm_result_cache (
        .clk       (clk),
        .wr_en     (run_cache_mvm && (prefetch_state == PF_COMMIT)),
        .wr_addr   (mvm_m_base[MVM_RESULT_BANK_ADDR_WIDTH+3:4]),
        .wr_data   (mvm_result_wr_data),
        .rd_en     (run_cache_mvm),
        .rd_addr   (c_rd_addr[4 +: MVM_RESULT_BANK_ADDR_WIDTH]),
        .rd_data   (mvm_result_rd_data)
    );

    // ------------------------------------------------------------------------
    // 4. Tile Controller (FSM, Tiling, Zero-Padding, Active Region)
    // ------------------------------------------------------------------------
    single_tile_controller #(
        .ARRAY_ROWS (ARRAY_ROWS),
        .ARRAY_COLS (ARRAY_COLS),
        .TILE_K     (TILE_K),
        .WAIT_FOR_CAPTURE(1'b1)
    ) u_controller (
        .clk            (clk),
        .rst_n          (combined_rst_n),
        .start          (core_start),
        .soft_reset     (ctrl_soft_reset),
        .m_dim          (run_cache_mvm ? {8'd0, run_tile_m_dim} : run_m_dim),
        .k_dim          (run_cache_mvm ? {8'd0, run_tile_k_dim} : run_k_dim),
        .n_dim          (run_cache_mvm ? {8'd0, run_tile_n_dim} : run_n_dim),
        .active_m_in    (run_active_m),
        .active_n_in    (run_active_n),
        .busy           (fsm_busy),
        .done           (fsm_done),
        .load_en        (load_en),
        .shift_en       (shift_en),
        .array_en       (array_en),
        .clr_acc        (clr_acc),
        .c_capture      (c_capture),
        .capture_done   (run_cache_mvm || c_buf_capture_done),
        .active_mask    (active_mask),
        .curr_mt        (curr_mt),
        .curr_nt        (curr_nt),
        .curr_kt        (curr_kt),
        .actual_m       (actual_m),
        .actual_k       (actual_k),
        .actual_n       (actual_n),
        .cycles_counter (hw_cycles),
        .tiles_counter  (hw_tiles)
    );

    // ------------------------------------------------------------------------
    // 5. Adaptive Skew Buffers
    // ------------------------------------------------------------------------
    skew_buffers #(
        .ARRAY_ROWS (ARRAY_ROWS),
        .ARRAY_COLS (ARRAY_COLS),
        .TILE_K     (TILE_K),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_skew (
        .clk        (clk),
        .rst_n      (combined_rst_n),
        .load_en    (load_en),
        .shift_en   (shift_en),
        .actual_m   (skew_actual_m),
        .actual_k   (actual_k),
        .actual_n   (skew_actual_n),
        .a_tile_in  (a_tile_wire),
        .b_tile_in  (b_tile_wire),
        .a_skewed_o (a_skewed),
        .b_skewed_o (b_skewed)
    );

    // ------------------------------------------------------------------------
    // 6. 2D Systolic Array Mesh
    // ------------------------------------------------------------------------
    systolic_array #(
        .ARRAY_ROWS (ARRAY_ROWS),
        .ARRAY_COLS (ARRAY_COLS),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .MAC_IMPL   (MAC_IMPL),
        .DSP_PE_LIMIT(DSP_PE_LIMIT),
        .MASK_AT_INGRESS(1'b1),
        .TRACK_OVERFLOW(!((DATA_WIDTH == 8) && (ACC_WIDTH == 20) && (TILE_K <= 16)))
    ) u_systolic_mesh (
        .clk         (clk),
        .rst_n       (combined_rst_n),
        .clr_acc     (clr_acc),
        .array_en    (array_en),
        .active_mask (active_mask),
        .a_in        (a_skewed),
        .b_in        (b_skewed),
        .c_out       (c_mesh_out),
        .overflow    (overflow_flag)
    );

    // ------------------------------------------------------------------------
    // 7. Matrix C Result Buffer
    // ------------------------------------------------------------------------
    c_buf #(
        .ARRAY_ROWS (ARRAY_ROWS),
        .ARRAY_COLS (ARRAY_COLS),
        .ACC_WIDTH  (ACC_WIDTH)
    ) u_c_buf (
        .clk        (clk),
        .rst_n      (combined_rst_n),
        .capture_en (c_capture && !run_cache_mvm),
        .c_matrix_i (c_mesh_out),
        .capture_done(c_buf_capture_done),
        .rd_addr    (c_rd_addr[7:0]),
        .rd_en      (1'b1),
        .rd_data    (c_rd_data)
    );

    // ------------------------------------------------------------------------
    // 8. AXI4-Stream Master Out Adapter
    // ------------------------------------------------------------------------
    axis_out_adapter #(
        .AXIS_DATA_WIDTH (AXIS_DATA_WIDTH),
        .ACC_WIDTH       (ACC_WIDTH),
        .ARRAY_ROWS      (ARRAY_ROWS),
        .ARRAY_COLS      (ARRAY_COLS),
        .MAX_VECTOR_ROWS (MAX_MVM_ROWS)
    ) u_axis_out (
        .clk          (clk),
        .rst_n        (combined_rst_n),
        .start_stream (run_cache_mvm ? mvm_stream_start : c_buf_capture_done),
        .active_rows  (run_cache_mvm ? run_m_dim[9:0] : {2'b00, actual_m}),
        .active_cols  (actual_n),
        .vector_mode  (run_cache_mvm),
        .final_stream_tile (1'b1),
        .stream_busy  (stream_busy),
        .stream_done  (stream_done),
        .c_rd_addr    (c_rd_addr),
        .c_rd_data    (c_rd_data),
        .vector_rd_data (mvm_rd_data),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tkeep (m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast)
    );

    // Interrupt output: pulses when matrix multiplication finishes
    assign interrupt = accelerator_done;

endmodule

`default_nettype wire
