`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: c_buf
// Description: BRAM-backed output buffer for a Matrix C tile.
//              - Captures one output column per cycle into row-banked BRAM
//              - Sequential readout port streams words to AXI-Stream
// ============================================================================

module c_buf #(
    parameter int ARRAY_ROWS = 16,
    parameter int ARRAY_COLS = 16,
    parameter int ACC_WIDTH  = 32,
    parameter bit GATE_READS = 1'b0
)(
    input  wire                               clk,
    input  wire                               rst_n,

    // Parallel capture interface from Systolic Array
    input  wire                               capture_en,
    input  wire signed [ACC_WIDTH-1:0]        c_matrix_i [0:ARRAY_ROWS-1][0:ARRAY_COLS-1],
    output logic                              capture_done,

    // Sequential readout interface (to AXI-Stream master)
    input  wire [7:0]                         rd_addr,   // row = rd_addr[7:4], col = rd_addr[3:0]
    input  wire                               rd_en,
    output wire signed [ACC_WIDTH-1:0]        rd_data
);

    localparam int COL_ADDR_WIDTH = (ARRAY_COLS < 2) ? 1 : $clog2(ARRAY_COLS);
    localparam int ROW_ADDR_WIDTH = (ARRAY_ROWS < 2) ? 1 : $clog2(ARRAY_ROWS);
    localparam logic [COL_ADDR_WIDTH-1:0] LAST_COL = ARRAY_COLS - 1;

    logic capture_active_q;
    logic capture_seen_q;
    logic [COL_ADDR_WIDTH-1:0] capture_col_q;
    wire [COL_ADDR_WIDTH-1:0] rd_col = rd_addr[0 +: COL_ADDR_WIDTH];
    wire [ROW_ADDR_WIDTH-1:0] rd_row = rd_addr[COL_ADDR_WIDTH +: ROW_ADDR_WIDTH];
    logic signed [ACC_WIDTH-1:0] rd_bank_q [0:ARRAY_ROWS-1];
    logic [ROW_ADDR_WIDTH-1:0] rd_row_q;

    always_ff @(posedge clk) begin
        if (!rst_n) rd_row_q <= '0;
        else if (rd_en) rd_row_q <= rd_row;
    end

    // The systolic result remains stable while the controller waits in its
    // capture state. Walk columns and write one word into every row bank per
    // cycle, preserving parallel row commit with only one BRAM write port per bank.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            capture_active_q <= 1'b0;
            capture_seen_q <= 1'b0;
            capture_col_q <= '0;
            capture_done <= 1'b0;
        end else begin
            capture_done <= 1'b0;
            if (!capture_en)
                capture_seen_q <= 1'b0;
            else if (!capture_seen_q && !capture_active_q) begin
                capture_seen_q <= 1'b1;
                capture_active_q <= 1'b1;
                capture_col_q <= '0;
            end

            if (capture_active_q) begin
                if (capture_col_q == LAST_COL) begin
                    capture_active_q <= 1'b0;
                    capture_done <= 1'b1;
                end else begin
                    capture_col_q <= capture_col_q + 1'b1;
                end
            end
        end
    end

    generate
        for (genvar row = 0; row < ARRAY_ROWS; row = row + 1) begin : gen_c_row_bank
            (* ram_style = "block" *) logic signed [ACC_WIDTH-1:0] mem [0:ARRAY_COLS-1];
            always_ff @(posedge clk) begin
                if (capture_active_q)
                    mem[capture_col_q] <= c_matrix_i[row][capture_col_q];
                if (!GATE_READS || (rd_en && rd_row == row))
                    rd_bank_q[row] <= mem[rd_col];
            end
        end
    endgenerate

    assign rd_data = rd_bank_q[GATE_READS ? rd_row_q : rd_row];

endmodule

`default_nettype wire
