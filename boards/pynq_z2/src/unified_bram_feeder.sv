`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: unified_bram_feeder.sv
// Description: Unified True Dual-Port Block RAM Matrix Feeder for Option 2.
//              - Receives AXI4-Stream MM2S data from a Single AXI DMA channel.
//              - Assembles incoming 32-bit beats into 128-bit wide rows.
//              - Implements dual ping-pong banks using dedicated Block RAM.
//              - Concurrently drives Port A (Engine 0) and Port B (Engine 1).
//              - Eliminates redundant DMA channels and inter-engine routing congestion.
// ============================================================================

module unified_bram_feeder #(
    parameter int ARRAY_ROWS      = 16,
    parameter int ARRAY_COLS      = 16,
    parameter int TILE_K          = 16,
    parameter int DATA_WIDTH      = 8,
    parameter int AXIS_DATA_WIDTH = 32
)(
    input  wire                                clk,
    input  wire                                rst_n,
    input  wire                                soft_reset,

    // AXI4-Stream Slave Interface (from Single AXI DMA MM2S)
    input  wire [AXIS_DATA_WIDTH-1:0]          s_axis_tdata,
    input  wire [(AXIS_DATA_WIDTH/8)-1:0]      s_axis_tkeep,
    input  wire                                s_axis_tvalid,
    output wire                                s_axis_tready,
    input  wire                                s_axis_tlast,

    // Configuration / Dimensions
    input  wire [15:0]                         cfg_m_dim,
    input  wire [15:0]                         cfg_k_dim,
    input  wire [15:0]                         cfg_n_dim,
    input  wire [7:0]                          cfg_active_m,
    input  wire [7:0]                          cfg_active_n,

    // Core Compute Handshake
    input  wire                                core_busy,
    input  wire                                core_done,
    output logic                               core_start,

    // Dedicated Parallel Feeder Ports to Engine 0 and Engine 1
    output wire signed [DATA_WIDTH-1:0]        a_tile_0 [0:ARRAY_ROWS-1][0:TILE_K-1],
    output wire signed [DATA_WIDTH-1:0]        b_tile_0 [0:TILE_K-1][0:ARRAY_COLS-1],
    output wire signed [DATA_WIDTH-1:0]        a_tile_1 [0:ARRAY_ROWS-1][0:TILE_K-1],
    output wire signed [DATA_WIDTH-1:0]        b_tile_1 [0:TILE_K-1][0:ARRAY_COLS-1],

    output logic                               feeder_busy,
    output wire                                feeder_ready,
    output wire                                tile_ready
);

    // ------------------------------------------------------------------------
    // Ping-Pong Memory Banks (Block RAM Backed)
    // Each bank stores:
    //   Indices  0..15: Matrix A0 (16 rows x 128 bits)
    //   Indices 16..31: Matrix B0 (16 cols x 128 bits)
    //   Indices 32..47: Matrix A1 (16 rows x 128 bits)
    //   Indices 48..63: Matrix B1 (16 cols x 128 bits)
    // ------------------------------------------------------------------------
    localparam int BRAM_DEPTH = 64;
    localparam int ROW_BITS   = ARRAY_COLS * DATA_WIDTH; // 128 bits

    (* ram_style = "block" *) logic [ROW_BITS-1:0] bram_bank0 [0:BRAM_DEPTH-1];
    (* ram_style = "block" *) logic [ROW_BITS-1:0] bram_bank1 [0:BRAM_DEPTH-1];

    // Bank Ping-Pong status
    logic wr_bank;
    logic rd_bank;
    logic bank_ready [0:1];

    logic wr_bank_ready_pulse;
    logic wr_bank_ready_idx;
    logic rd_bank_clear_pulse;
    logic rd_bank_clear_idx;

    // ------------------------------------------------------------------------
    // Stream Ingestion State Machine
    // ------------------------------------------------------------------------
    logic [1:0]  beat_cnt;
    logic [5:0]  entry_idx;
    logic [ROW_BITS-1:0] assemble_reg;
    logic        wr_en;
    logic [5:0]  wr_addr;
    logic [ROW_BITS-1:0] wr_data;

    wire combined_rst_n = rst_n && !soft_reset;

    logic wr_bank_d;

    // Single procedural block for bank_ready to eliminate multi-driven net warnings/errors
    always_ff @(posedge clk) begin
        if (!combined_rst_n) begin
            bank_ready[0] <= 1'b0;
            bank_ready[1] <= 1'b0;
        end else begin
            if (wr_bank_ready_pulse)
                bank_ready[wr_bank_ready_idx] <= 1'b1;
            if (rd_bank_clear_pulse)
                bank_ready[rd_bank_clear_idx] <= 1'b0;
        end
    end

    // Ready to receive if the current write bank is not waiting to be read
    assign s_axis_tready = combined_rst_n && !bank_ready[wr_bank] &&
                          !(read_en && wr_bank == rd_bank);

    always_ff @(posedge clk) begin
        if (!combined_rst_n) begin
            beat_cnt            <= 2'd0;
            entry_idx           <= 6'd0;
            assemble_reg        <= '0;
            wr_en               <= 1'b0;
            wr_addr             <= 6'd0;
            wr_data             <= '0;
            wr_bank             <= 1'b0;
            wr_bank_d           <= 1'b0;
            wr_bank_ready_pulse <= 1'b0;
            wr_bank_ready_idx   <= 1'b0;
        end else begin
            wr_en               <= 1'b0;
            wr_bank_ready_pulse <= 1'b0;

            if (s_axis_tvalid && s_axis_tready) begin
                // Pack 32-bit beat into 128-bit row buffer (little-endian byte packing)
                case (beat_cnt)
                    2'd0: assemble_reg[31:0]   <= s_axis_tdata;
                    2'd1: assemble_reg[63:32]  <= s_axis_tdata;
                    2'd2: assemble_reg[95:64]  <= s_axis_tdata;
                    2'd3: assemble_reg[127:96] <= s_axis_tdata;
                endcase

                if (beat_cnt == 2'd3) begin
                    beat_cnt  <= 2'd0;
                    wr_en     <= 1'b1;
                    wr_addr   <= entry_idx;
                    wr_data   <= {s_axis_tdata, assemble_reg[95:0]};
                    wr_bank_d <= wr_bank;

                    if (s_axis_tlast || entry_idx == 6'd63) begin
                        entry_idx           <= 6'd0;
                        wr_bank_ready_pulse <= 1'b1;
                        wr_bank_ready_idx   <= wr_bank;
                        wr_bank             <= ~wr_bank;
                    end else begin
                        entry_idx <= entry_idx + 6'd1;
                    end
                end else begin
                    beat_cnt <= beat_cnt + 2'd1;
                    if (s_axis_tlast) begin
                        // Early TLAST packet boundary
                        wr_en     <= 1'b1;
                        wr_addr   <= entry_idx;
                        wr_bank_d <= wr_bank;
                        case (beat_cnt)
                            2'd0: wr_data <= {96'd0, s_axis_tdata};
                            2'd1: wr_data <= {64'd0, s_axis_tdata, assemble_reg[31:0]};
                            2'd2: wr_data <= {32'd0, s_axis_tdata, assemble_reg[63:0]};
                            default: wr_data <= assemble_reg;
                        endcase
                        beat_cnt            <= 2'd0;
                        entry_idx           <= 6'd0;
                        wr_bank_ready_pulse <= 1'b1;
                        wr_bank_ready_idx   <= wr_bank;
                        wr_bank             <= ~wr_bank;
                    end
                end
            end
        end
    end

    // Each bank has exactly two physical ports. Port A is time-multiplexed
    // between ingestion and Engine 0 prefetch; Port B reads Engine 1.
    typedef enum logic [1:0] {
        PF_IDLE = 2'd0, PF_READ = 2'd1, PF_WAIT_RUN = 2'd2
    } pf_state_t;
    pf_state_t pf_state;
    logic [5:0] pf_step;
    wire read_en = combined_rst_n && pf_state == PF_READ && pf_step < 6'd32;
    wire [5:0] addr_e0 = pf_step;
    wire [5:0] addr_e1 = 6'd32 + pf_step;
    logic [ROW_BITS-1:0] bank0_e0_q, bank0_e1_q, bank1_e0_q, bank1_e1_q;
    wire [ROW_BITS-1:0] data_e0_q = rd_bank ? bank1_e0_q : bank0_e0_q;
    wire [ROW_BITS-1:0] data_e1_q = rd_bank ? bank1_e1_q : bank0_e1_q;

    always_ff @(posedge clk) begin
        if (wr_en && !wr_bank_d)
            bram_bank0[wr_addr] <= wr_data;
        else if (read_en && !rd_bank)
            bank0_e0_q <= bram_bank0[addr_e0];
    end
    always_ff @(posedge clk) begin
        if (read_en && !rd_bank)
            bank0_e1_q <= bram_bank0[addr_e1];
    end
    always_ff @(posedge clk) begin
        if (wr_en && wr_bank_d)
            bram_bank1[wr_addr] <= wr_data;
        else if (read_en && rd_bank)
            bank1_e0_q <= bram_bank1[addr_e0];
    end
    always_ff @(posedge clk) begin
        if (read_en && rd_bank)
            bank1_e1_q <= bram_bank1[addr_e1];
    end

    // Pipeline registers for capturing rows and columns into parallel arrays
    logic signed [DATA_WIDTH-1:0] a0_wire [0:ARRAY_ROWS-1][0:TILE_K-1];
    logic signed [DATA_WIDTH-1:0] b0_wire [0:TILE_K-1][0:ARRAY_COLS-1];
    logic signed [DATA_WIDTH-1:0] a1_wire [0:ARRAY_ROWS-1][0:TILE_K-1];
    logic signed [DATA_WIDTH-1:0] b1_wire [0:TILE_K-1][0:ARRAY_COLS-1];

    always_ff @(posedge clk) begin
        if (!combined_rst_n) begin
            pf_state            <= PF_IDLE;
            pf_step             <= 6'd0;
            rd_bank             <= 1'b0;
            core_start          <= 1'b0;
            feeder_busy         <= 1'b0;
            rd_bank_clear_pulse <= 1'b0;
            rd_bank_clear_idx   <= 1'b0;
            for (int r = 0; r < ARRAY_ROWS; r = r + 1) begin
                for (int k = 0; k < TILE_K; k = k + 1) begin
                    a0_wire[r][k] <= '0;
                    b0_wire[r][k] <= '0;
                    a1_wire[r][k] <= '0;
                    b1_wire[r][k] <= '0;
                end
            end
        end else begin
            core_start          <= 1'b0;
            rd_bank_clear_pulse <= 1'b0;

            case (pf_state)
                PF_IDLE: begin
                    feeder_busy <= 1'b0;
                    if (bank_ready[rd_bank] && !core_busy) begin
                        pf_state    <= PF_READ;
                        pf_step     <= 6'd0;
                        feeder_busy <= 1'b1;
                    end
                end

                PF_READ: begin
                    feeder_busy <= 1'b1;
                    pf_step     <= pf_step + 6'd1;

                    // Due to 1-cycle BRAM latency, data for address s arrives at pf_step = s + 1
                    if (pf_step >= 6'd1 && pf_step <= 6'd16) begin
                        // Latch Matrix A rows (0..15)
                        for (int c = 0; c < 16; c = c + 1) begin
                            a0_wire[pf_step - 6'd1][c] <= data_e0_q[c*8 +: 8];
                            a1_wire[pf_step - 6'd1][c] <= data_e1_q[c*8 +: 8];
                        end
                    end else if (pf_step >= 6'd17 && pf_step <= 6'd32) begin
                        // Latch Matrix B columns (0..15)
                        for (int k = 0; k < 16; k = k + 1) begin
                            b0_wire[k][pf_step - 6'd17] <= data_e0_q[k*8 +: 8];
                            b1_wire[k][pf_step - 6'd17] <= data_e1_q[k*8 +: 8];
                        end
                    end

                    // At step 32, all 4 matrices (A0, B0, A1, B1) are fully captured!
                    if (pf_step == 6'd32) begin
                        core_start          <= 1'b1;
                        rd_bank_clear_pulse <= 1'b1;
                        rd_bank_clear_idx   <= rd_bank;
                        rd_bank             <= ~rd_bank;
                        pf_state            <= PF_WAIT_RUN;
                    end
                end

                PF_WAIT_RUN: begin
                    core_start <= 1'b0;
                    if (core_done) begin
                        pf_state    <= PF_IDLE;
                        feeder_busy <= 1'b0;
                    end
                end

                default: pf_state <= PF_IDLE;
            endcase
        end
    end

    assign a_tile_0 = a0_wire;
    assign b_tile_0 = b0_wire;
    assign a_tile_1 = a1_wire;
    assign b_tile_1 = b1_wire;
    assign feeder_ready = bank_ready[rd_bank];
    // Packet completion and parallel-tile completion are different events.
    // Preserve the loaded status while protecting manual compute requests.
    assign tile_ready = bank_ready[rd_bank] && pf_state == PF_WAIT_RUN;

endmodule

`default_nettype wire
