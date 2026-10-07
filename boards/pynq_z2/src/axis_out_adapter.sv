`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: axis_out_adapter
// Description: AXI4-Stream Master output adapter for Matrix C tile results.
//              Reads INT32 words sequentially from c_buf and drives them over
//              the AXI4-Stream master interface with proper tlast signaling.
// ============================================================================

module axis_out_adapter #(
    parameter int AXIS_DATA_WIDTH = 32,
    parameter int ACC_WIDTH       = 32,
    parameter int ARRAY_ROWS      = 16,
    parameter int ARRAY_COLS      = 16,
    parameter int MAX_VECTOR_ROWS = 680
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Stream transfer trigger
    input  wire                         start_stream,
    input  wire                         final_stream_tile,
    input  wire [9:0]                   active_rows,
    input  wire [7:0]                   active_cols,
    input  wire                         vector_mode,
    output logic                        stream_busy,
    output logic                        stream_done,

    // C Buffer read port
    output logic [9:0]                  c_rd_addr,
    input  wire signed [ACC_WIDTH-1:0]  c_rd_data,
    input  wire signed [AXIS_DATA_WIDTH-1:0] vector_rd_data,

    // AXI4-Stream Master Interface
    output logic [AXIS_DATA_WIDTH-1:0]  m_axis_tdata,
    output logic [(AXIS_DATA_WIDTH/8)-1:0] m_axis_tkeep,
    output logic                        m_axis_tvalid,
    input  wire                         m_axis_tready,
    output logic                        m_axis_tlast
);

    typedef enum logic [1:0] {
        IDLE    = 2'd0,
        READ    = 2'd1,
        STREAM  = 2'd2,
        DONE    = 2'd3
    } state_t;

    state_t state;

    logic [9:0] curr_r;
    logic [3:0] curr_c;
    logic [9:0] lim_r;
    logic [7:0] lim_c;
    logic       is_last_elem;
    logic       vector_mode_q;
    logic       final_stream_tile_q;
    logic signed [AXIS_DATA_WIDTH-1:0] matrix_data_ext;

    wire is_last = (curr_r == lim_r - 1) && (curr_c == lim_c - 1);
    always_comb matrix_data_ext = c_rd_data;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state         <= IDLE;
            curr_r        <= 4'd0;
            curr_c        <= 4'd0;
            lim_r         <= ARRAY_ROWS[9:0];
            lim_c         <= ARRAY_COLS[7:0];
            c_rd_addr     <= 10'd0;
            m_axis_tdata  <= '0;
            m_axis_tkeep  <= 4'b1111;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            stream_busy   <= 1'b0;
            stream_done   <= 1'b0;
            is_last_elem  <= 1'b0;
            vector_mode_q <= 1'b0;
            final_stream_tile_q <= 1'b1;
        end else begin
            stream_done <= 1'b0;

            case (state)
                IDLE: begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                    if (start_stream) begin
                        state        <= READ;
                        stream_busy  <= 1'b1;
                        curr_r       <= 10'd0;
                        curr_c       <= 4'd0;
                        lim_r        <= vector_mode
                            ? ((active_rows == 0 || active_rows > MAX_VECTOR_ROWS) ? MAX_VECTOR_ROWS[9:0] : active_rows)
                            : ((active_rows == 0 || active_rows > ARRAY_ROWS) ? ARRAY_ROWS[9:0] : active_rows);
                        lim_c        <= (active_cols == 0 || active_cols > ARRAY_COLS) ? ARRAY_COLS[7:0] : active_cols;
                        c_rd_addr    <= 10'd0;
                        is_last_elem <= 1'b0;
                        vector_mode_q <= vector_mode;
                        final_stream_tile_q <= final_stream_tile;
                        if (vector_mode) lim_c <= 8'd1;
                    end else begin
                        stream_busy  <= 1'b0;
                    end
                end

                READ: begin
                    // 1 cycle memory read latency
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                    state        <= STREAM;
                    is_last_elem <= is_last;
                end

                STREAM: begin
                    m_axis_tvalid <= 1'b1;
                    m_axis_tdata  <= vector_mode_q ? vector_rd_data : matrix_data_ext;
                    m_axis_tlast  <= is_last_elem &&
                                     (!vector_mode_q || final_stream_tile_q);

                    if (m_axis_tvalid && m_axis_tready) begin
                        if (is_last_elem) begin
                            m_axis_tvalid <= 1'b0;
                            m_axis_tlast  <= 1'b0;
                            state         <= DONE;
                        end else begin
                            // Drop VALID on the accepted beat before the
                            // next synchronous C-buffer read to avoid replaying it.
                            m_axis_tvalid <= 1'b0;
                            m_axis_tlast  <= 1'b0;
                            // Advance coordinates
                            if (vector_mode_q) begin
                                curr_r <= curr_r + 1'b1;
                                c_rd_addr <= curr_r + 1'b1;
                            end else if (curr_c + 1 < lim_c) begin
                                curr_c <= curr_c + 1;
                                c_rd_addr <= {2'b00, curr_r[3:0], curr_c + 4'd1};
                            end else begin
                                curr_c <= 4'd0;
                                curr_r <= curr_r + 1;
                                c_rd_addr <= {2'b00, curr_r[3:0] + 4'd1, 4'd0};
                            end
                            state <= READ;
                        end
                    end
                end

                DONE: begin
                    stream_busy <= 1'b0;
                    stream_done <= 1'b1;
                    state       <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
