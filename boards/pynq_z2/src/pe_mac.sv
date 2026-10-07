`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: pe_mac
// Description: Parameterized Processing Element (PE) with Multiply-Accumulate
//              and Selectable MAC Implementation (DSP / LUT / SHARED).
// ============================================================================

module pe_mac #(
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32,
    parameter     MAC_IMPL   = "DSP", // "DSP", "LUT", "SHARED"
    parameter bit FREE_RUN_FORWARD = 1'b0,
    // Disable only when system-level operand/K bounds prove overflow impossible.
    parameter bit TRACK_OVERFLOW = 1'b1
)(
    input  wire                          clk,
    input  wire                          rst_n,      // Synchronous active-low reset
    input  wire                          clr_acc,    // Clear accumulator for new K-pass
    input  wire                          en,         // Active region enable

    // Systolic stream inputs
    input  wire signed [DATA_WIDTH-1:0]  a_i,        // Activation input from West
    input  wire signed [DATA_WIDTH-1:0]  b_i,        // Weight/feature input from North

    // Systolic forwarding outputs (1-cycle register delay)
    output logic signed [DATA_WIDTH-1:0] a_o,        // Forward to East
    output logic signed [DATA_WIDTH-1:0] b_o,        // Forward to South

    // Accumulated output and status
    output logic signed [ACC_WIDTH-1:0]  acc_o,      // 32-bit signed accumulator
    output logic                         overflow_o  // Sticky overflow indicator
);

    // Internal pipeline registers
    logic signed [DATA_WIDTH-1:0] a_q;
    logic signed [DATA_WIDTH-1:0] b_q;
    logic signed [ACC_WIDTH-1:0]  acc_q;
    logic                         overflow_q;

    // Multiplier product
    localparam int PROD_WIDTH = 2 * DATA_WIDTH;
    wire signed [PROD_WIDTH-1:0] mult_product;

    // Synthesize MAC according to MAC_IMPL parameter
    generate
        if (MAC_IMPL == "LUT") begin : gen_lut_mac
            (* use_dsp = "no" *) wire signed [PROD_WIDTH-1:0] product_lut;
            assign product_lut = a_i * b_i;
            assign mult_product = product_lut;
        end else if (MAC_IMPL == "SHARED") begin : gen_shared_mac
            (* use_dsp = "no" *) wire signed [PROD_WIDTH-1:0] product_shared;
            assign product_shared = a_i * b_i;
            assign mult_product = product_shared;
        end else begin : gen_dsp_mac // Default: "DSP"
            // Leave the product unforced so Vivado can fuse it with the
            // accumulator add into one DSP48E1 MAC, instead of mapping a
            // multiplier DSP and a second MAC DSP for the same PE.
            wire signed [PROD_WIDTH-1:0] product_dsp;
            assign product_dsp = a_i * b_i;
            assign mult_product = product_dsp;
        end
    endgenerate

    // Sign-extend product to accumulator width
    wire signed [ACC_WIDTH-1:0] prod_ext = {{ (ACC_WIDTH - PROD_WIDTH){mult_product[PROD_WIDTH-1]} }, mult_product};

    // Calculate next accumulator and detect two's complement overflow
    wire signed [ACC_WIDTH-1:0] next_acc;
    generate
        if (MAC_IMPL == "LUT" || MAC_IMPL == "SHARED") begin : gen_lut_accum
            (* use_dsp = "no" *) wire signed [ACC_WIDTH-1:0] next_acc_lut;
            assign next_acc_lut = acc_q + prod_ext;
            assign next_acc = next_acc_lut;
        end else begin : gen_dsp_accum
            (* use_dsp = "yes" *) wire signed [ACC_WIDTH-1:0] next_acc_dsp;
            assign next_acc_dsp = acc_q + prod_ext;
            assign next_acc = next_acc_dsp;
        end
    endgenerate
    wire signed_overflow = (acc_q[ACC_WIDTH-1] == prod_ext[ACC_WIDTH-1]) &&
                           (next_acc[ACC_WIDTH-1] != acc_q[ACC_WIDTH-1]);

    // Sequential update
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            a_q        <= '0;
            b_q        <= '0;
            acc_q      <= '0;
            overflow_q <= 1'b0;
        end else begin
            if (clr_acc) begin
                acc_q      <= '0;
                overflow_q <= 1'b0;
            end

            // In the integrated ingress-masked mesh, inactive rows/columns
            // receive zero-padded streams and clr_acc clears forwarding state
            // at each tile boundary. The forwarding flops can then capture
            // every cycle without per-bit enable/zero muxes.
            if (FREE_RUN_FORWARD) begin
                a_q <= a_i;
                b_q <= b_i;
            end else if (en) begin
                a_q <= a_i;
                b_q <= b_i;
            end else begin
                a_q <= '0;
                b_q <= '0;
            end
            if (en && !clr_acc) begin
                acc_q <= next_acc;
                if (signed_overflow)
                    overflow_q <= 1'b1; // Sticky flag
            end
        end
    end

    assign a_o        = a_q;
    assign b_o        = b_q;
    assign acc_o      = acc_q;
    assign overflow_o = TRACK_OVERFLOW ? overflow_q : 1'b0;

endmodule

`default_nettype wire
