`timescale 1ns / 1ps
`default_nettype none

// AXI4-Stream byte unpacker. In compatibility mode packets target A then B
// automatically. Cached MVM mode can select A (weight cache) or B (activation
// vector) explicitly so a loaded weight matrix can be reused across vectors.
module axis_in_adapter #(
    parameter int AXIS_DATA_WIDTH = 32,
    parameter int DATA_WIDTH      = 8,
    parameter int A_ADDR_WIDTH    = 18,
    parameter int B_ADDR_WIDTH    = 9,
    parameter int A_DEPTH_BYTES  = 245760,
    parameter int B_DEPTH_BYTES  = 512
)(
    input  wire                                  clk,
    input  wire                                  rst_n,
    input  wire [AXIS_DATA_WIDTH-1:0]            s_axis_tdata,
    input  wire [(AXIS_DATA_WIDTH/8)-1:0]        s_axis_tkeep,
    input  wire                                  s_axis_tvalid,
    output logic                                 s_axis_tready,
    input  wire                                  s_axis_tlast,
    input  wire                                  load_enable,
    input  wire                                  stream_target_manual,
    input  wire                                  stream_target,
    output logic                                 a_wr_en,
    output logic [A_ADDR_WIDTH-1:0]              a_wr_addr,
    output logic signed [DATA_WIDTH-1:0]         a_wr_data,
    output logic                                 b_wr_en,
    output logic [B_ADDR_WIDTH-1:0]              b_wr_addr,
    output logic signed [DATA_WIDTH-1:0]         b_wr_data,
    output logic                                 a_commit,
    output logic                                 b_commit,
    output logic [A_ADDR_WIDTH-1:0]              a_packet_bytes,
    output logic [B_ADDR_WIDTH:0]                b_packet_bytes,
    output logic                                 packet_overflow,
    output logic                                 load_active,
    output logic                                 load_complete
);
    typedef enum logic {IDLE, UNPACK} state_t;
    state_t state;

    logic [AXIS_DATA_WIDTH-1:0] latched_word;
    logic [(AXIS_DATA_WIDTH/8)-1:0] latched_keep;
    logic latched_last;
    logic target_buf;
    logic packet_target;
    logic packet_manual;
    logic [1:0] byte_idx;
    logic [A_ADDR_WIDTH-1:0] a_addr_reg;
    logic [B_ADDR_WIDTH-1:0] b_addr_reg;

    always_comb begin
        s_axis_tready = (state == IDLE) && load_enable;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state          <= IDLE;
            latched_word   <= '0;
            latched_keep   <= '0;
            latched_last   <= 1'b0;
            target_buf     <= 1'b0;
            packet_target  <= 1'b0;
            packet_manual  <= 1'b0;
            byte_idx       <= '0;
            a_addr_reg     <= '0;
            b_addr_reg     <= '0;
            a_wr_en        <= 1'b0;
            a_wr_addr      <= '0;
            a_wr_data      <= '0;
            b_wr_en        <= 1'b0;
            b_wr_addr      <= '0;
            b_wr_data      <= '0;
            a_commit       <= 1'b0;
            b_commit       <= 1'b0;
            a_packet_bytes <= '0;
            b_packet_bytes <= '0;
            packet_overflow <= 1'b0;
            load_active    <= 1'b0;
            load_complete  <= 1'b0;
        end else begin
            a_wr_en       <= 1'b0;
            b_wr_en       <= 1'b0;
            a_commit      <= 1'b0;
            b_commit      <= 1'b0;
            load_complete <= 1'b0;

            case (state)
                IDLE: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        latched_word  <= s_axis_tdata;
                        latched_keep  <= s_axis_tkeep;
                        latched_last  <= s_axis_tlast;
                        byte_idx      <= 2'd0;
                        packet_manual <= stream_target_manual;
                        packet_target <= stream_target_manual ? stream_target : target_buf;
                        state         <= UNPACK;
                        load_active   <= 1'b1;
                    end
                end

                UNPACK: begin
                    if (latched_keep[byte_idx]) begin
                        if (!packet_target) begin
                            if (a_addr_reg < A_DEPTH_BYTES) begin
                                a_wr_en   <= 1'b1;
                                a_wr_addr <= a_addr_reg;
                                a_wr_data <= latched_word[byte_idx*8 +: DATA_WIDTH];
                                a_addr_reg <= a_addr_reg + 1'b1;
                            end else begin
                                packet_overflow <= 1'b1;
                            end
                        end else begin
                            if (b_addr_reg < B_DEPTH_BYTES) begin
                                b_wr_en   <= 1'b1;
                                b_wr_addr <= b_addr_reg;
                                b_wr_data <= latched_word[byte_idx*8 +: DATA_WIDTH];
                                b_addr_reg <= b_addr_reg + 1'b1;
                            end else begin
                                packet_overflow <= 1'b1;
                            end
                        end
                    end

                    if (byte_idx == 2'd3) begin
                        state <= IDLE;
                        if (latched_last) begin
                            load_active   <= 1'b0;
                            load_complete <= 1'b1;
                            if (!packet_target) begin
                                a_commit <= 1'b1;
                                a_packet_bytes <= a_addr_reg +
                                    ((latched_keep[byte_idx] && a_addr_reg < A_DEPTH_BYTES) ? 1'b1 : 1'b0);
                                a_addr_reg <= '0;
                                if (!packet_manual) target_buf <= 1'b1;
                            end else begin
                                b_commit <= 1'b1;
                                b_packet_bytes <= {1'b0, b_addr_reg} +
                                    ((latched_keep[byte_idx] && b_addr_reg < B_DEPTH_BYTES) ? 1'b1 : 1'b0);
                                b_addr_reg <= '0;
                                if (!packet_manual) target_buf <= 1'b0;
                            end
                        end
                    end else begin
                        byte_idx <= byte_idx + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
