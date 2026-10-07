`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: accel_dual_engine_top.sv
// Description: Unified Dual-Engine Systolic Matrix Accelerator for PYNQ-Z2
//              (Option 2 — Optimized Architecture).
//
// Key Architectural Pillars (PRD.md):
// 1. Total Compute Power: 512 physical MAC units across dual 16x16 meshes.
// 2. Symmetrical DSP Partitioning (Plan B): Exactly 110 DSP48E1 slices per
//    engine (110 Engine 0 + 110 Engine 1 = 220 total DSPs, 100% capacity).
// 3. Unified True Dual-Port BRAM Feeder (Plan C): Single AXI DMA MM2S stream
//    feeding both Engine 0 (Port A) and Engine 1 (Port B) concurrently.
// 4. Memory Offloading to Dedicated Block RAM (Plan A): Zero distributed LUT RAM
//    for matrix storage or tile buffers; all mapped with (* ram_style = "block" *).
// 5. Result Draining & Streaming: Sequential drain of C0 then C1 with INT32
//    sign extension over single AXI DMA S2MM stream with tlast on final word.
// ============================================================================

module accel_dual_engine_top #(
    parameter int ARRAY_ROWS      = 16,
    parameter int ARRAY_COLS      = 16,
    parameter int TILE_K          = 16,
    parameter int DATA_WIDTH      = 8,
    parameter int ACC_WIDTH       = 20,
    parameter int DSP_PE_LIMIT_0  = 110,
    parameter int DSP_PE_LIMIT_1  = 110,
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_DATA_WIDTH  = 32,
    parameter int AXIS_DATA_WIDTH = 32
)(
    // System Clock and Active-Low Synchronous Reset
    input  wire                                clk,
    input  wire                                rst_n,

    // ------------------------------------------------------------------------
    // AXI4-Lite Slave Interface (Control & Status)
    // ------------------------------------------------------------------------
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

    // ------------------------------------------------------------------------
    // AXI4-Stream Slave Interface (Matrix Data In: A0, B0, A1, B1 from DMA MM2S)
    // ------------------------------------------------------------------------
    input  wire [AXIS_DATA_WIDTH-1:0]          s_axis_tdata,
    input  wire [(AXIS_DATA_WIDTH/8)-1:0]      s_axis_tkeep,
    input  wire                                s_axis_tvalid,
    output logic                               s_axis_tready,
    input  wire                                s_axis_tlast,

    // ------------------------------------------------------------------------
    // AXI4-Stream Master Interface (Matrix Data Out: C0 then C1 to DMA S2MM)
    // ------------------------------------------------------------------------
    output logic [AXIS_DATA_WIDTH-1:0]         m_axis_tdata,
    output logic [(AXIS_DATA_WIDTH/8)-1:0]     m_axis_tkeep,
    output logic                               m_axis_tvalid,
    input  wire                                m_axis_tready,
    output logic                               m_axis_tlast,

    // ------------------------------------------------------------------------
    // Hardware Interrupt to Zynq Processing System (IRQ_F2P)
    // ------------------------------------------------------------------------
    output logic                               interrupt
);

    // ------------------------------------------------------------------------
    // Internal Interconnect Signals
    // ------------------------------------------------------------------------
    wire        ctrl_start;
    wire        ctrl_soft_reset;
    wire [15:0] cfg_m_dim;
    wire [15:0] cfg_k_dim;
    wire [15:0] cfg_n_dim;
    wire [7:0]  cfg_active_m;
    wire [7:0]  cfg_active_n;
    wire        cfg_cache_mvm;
    wire        cfg_stream_target_manual;
    wire        cfg_stream_target;

    wire        combined_rst_n = rst_n && !ctrl_soft_reset;

    // Feeder signals
    wire        feeder_busy;
    wire        feeder_ready;
    wire        feeder_tile_ready;
    wire        feeder_start;
    wire signed [DATA_WIDTH-1:0] a_tile_0 [0:ARRAY_ROWS-1][0:TILE_K-1];
    wire signed [DATA_WIDTH-1:0] b_tile_0 [0:TILE_K-1][0:ARRAY_COLS-1];
    wire signed [DATA_WIDTH-1:0] a_tile_1 [0:ARRAY_ROWS-1][0:TILE_K-1];
    wire signed [DATA_WIDTH-1:0] b_tile_1 [0:TILE_K-1][0:ARRAY_COLS-1];

    // Compute core signals
    wire        core_busy;
    wire        core_done;
    wire        core_ovf_0;
    wire        core_ovf_1;
    wire        core_invalid;
    wire [31:0] core_cycles;
    wire [31:0] core_tiles;
    wire signed [ACC_WIDTH-1:0] c_tile_0 [0:ARRAY_ROWS-1][0:ARRAY_COLS-1];
    wire signed [ACC_WIDTH-1:0] c_tile_1 [0:ARRAY_ROWS-1][0:ARRAY_COLS-1];

    // C Buffer signals
    wire        c_capture_done_0;
    wire        c_capture_done_1;
    wire [7:0]  c0_rd_addr;
    wire signed [ACC_WIDTH-1:0] c0_rd_data;
    wire [7:0]  c1_rd_addr;
    wire signed [ACC_WIDTH-1:0] c1_rd_data;

    // Output adapter signals
    wire        stream_busy;
    wire        stream_done;
    logic       job_pending_q;
    logic [7:0] job_active_m_q, job_active_n_q;
    wire c0_rd_en, c1_rd_en;

    // Effective start trigger (either AXI-Lite manual start or auto-start from feeder)
    wire effective_core_start = (feeder_start || (ctrl_start && feeder_tile_ready)) &&
                                !job_pending_q && !core_busy && !core_invalid;
    always_ff @(posedge clk) begin
        if (!combined_rst_n) begin
            job_pending_q <= 1'b0;
            job_active_m_q <= ARRAY_ROWS;
            job_active_n_q <= ARRAY_COLS;
        end else begin
            if (stream_done) job_pending_q <= 1'b0;
            if (effective_core_start) begin
                job_pending_q <= 1'b1;
                job_active_m_q <= cfg_active_m;
                job_active_n_q <= cfg_active_n;
            end
        end
    end

    // ------------------------------------------------------------------------
    // 1. AXI4-Lite Register File (Control & Status)
    // ------------------------------------------------------------------------
    axi_lite_regs #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH)
    ) u_regs (
        .s_axi_aclk               (clk),
        .s_axi_aresetn            (rst_n),
        .s_axi_awaddr             (s_axi_awaddr),
        .s_axi_awprot             (s_axi_awprot),
        .s_axi_awvalid            (s_axi_awvalid),
        .s_axi_awready            (s_axi_awready),
        .s_axi_wdata              (s_axi_wdata),
        .s_axi_wstrb              (s_axi_wstrb),
        .s_axi_wvalid             (s_axi_wvalid),
        .s_axi_wready             (s_axi_wready),
        .s_axi_bresp              (s_axi_bresp),
        .s_axi_bvalid             (s_axi_bvalid),
        .s_axi_bready             (s_axi_bready),
        .s_axi_araddr             (s_axi_araddr),
        .s_axi_arprot             (s_axi_arprot),
        .s_axi_arvalid            (s_axi_arvalid),
        .s_axi_arready            (s_axi_arready),
        .s_axi_rdata              (s_axi_rdata),
        .s_axi_rresp              (s_axi_rresp),
        .s_axi_rvalid             (s_axi_rvalid),
        .s_axi_rready             (s_axi_rready),
        .ctrl_start               (ctrl_start),
        .ctrl_soft_reset          (ctrl_soft_reset),
        .cfg_m_dim                (cfg_m_dim),
        .cfg_k_dim                (cfg_k_dim),
        .cfg_n_dim                (cfg_n_dim),
        .cfg_active_m             (cfg_active_m),
        .cfg_active_n             (cfg_active_n),
        .cfg_cache_mvm            (cfg_cache_mvm),
        .cfg_stream_target_manual (cfg_stream_target_manual),
        .cfg_stream_target        (cfg_stream_target),
        .status_busy              (job_pending_q || core_busy || stream_busy || feeder_busy),
        .status_done              (stream_done),
        .status_overflow          (core_ovf_0 || core_ovf_1),
        .status_invalid           (core_invalid),
        .status_a_loaded          (feeder_ready),
        .status_b_loaded          (feeder_ready),
        .hw_cycles                (core_cycles),
        .hw_tiles                 (core_tiles)
    );

    // ------------------------------------------------------------------------
    // 2. Unified True Dual-Port Block RAM Matrix Feeder (Plan C + Plan A)
    // ------------------------------------------------------------------------
    unified_bram_feeder #(
        .ARRAY_ROWS      (ARRAY_ROWS),
        .ARRAY_COLS      (ARRAY_COLS),
        .TILE_K          (TILE_K),
        .DATA_WIDTH      (DATA_WIDTH),
        .AXIS_DATA_WIDTH (AXIS_DATA_WIDTH)
    ) u_feeder (
        .clk          (clk),
        .rst_n        (rst_n),
        .soft_reset   (ctrl_soft_reset),
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tkeep (s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast (s_axis_tlast),
        .cfg_m_dim    (cfg_m_dim),
        .cfg_k_dim    (cfg_k_dim),
        .cfg_n_dim    (cfg_n_dim),
        .cfg_active_m (cfg_active_m),
        .cfg_active_n (cfg_active_n),
        .core_busy    (job_pending_q || core_busy),
        .core_done    (stream_done),
        .core_start   (feeder_start),
        .a_tile_0     (a_tile_0),
        .b_tile_0     (b_tile_0),
        .a_tile_1     (a_tile_1),
        .b_tile_1     (b_tile_1),
        .feeder_busy  (feeder_busy),
        .feeder_ready (feeder_ready),
        .tile_ready   (feeder_tile_ready)
    );

    // ------------------------------------------------------------------------
    // 3. Dual-Engine Systolic Compute Core (512 MACs, Symmetrical 110/110 DSPs)
    // ------------------------------------------------------------------------
    accel_dual_tile_core #(
        .ARRAY_ROWS     (ARRAY_ROWS),
        .ARRAY_COLS     (ARRAY_COLS),
        .TILE_K         (TILE_K),
        .DATA_WIDTH     (DATA_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .DSP_PE_LIMIT_0 (DSP_PE_LIMIT_0),
        .DSP_PE_LIMIT_1 (DSP_PE_LIMIT_1),
        .DSP_PE_LIMIT   (DSP_PE_LIMIT_0)
    ) u_compute_core (
        .clk            (clk),
        .rst_n          (combined_rst_n),
        .start          (effective_core_start),
        .m_dim          (cfg_m_dim),
        .k_dim          (cfg_k_dim),
        .n_dim          (cfg_n_dim),
        .active_m       (cfg_active_m),
        .active_n       (cfg_active_n),
        .a_tile_0       (a_tile_0),
        .b_tile_0       (b_tile_0),
        .a_tile_1       (a_tile_1),
        .b_tile_1       (b_tile_1),
        .c_tile_0       (c_tile_0),
        .c_tile_1       (c_tile_1),
        .busy           (core_busy),
        .done           (core_done),
        .overflow_0     (core_ovf_0),
        .overflow_1     (core_ovf_1),
        .invalid_shape  (core_invalid),
        .cycles_counter (core_cycles),
        .tiles_counter  (core_tiles)
    );

    // ------------------------------------------------------------------------
    // 4. Matrix C Result Buffers (Block RAM Backed)
    // ------------------------------------------------------------------------
    c_buf #(
        .ARRAY_ROWS (ARRAY_ROWS),
        .ARRAY_COLS (ARRAY_COLS),
        .ACC_WIDTH  (ACC_WIDTH),
        .GATE_READS (1'b1)
    ) u_c_buf_0 (
        .clk         (clk),
        .rst_n       (combined_rst_n),
        .capture_en  (core_done),
        .c_matrix_i  (c_tile_0),
        .capture_done(c_capture_done_0),
        .rd_addr     (c0_rd_addr),
        .rd_en       (c0_rd_en),
        .rd_data     (c0_rd_data)
    );

    c_buf #(
        .ARRAY_ROWS (ARRAY_ROWS),
        .ARRAY_COLS (ARRAY_COLS),
        .ACC_WIDTH  (ACC_WIDTH),
        .GATE_READS (1'b1)
    ) u_c_buf_1 (
        .clk         (clk),
        .rst_n       (combined_rst_n),
        .capture_en  (core_done),
        .c_matrix_i  (c_tile_1),
        .capture_done(c_capture_done_1),
        .rd_addr     (c1_rd_addr),
        .rd_en       (c1_rd_en),
        .rd_data     (c1_rd_data)
    );

    // ------------------------------------------------------------------------
    // 5. AXI4-Stream Master Output Adapter (Single DMA S2MM Channel)
    // ------------------------------------------------------------------------
    axis_out_dual_adapter #(
        .AXIS_DATA_WIDTH (AXIS_DATA_WIDTH),
        .ACC_WIDTH       (ACC_WIDTH),
        .ARRAY_ROWS      (ARRAY_ROWS),
        .ARRAY_COLS      (ARRAY_COLS)
    ) u_out_adapter (
        .clk          (clk),
        .rst_n        (combined_rst_n),
        .start_stream (c_capture_done_0 && c_capture_done_1),
        .active_rows  (job_active_m_q),
        .active_cols  (job_active_n_q),
        .stream_busy  (stream_busy),
        .stream_done  (stream_done),
        .c0_rd_addr   (c0_rd_addr),
        .c0_rd_en     (c0_rd_en),
        .c0_rd_data   (c0_rd_data),
        .c1_rd_addr   (c1_rd_addr),
        .c1_rd_en     (c1_rd_en),
        .c1_rd_data   (c1_rd_data),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tkeep (m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast)
    );

    // Interrupt line to PS7
    assign interrupt = stream_done;

endmodule

`default_nettype wire
