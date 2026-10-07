`timescale 1ns / 1ps
`default_nettype none

// One-cycle synchronous BRAM requests, one pending response and two reserved
// FIFO slots. Payload remains stable under arbitrary AXI backpressure.
// Full 512-word packets preserve the driver's fixed receive-buffer contract.
module axis_out_dual_adapter #(
    parameter int AXIS_DATA_WIDTH = 32,
    parameter int ACC_WIDTH = 20,
    parameter int ARRAY_ROWS = 16,
    parameter int ARRAY_COLS = 16
)(
    input wire clk, rst_n,
    input wire start_stream,
    input wire [7:0] active_rows, active_cols,
    output wire stream_busy,
    output logic stream_done,
    output wire [7:0] c0_rd_addr,
    output wire c0_rd_en,
    input wire signed [ACC_WIDTH-1:0] c0_rd_data,
    output wire [7:0] c1_rd_addr,
    output wire c1_rd_en,
    input wire signed [ACC_WIDTH-1:0] c1_rd_data,
    output wire [AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output wire [(AXIS_DATA_WIDTH/8)-1:0] m_axis_tkeep,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tlast
);
    localparam int WORDS = 2 * ARRAY_ROWS * ARRAY_COLS;
    logic running_q;
    logic [9:0] request_index_q;
    logic [7:0] rows_q, cols_q;
    logic pending_q, pending_engine_q, pending_zero_q, pending_last_q;
    logic [1:0] count_q;
    logic head_q, tail_q;
    logic [AXIS_DATA_WIDTH-1:0] fifo_data [0:1];
    logic fifo_last [0:1];

    wire pop = (count_q != 0) && m_axis_tready;
    // Include the in-flight BRAM response in capacity accounting.
    wire [2:0] reservations = {1'b0,count_q} + {2'b0,pending_q};
    wire issue = running_q && request_index_q < WORDS &&
                 (reservations < 3'd2 || pop);
    wire request_zero = request_index_q[7:4] >= rows_q ||
                        request_index_q[3:0] >= cols_q;
    wire signed [ACC_WIDTH-1:0] response =
        pending_engine_q ? c1_rd_data : c0_rd_data;
    wire [AXIS_DATA_WIDTH-1:0] response_ext =
        {{(AXIS_DATA_WIDTH-ACC_WIDTH){response[ACC_WIDTH-1]}},response};

    assign c0_rd_addr = request_index_q[7:0];
    assign c1_rd_addr = request_index_q[7:0];
    assign c0_rd_en = issue && !request_index_q[8] && !request_zero;
    assign c1_rd_en = issue && request_index_q[8] && !request_zero;
    assign m_axis_tvalid = count_q != 0;
    assign m_axis_tdata = fifo_data[head_q];
    assign m_axis_tkeep = {(AXIS_DATA_WIDTH/8){1'b1}};
    assign m_axis_tlast = m_axis_tvalid && fifo_last[head_q];
    assign stream_busy = running_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            running_q <= 1'b0;
            request_index_q <= '0;
            rows_q <= ARRAY_ROWS;
            cols_q <= ARRAY_COLS;
            pending_q <= 1'b0;
            pending_engine_q <= 1'b0;
            pending_zero_q <= 1'b0;
            pending_last_q <= 1'b0;
            count_q <= '0;
            head_q <= 1'b0;
            tail_q <= 1'b0;
            stream_done <= 1'b0;
        end else begin
            stream_done <= 1'b0;
            pending_q <= issue;
            if (start_stream && !running_q) begin
                running_q <= 1'b1;
                request_index_q <= '0;
                rows_q <= (active_rows == 0 || active_rows > ARRAY_ROWS)
                    ? ARRAY_ROWS : active_rows;
                cols_q <= (active_cols == 0 || active_cols > ARRAY_COLS)
                    ? ARRAY_COLS : active_cols;
            end
            if (issue) begin
                request_index_q <= request_index_q + 1'b1;
                pending_engine_q <= request_index_q[8];
                pending_zero_q <= request_zero;
                pending_last_q <= request_index_q == WORDS-1;
            end
            if (pending_q) begin
                fifo_data[tail_q] <= pending_zero_q ? '0 : response_ext;
                fifo_last[tail_q] <= pending_last_q;
                tail_q <= ~tail_q;
            end
            if (pop) begin
                head_q <= ~head_q;
                if (fifo_last[head_q]) begin
                    running_q <= 1'b0;
                    stream_done <= 1'b1;
                end
            end
            case ({pending_q,pop})
                2'b10: count_q <= count_q + 1'b1;
                2'b01: count_q <= count_q - 1'b1;
                default: ;
            endcase
        end
    end
endmodule
`default_nettype wire
