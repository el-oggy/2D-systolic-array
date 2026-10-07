`timescale 1ns / 1ps
`default_nettype none

// Two-bank, single-write/synchronous-read tile storage. Writes always target
// the inactive bank; commit atomically makes that bank visible to the reader.
// At 256 bytes per bank, Vivado maps these small memories to distributed RAM.
module ping_pong_bram #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH = 256,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire                  commit,
    input  wire                  rd_en,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic                 active_bank
);
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] bank0 [0:DEPTH-1];
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] bank1 [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (wr_en) begin
            if (active_bank)
                bank0[wr_addr] <= wr_data;
            else
                bank1[wr_addr] <= wr_data;
        end

        if (rd_en) begin
            if (active_bank)
                rd_data <= bank1[rd_addr];
            else
                rd_data <= bank0[rd_addr];
        end

        if (!rst_n) begin
            active_bank <= 1'b0;
            rd_data <= '0;
        end else if (commit) begin
            active_bank <= ~active_bank;
        end
    end
endmodule

// Persistent row-banked weight store used by cached MVM mode. The AXIS loader
// supplies dense row-major INT8 weights while the accelerator is idle. Rows
// are striped over ROW_BANKS synchronous BRAM banks, allowing one byte from
// each row of a 16-row tile to be read per cycle. The in-bank address is
// group*load_k+k, so variable K dimensions remain densely packed.
module weight_bram_cache #(
    parameter int MAX_ROWS = 224,
    parameter int MAX_K = 512,
    parameter int ROW_BANKS = 16,
    parameter int DEPTH_BYTES = MAX_ROWS * MAX_K,
    parameter int ADDR_WIDTH = $clog2(DEPTH_BYTES),
    parameter int ROWS_PER_BANK = (MAX_ROWS + ROW_BANKS - 1) / ROW_BANKS,
    parameter int BANK_DEPTH_BYTES = ROWS_PER_BANK * MAX_K,
    parameter int BANK_ADDR_WIDTH = $clog2(BANK_DEPTH_BYTES)
)(
    input  wire                  clk,
    input  wire [15:0]           load_k,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [7:0]            wr_data,
    input  wire                  rd_en,
    input  wire [BANK_ADDR_WIDTH-1:0] rd_addr,
    output logic [7:0]           rd_data [0:ROW_BANKS-1]
);
    logic [15:0] wr_row_q;
    logic [15:0] wr_k_q;
    logic [BANK_ADDR_WIDTH-1:0] wr_group_base_q;

    // Address zero starts a new dense row-major weight packet. The counters
    // transpose the stream into row banks without requiring host-side padding.
    wire start_packet = wr_en && (wr_addr == '0);
    wire [15:0] row_for_write = start_packet ? 16'd0 : wr_row_q;
    wire [15:0] k_for_write = start_packet ? 16'd0 : wr_k_q;
    wire [BANK_ADDR_WIDTH-1:0] group_base_for_write =
        start_packet ? '0 : wr_group_base_q;
    wire [BANK_ADDR_WIDTH-1:0] bank_wr_addr =
        group_base_for_write + k_for_write[BANK_ADDR_WIDTH-1:0];

    // Each bank holds 14 rows * 512 bytes = 7168 bytes at the configured
    // maximum, which maps to two RAMB36 blocks per row bank.
    generate
        for (genvar bank = 0; bank < ROW_BANKS; bank = bank + 1) begin : gen_weight_bank
            (* ram_style = "block" *) logic [7:0] mem [0:BANK_DEPTH_BYTES-1];
            always_ff @(posedge clk) begin
                if (wr_en && (load_k != 0) && (row_for_write % ROW_BANKS == bank))
                    mem[bank_wr_addr] <= wr_data;
                if (rd_en)
                    rd_data[bank] <= mem[rd_addr];
            end
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (wr_en && (load_k != 0)) begin
            if (k_for_write + 16'd1 >= load_k) begin
                wr_row_q <= row_for_write + 16'd1;
                wr_k_q <= '0;
                if ((row_for_write % ROW_BANKS) == ROW_BANKS - 1)
                    wr_group_base_q <= group_base_for_write + load_k[BANK_ADDR_WIDTH-1:0];
                else
                    wr_group_base_q <= group_base_for_write;
            end else begin
                wr_row_q <= row_for_write;
                wr_k_q <= k_for_write + 16'd1;
                wr_group_base_q <= group_base_for_write;
            end
        end
    end
endmodule

// Completed MVM result storage. Each row bank accepts one 32-bit result on
// the same commit edge, while the synchronous read side returns one value
// from every bank so the stream adapter can select the requested row.
module mvm_result_bram #(
    parameter int DATA_WIDTH = 32,
    parameter int BANKS = 16,
    parameter int DEPTH = 14,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire                              clk,
    input  wire                              wr_en,
    input  wire [ADDR_WIDTH-1:0]             wr_addr,
    input  wire signed [DATA_WIDTH-1:0]      wr_data [0:BANKS-1],
    input  wire                              rd_en,
    input  wire [ADDR_WIDTH-1:0]             rd_addr,
    output wire signed [DATA_WIDTH-1:0]      rd_data [0:BANKS-1]
);
    generate
        for (genvar bank = 0; bank < BANKS; bank = bank + 1) begin : gen_mvm_result_bank
            (* ram_style = "block" *) logic signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];
            logic signed [DATA_WIDTH-1:0] rd_data_q;

            always_ff @(posedge clk) begin
                if (wr_en)
                    mem[wr_addr] <= wr_data[bank];
                if (rd_en)
                    rd_data_q <= mem[rd_addr];
            end

            assign rd_data[bank] = rd_data_q;
        end
    endgenerate
endmodule

`default_nettype wire
