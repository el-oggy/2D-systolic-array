`timescale 1ns / 1ps
`default_nettype none

// Two independent meshes with symmetrical DSP partitioning (Plan B).
// Both Engine 0 and Engine 1 use a balanced hybrid allocation: 110 DSP48E1
// MAC units and 146 Soft-Logic (LUT) MAC units each (total 220 DSPs on XC7Z020).
// Each mesh has its own input wavefront, control, active mask, result matrix,
// and overflow status so the engines compute in parallel with balanced wire routing.
module dual_systolic_array #(
    parameter int ARRAY_ROWS     = 16,
    parameter int ARRAY_COLS     = 16,
    parameter int DATA_WIDTH     = 8,
    parameter int ACC_WIDTH      = 32,
    parameter int DSP_PE_LIMIT   = 110,
    parameter int DSP_PE_LIMIT_0 = DSP_PE_LIMIT,
    parameter int DSP_PE_LIMIT_1 = DSP_PE_LIMIT,
    parameter bit MASK_AT_INGRESS = 1'b0,
    parameter bit TRACK_OVERFLOW = 1'b1
)(
    input  wire                                  clk,
    input  wire                                  rst_n,

    input  wire                                  clr_acc_0,
    input  wire                                  array_en_0,
    input  wire                                  active_mask_0 [0:ARRAY_ROWS-1][0:ARRAY_COLS-1],
    input  wire signed [DATA_WIDTH-1:0]          a_in_0 [0:ARRAY_ROWS-1],
    input  wire signed [DATA_WIDTH-1:0]          b_in_0 [0:ARRAY_COLS-1],
    output wire signed [ACC_WIDTH-1:0]           c_out_0 [0:ARRAY_ROWS-1][0:ARRAY_COLS-1],
    output wire                                  overflow_0,

    input  wire                                  clr_acc_1,
    input  wire                                  array_en_1,
    input  wire                                  active_mask_1 [0:ARRAY_ROWS-1][0:ARRAY_COLS-1],
    input  wire signed [DATA_WIDTH-1:0]          a_in_1 [0:ARRAY_ROWS-1],
    input  wire signed [DATA_WIDTH-1:0]          b_in_1 [0:ARRAY_COLS-1],
    output wire signed [ACC_WIDTH-1:0]           c_out_1 [0:ARRAY_ROWS-1][0:ARRAY_COLS-1],
    output wire                                  overflow_1
);

    localparam int EFF_DSP_LIMIT_0 = DSP_PE_LIMIT_0;
    localparam int EFF_DSP_LIMIT_1 = DSP_PE_LIMIT_1;

    systolic_array #(
        .ARRAY_ROWS  (ARRAY_ROWS),
        .ARRAY_COLS  (ARRAY_COLS),
        .DATA_WIDTH  (DATA_WIDTH),
        .ACC_WIDTH   (ACC_WIDTH),
        .MAC_IMPL    ("HYBRID"),
        .DSP_PE_LIMIT(EFF_DSP_LIMIT_0),
        .MASK_AT_INGRESS(MASK_AT_INGRESS),
        .TRACK_OVERFLOW(TRACK_OVERFLOW)
    ) u_engine_0 (
        .clk        (clk),
        .rst_n      (rst_n),
        .clr_acc    (clr_acc_0),
        .array_en   (array_en_0),
        .active_mask(active_mask_0),
        .a_in       (a_in_0),
        .b_in       (b_in_0),
        .c_out      (c_out_0),
        .overflow   (overflow_0)
    );

    systolic_array #(
        .ARRAY_ROWS  (ARRAY_ROWS),
        .ARRAY_COLS  (ARRAY_COLS),
        .DATA_WIDTH  (DATA_WIDTH),
        .ACC_WIDTH   (ACC_WIDTH),
        .MAC_IMPL    ("HYBRID"),
        .DSP_PE_LIMIT(EFF_DSP_LIMIT_1),
        .MASK_AT_INGRESS(MASK_AT_INGRESS),
        .TRACK_OVERFLOW(TRACK_OVERFLOW)
    ) u_engine_1 (
        .clk        (clk),
        .rst_n      (rst_n),
        .clr_acc    (clr_acc_1),
        .array_en   (array_en_1),
        .active_mask(active_mask_1),
        .a_in       (a_in_1),
        .b_in       (b_in_1),
        .c_out      (c_out_1),
        .overflow   (overflow_1)
    );

endmodule

`default_nettype wire
