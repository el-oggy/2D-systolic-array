`timescale 1ns / 1ps
`default_nettype none

// Central tile controller driving two independent systolic meshes. Each call
// processes one tile per engine; the host schedules larger GEMMs as tiles.
// Plan B: Engine 0 and Engine 1 both use symmetrical 110-DSP / 146-LUT hybrid meshes.
module accel_dual_tile_core #(
    parameter int ARRAY_ROWS     = 16,
    parameter int ARRAY_COLS     = 16,
    parameter int TILE_K         = 16,
    parameter int DATA_WIDTH     = 8,
    parameter int ACC_WIDTH      = 32,
    parameter int DSP_PE_LIMIT_0 = 110,
    parameter int DSP_PE_LIMIT_1 = 110,
    parameter int DSP_PE_LIMIT   = 110
)(
    input  wire                                      clk,
    input  wire                                      rst_n,
    input  wire                                      start,
    input  wire [15:0]                               m_dim,
    input  wire [15:0]                               k_dim,
    input  wire [15:0]                               n_dim,
    input  wire [7:0]                                active_m,
    input  wire [7:0]                                active_n,
    input  wire signed [DATA_WIDTH-1:0]              a_tile_0 [0:ARRAY_ROWS-1][0:TILE_K-1],
    input  wire signed [DATA_WIDTH-1:0]              b_tile_0 [0:TILE_K-1][0:ARRAY_COLS-1],
    input  wire signed [DATA_WIDTH-1:0]              a_tile_1 [0:ARRAY_ROWS-1][0:TILE_K-1],
    input  wire signed [DATA_WIDTH-1:0]              b_tile_1 [0:TILE_K-1][0:ARRAY_COLS-1],
    output wire signed [ACC_WIDTH-1:0]               c_tile_0 [0:ARRAY_ROWS-1][0:ARRAY_COLS-1],
    output wire signed [ACC_WIDTH-1:0]               c_tile_1 [0:ARRAY_ROWS-1][0:ARRAY_COLS-1],
    output wire                                      busy,
    output wire                                      done,
    output wire                                      overflow_0,
    output wire                                      overflow_1,
    output wire                                      invalid_shape,
    output wire [31:0]                               cycles_counter,
    output wire [31:0]                               tiles_counter
);

    wire start_valid = start && !invalid_shape;
    wire load_en;
    wire shift_en;
    wire array_en;
    wire clr_acc;
    wire c_capture;
    wire active_mask [0:ARRAY_ROWS-1][0:ARRAY_COLS-1];
    wire [15:0] curr_mt;
    wire [15:0] curr_nt;
    wire [15:0] curr_kt;
    wire [7:0] actual_m;
    wire [7:0] actual_k;
    wire [7:0] actual_n;
    wire signed [DATA_WIDTH-1:0] a_skewed_0 [0:ARRAY_ROWS-1];
    wire signed [DATA_WIDTH-1:0] b_skewed_0 [0:ARRAY_COLS-1];
    wire signed [DATA_WIDTH-1:0] a_skewed_1 [0:ARRAY_ROWS-1];
    wire signed [DATA_WIDTH-1:0] b_skewed_1 [0:ARRAY_COLS-1];

    assign invalid_shape = (m_dim == 0) || (m_dim > ARRAY_ROWS) ||
                           (k_dim == 0) || (k_dim > TILE_K) ||
                           (n_dim == 0) || (n_dim > ARRAY_COLS);

    single_tile_controller #(
        .ARRAY_ROWS(ARRAY_ROWS),
        .ARRAY_COLS(ARRAY_COLS),
        .TILE_K(TILE_K),
        .WAIT_FOR_CAPTURE(1'b0),
        .ACTIVE_EXTENT_OUTPUTS(1'b1)
    ) u_controller (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_valid),
        .soft_reset(1'b0),
        .m_dim(m_dim),
        .k_dim(k_dim),
        .n_dim(n_dim),
        .active_m_in(active_m),
        .active_n_in(active_n),
        .busy(busy),
        .done(done),
        .load_en(load_en),
        .shift_en(shift_en),
        .array_en(array_en),
        .clr_acc(clr_acc),
        .c_capture(c_capture),
        .capture_done(1'b0),
        .active_mask(active_mask),
        .curr_mt(curr_mt),
        .curr_nt(curr_nt),
        .curr_kt(curr_kt),
        .actual_m(actual_m),
        .actual_k(actual_k),
        .actual_n(actual_n),
        .cycles_counter(cycles_counter),
        .tiles_counter(tiles_counter)
    );

    skew_buffers #(
        .ARRAY_ROWS(ARRAY_ROWS),
        .ARRAY_COLS(ARRAY_COLS),
        .TILE_K(TILE_K),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_skew_0 (
        .clk(clk), .rst_n(rst_n), .load_en(load_en), .shift_en(shift_en),
        .actual_m(actual_m), .actual_k(actual_k), .actual_n(actual_n),
        .a_tile_in(a_tile_0), .b_tile_in(b_tile_0),
        .a_skewed_o(a_skewed_0), .b_skewed_o(b_skewed_0)
    );

    skew_buffers #(
        .ARRAY_ROWS(ARRAY_ROWS),
        .ARRAY_COLS(ARRAY_COLS),
        .TILE_K(TILE_K),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_skew_1 (
        .clk(clk), .rst_n(rst_n), .load_en(load_en), .shift_en(shift_en),
        .actual_m(actual_m), .actual_k(actual_k), .actual_n(actual_n),
        .a_tile_in(a_tile_1), .b_tile_in(b_tile_1),
        .a_skewed_o(a_skewed_1), .b_skewed_o(b_skewed_1)
    );

    dual_systolic_array #(
        .ARRAY_ROWS(ARRAY_ROWS),
        .ARRAY_COLS(ARRAY_COLS),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .DSP_PE_LIMIT_0(DSP_PE_LIMIT_0),
        .DSP_PE_LIMIT_1(DSP_PE_LIMIT_1),
        .DSP_PE_LIMIT(DSP_PE_LIMIT),
        .MASK_AT_INGRESS(1'b1),
        .TRACK_OVERFLOW(!((DATA_WIDTH == 8) && (ACC_WIDTH == 20) && (TILE_K <= 16)))
    ) u_dual_mesh (
        .clk(clk), .rst_n(rst_n),
        .clr_acc_0(clr_acc), .array_en_0(array_en), .active_mask_0(active_mask),
        .a_in_0(a_skewed_0), .b_in_0(b_skewed_0),
        .c_out_0(c_tile_0), .overflow_0(overflow_0),
        .clr_acc_1(clr_acc), .array_en_1(array_en), .active_mask_1(active_mask),
        .a_in_1(a_skewed_1), .b_in_1(b_skewed_1),
        .c_out_1(c_tile_1), .overflow_1(overflow_1)
    );

endmodule

`default_nettype wire
