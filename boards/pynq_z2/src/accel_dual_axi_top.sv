`timescale 1ns / 1ps
`default_nettype none

// Two independently controlled AXI engines. Engine 0 maps at most 200 MAC
// multipliers to DSP48E1s; engine 1 is fully LUT based. Each AXI DMA sends an
// A packet followed by a B packet to its engine's input stream.
module accel_dual_axi_top #(
    parameter int ARRAY_ROWS = 16,
    parameter int ARRAY_COLS = 16,
    parameter int ENGINE1_ROWS = 16,
    parameter int TILE_K = 16,
    parameter int DATA_WIDTH = 8,
    // Per-tile INT8 dot products with K<=16 fit signed 20-bit; the AXIS
    // adapter sign-extends results to the driver's INT32 output buffer.
    parameter int ACC_WIDTH = 20,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int AXIS_DATA_WIDTH = 32,
    parameter int DSP_PE_LIMIT = 110
)(
    input wire clk,
    input wire rst_n,

    input wire [AXI_ADDR_WIDTH-1:0] e0_s_axi_awaddr,
    input wire [2:0] e0_s_axi_awprot,
    input wire e0_s_axi_awvalid,
    output wire e0_s_axi_awready,
    input wire [AXI_DATA_WIDTH-1:0] e0_s_axi_wdata,
    input wire [AXI_DATA_WIDTH/8-1:0] e0_s_axi_wstrb,
    input wire e0_s_axi_wvalid,
    output wire e0_s_axi_wready,
    output wire [1:0] e0_s_axi_bresp,
    output wire e0_s_axi_bvalid,
    input wire e0_s_axi_bready,
    input wire [AXI_ADDR_WIDTH-1:0] e0_s_axi_araddr,
    input wire [2:0] e0_s_axi_arprot,
    input wire e0_s_axi_arvalid,
    output wire e0_s_axi_arready,
    output wire [AXI_DATA_WIDTH-1:0] e0_s_axi_rdata,
    output wire [1:0] e0_s_axi_rresp,
    output wire e0_s_axi_rvalid,
    input wire e0_s_axi_rready,
    input wire [AXIS_DATA_WIDTH-1:0] e0_s_axis_tdata,
    input wire [AXIS_DATA_WIDTH/8-1:0] e0_s_axis_tkeep,
    input wire e0_s_axis_tvalid,
    output wire e0_s_axis_tready,
    input wire e0_s_axis_tlast,
    output wire [AXIS_DATA_WIDTH-1:0] e0_m_axis_tdata,
    output wire [AXIS_DATA_WIDTH/8-1:0] e0_m_axis_tkeep,
    output wire e0_m_axis_tvalid,
    input wire e0_m_axis_tready,
    output wire e0_m_axis_tlast,
    output wire e0_interrupt,

    input wire [AXI_ADDR_WIDTH-1:0] e1_s_axi_awaddr,
    input wire [2:0] e1_s_axi_awprot,
    input wire e1_s_axi_awvalid,
    output wire e1_s_axi_awready,
    input wire [AXI_DATA_WIDTH-1:0] e1_s_axi_wdata,
    input wire [AXI_DATA_WIDTH/8-1:0] e1_s_axi_wstrb,
    input wire e1_s_axi_wvalid,
    output wire e1_s_axi_wready,
    output wire [1:0] e1_s_axi_bresp,
    output wire e1_s_axi_bvalid,
    input wire e1_s_axi_bready,
    input wire [AXI_ADDR_WIDTH-1:0] e1_s_axi_araddr,
    input wire [2:0] e1_s_axi_arprot,
    input wire e1_s_axi_arvalid,
    output wire e1_s_axi_arready,
    output wire [AXI_DATA_WIDTH-1:0] e1_s_axi_rdata,
    output wire [1:0] e1_s_axi_rresp,
    output wire e1_s_axi_rvalid,
    input wire e1_s_axi_rready,
    input wire [AXIS_DATA_WIDTH-1:0] e1_s_axis_tdata,
    input wire [AXIS_DATA_WIDTH/8-1:0] e1_s_axis_tkeep,
    input wire e1_s_axis_tvalid,
    output wire e1_s_axis_tready,
    input wire e1_s_axis_tlast,
    output wire [AXIS_DATA_WIDTH-1:0] e1_m_axis_tdata,
    output wire [AXIS_DATA_WIDTH/8-1:0] e1_m_axis_tkeep,
    output wire e1_m_axis_tvalid,
    input wire e1_m_axis_tready,
    output wire e1_m_axis_tlast,
    output wire e1_interrupt
);
    accel_top #(
        .ARRAY_ROWS(ARRAY_ROWS), .ARRAY_COLS(ARRAY_COLS), .TILE_K(TILE_K),
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .MAC_IMPL("HYBRID"),
        .DSP_PE_LIMIT(DSP_PE_LIMIT), .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH), .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH)
    ) u_engine0 (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(e0_s_axi_awaddr), .s_axi_awprot(e0_s_axi_awprot),
        .s_axi_awvalid(e0_s_axi_awvalid), .s_axi_awready(e0_s_axi_awready),
        .s_axi_wdata(e0_s_axi_wdata), .s_axi_wstrb(e0_s_axi_wstrb),
        .s_axi_wvalid(e0_s_axi_wvalid), .s_axi_wready(e0_s_axi_wready),
        .s_axi_bresp(e0_s_axi_bresp), .s_axi_bvalid(e0_s_axi_bvalid),
        .s_axi_bready(e0_s_axi_bready), .s_axi_araddr(e0_s_axi_araddr),
        .s_axi_arprot(e0_s_axi_arprot), .s_axi_arvalid(e0_s_axi_arvalid),
        .s_axi_arready(e0_s_axi_arready), .s_axi_rdata(e0_s_axi_rdata),
        .s_axi_rresp(e0_s_axi_rresp), .s_axi_rvalid(e0_s_axi_rvalid),
        .s_axi_rready(e0_s_axi_rready), .s_axis_tdata(e0_s_axis_tdata),
        .s_axis_tkeep(e0_s_axis_tkeep), .s_axis_tvalid(e0_s_axis_tvalid),
        .s_axis_tready(e0_s_axis_tready), .s_axis_tlast(e0_s_axis_tlast),
        .m_axis_tdata(e0_m_axis_tdata), .m_axis_tkeep(e0_m_axis_tkeep),
        .m_axis_tvalid(e0_m_axis_tvalid), .m_axis_tready(e0_m_axis_tready),
        .m_axis_tlast(e0_m_axis_tlast), .interrupt(e0_interrupt)
    );

    accel_top #(
        .ARRAY_ROWS(ENGINE1_ROWS), .ARRAY_COLS(ARRAY_COLS), .TILE_K(TILE_K),
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .MAC_IMPL("HYBRID"),
        .DSP_PE_LIMIT(DSP_PE_LIMIT), .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH), .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH)
    ) u_engine1 (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(e1_s_axi_awaddr), .s_axi_awprot(e1_s_axi_awprot),
        .s_axi_awvalid(e1_s_axi_awvalid), .s_axi_awready(e1_s_axi_awready),
        .s_axi_wdata(e1_s_axi_wdata), .s_axi_wstrb(e1_s_axi_wstrb),
        .s_axi_wvalid(e1_s_axi_wvalid), .s_axi_wready(e1_s_axi_wready),
        .s_axi_bresp(e1_s_axi_bresp), .s_axi_bvalid(e1_s_axi_bvalid),
        .s_axi_bready(e1_s_axi_bready), .s_axi_araddr(e1_s_axi_araddr),
        .s_axi_arprot(e1_s_axi_arprot), .s_axi_arvalid(e1_s_axi_arvalid),
        .s_axi_arready(e1_s_axi_arready), .s_axi_rdata(e1_s_axi_rdata),
        .s_axi_rresp(e1_s_axi_rresp), .s_axi_rvalid(e1_s_axi_rvalid),
        .s_axi_rready(e1_s_axi_rready), .s_axis_tdata(e1_s_axis_tdata),
        .s_axis_tkeep(e1_s_axis_tkeep), .s_axis_tvalid(e1_s_axis_tvalid),
        .s_axis_tready(e1_s_axis_tready), .s_axis_tlast(e1_s_axis_tlast),
        .m_axis_tdata(e1_m_axis_tdata), .m_axis_tkeep(e1_m_axis_tkeep),
        .m_axis_tvalid(e1_m_axis_tvalid), .m_axis_tready(e1_m_axis_tready),
        .m_axis_tlast(e1_m_axis_tlast), .interrupt(e1_interrupt)
    );
endmodule

`default_nettype wire
