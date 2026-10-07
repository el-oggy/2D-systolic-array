`timescale 1ns / 1ps

// ============================================================================
// Module: accel_top_wrapper.v
// Description: Pure Verilog (.v) Top Wrapper for Vivado IP Integrator (BD).
//              Required because Vivado Block Design forbids .sv files as the
//              top-level module reference (ERROR: [filemgmt 56-195]).
//              Instantiates the SystemVerilog accel_dual_engine_top compute engine.
//              Option 2: Unified Dual-Engine Accelerator (512 MACs, 110/110 DSPs).
// ============================================================================

module accel_top_wrapper #(
    parameter integer ARRAY_ROWS      = 16,
    parameter integer ARRAY_COLS      = 16,
    parameter integer TILE_K          = 16,
    parameter integer DATA_WIDTH      = 8,
    parameter integer ACC_WIDTH       = 20,
    parameter integer DSP_PE_LIMIT_0  = 110,
    parameter integer DSP_PE_LIMIT_1  = 110,
    parameter integer AXI_ADDR_WIDTH  = 32,
    parameter integer AXI_DATA_WIDTH  = 32,
    parameter integer AXIS_DATA_WIDTH = 32
)(
    input  wire                                clk,
    input  wire                                rst_n,

    // AXI4-Lite Slave Interface (Control & Status)
    input  wire [AXI_ADDR_WIDTH-1:0]           s_axi_awaddr,
    input  wire [2:0]                          s_axi_awprot,
    input  wire                                s_axi_awvalid,
    output wire                                s_axi_awready,

    input  wire [AXI_DATA_WIDTH-1:0]           s_axi_wdata,
    input  wire [(AXI_DATA_WIDTH/8)-1:0]       s_axi_wstrb,
    input  wire                                s_axi_wvalid,
    output wire                                s_axi_wready,

    output wire [1:0]                          s_axi_bresp,
    output wire                                s_axi_bvalid,
    input  wire                                s_axi_bready,

    input  wire [AXI_ADDR_WIDTH-1:0]           s_axi_araddr,
    input  wire [2:0]                          s_axi_arprot,
    input  wire                                s_axi_arvalid,
    output wire                                s_axi_arready,

    output wire [AXI_DATA_WIDTH-1:0]          s_axi_rdata,
    output wire [1:0]                          s_axi_rresp,
    output wire                                s_axi_rvalid,
    input  wire                                s_axi_rready,

    // AXI4-Stream Slave Interface (Matrix Data In: A0, B0, A1, B1 from Single DMA)
    input  wire [AXIS_DATA_WIDTH-1:0]          s_axis_tdata,
    input  wire [(AXIS_DATA_WIDTH/8)-1:0]      s_axis_tkeep,
    input  wire                                s_axis_tvalid,
    output wire                                s_axis_tready,
    input  wire                                s_axis_tlast,

    // AXI4-Stream Master Interface (Matrix Data Out: C0 then C1 to Single DMA)
    output wire [AXIS_DATA_WIDTH-1:0]          m_axis_tdata,
    output wire [(AXIS_DATA_WIDTH/8)-1:0]      m_axis_tkeep,
    output wire                                m_axis_tvalid,
    input  wire                                m_axis_tready,
    output wire                                m_axis_tlast,

    // Interrupt output to Zynq Processing System
    output wire                                interrupt
);

    accel_dual_engine_top #(
        .ARRAY_ROWS     (ARRAY_ROWS),
        .ARRAY_COLS     (ARRAY_COLS),
        .TILE_K         (TILE_K),
        .DATA_WIDTH     (DATA_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .DSP_PE_LIMIT_0 (DSP_PE_LIMIT_0),
        .DSP_PE_LIMIT_1 (DSP_PE_LIMIT_1),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH)
    ) u_dual_top (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axi_awaddr (s_axi_awaddr),
        .s_axi_awprot (s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata  (s_axi_wdata),
        .s_axi_wstrb  (s_axi_wstrb),
        .s_axi_wvalid (s_axi_wvalid),
        .s_axi_wready (s_axi_wready),
        .s_axi_bresp  (s_axi_bresp),
        .s_axi_bvalid (s_axi_bvalid),
        .s_axi_bready (s_axi_bready),
        .s_axi_araddr (s_axi_araddr),
        .s_axi_arprot (s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata  (s_axi_rdata),
        .s_axi_rresp  (s_axi_rresp),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready),
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tkeep (s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast (s_axis_tlast),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tkeep (m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast),
        .interrupt    (interrupt)
    );

endmodule
