`timescale 1ns / 1ps
`default_nettype none

module tb_accel_cache_mvm;
    localparam integer M = 18;
    localparam integer K = 19;
    localparam integer WEIGHT_BYTES = M * K;

    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic rst_n = 1'b0;

    logic [31:0] awaddr = '0, wdata = '0;
    logic [2:0] awprot = '0;
    logic awvalid = 1'b0, wvalid = 1'b0, bready = 1'b0;
    wire awready, wready, bvalid;
    wire [1:0] bresp;
    logic [3:0] wstrb = 4'hf;

    logic [31:0] s_data = '0;
    logic [3:0] s_keep = '0;
    logic s_valid = 1'b0, s_last = 1'b0;
    wire s_ready;
    wire [31:0] m_data;
    wire [3:0] m_keep;
    wire m_valid, m_last;
    logic m_ready = 1'b0;
    wire interrupt;

    logic signed [7:0] weights [0:WEIGHT_BYTES-1];
    logic signed [7:0] vector1 [0:K-1];
    logic signed [7:0] vector2 [0:K-1];
    integer expected [0:M-1];
    integer expected_output [0:M-1];
    integer output_count = 0;
    integer last_count = 0;
    integer ready_count = 0;
    integer row_idx, k_idx, word_idx, lane_idx;
    integer lhs, rhs;
    integer timeout_count;
    logic saw_last = 1'b0;

    // Match the board's full 16x16 LUT-only engine.
    accel_top #(.ARRAY_ROWS(16), .ARRAY_COLS(16), .ACC_WIDTH(20),
                .MAC_IMPL("LUT"), .DSP_PE_LIMIT(0)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awprot(awprot), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(32'b0), .s_axi_arprot(3'b0), .s_axi_arvalid(1'b0), .s_axi_arready(),
        .s_axi_rdata(), .s_axi_rresp(), .s_axi_rvalid(), .s_axi_rready(1'b0),
        .s_axis_tdata(s_data), .s_axis_tkeep(s_keep), .s_axis_tvalid(s_valid),
        .s_axis_tready(s_ready), .s_axis_tlast(s_last),
        .m_axis_tdata(m_data), .m_axis_tkeep(m_keep), .m_axis_tvalid(m_valid),
        .m_axis_tready(m_ready), .m_axis_tlast(m_last), .interrupt(interrupt)
    );

    always @(negedge clk) begin
        if (!rst_n) begin
            ready_count = 0;
            m_ready = 1'b0;
        end else begin
            ready_count = ready_count + 1;
            m_ready = ((ready_count % 5) != 0);
        end
    end

    always @(posedge clk) begin
        if (m_valid && m_ready) begin
            if (output_count < M)
                expected_output[output_count] <= m_data;
            output_count <= output_count + 1;
            if (m_last) begin
                saw_last <= 1'b1;
                last_count <= last_count + 1;
            end
        end
    end

    task automatic axi_write(input logic [31:0] addr, input logic [31:0] value);
        begin
            @(negedge clk);
            awaddr = addr;
            wdata = value;
            awvalid = 1'b1;
            wvalid = 1'b1;
            do @(posedge clk); while (!(awready && wready));
            @(negedge clk);
            awvalid = 1'b0;
            wvalid = 1'b0;
            bready = 1'b1;
            wait (bvalid === 1'b1);
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task automatic send_weights;
        reg [31:0] packed_word;
        reg [3:0] keep_word;
        integer position;
        integer word_count;
        begin
            word_count = (WEIGHT_BYTES + 3) / 4;
            for (word_idx = 0; word_idx < word_count; word_idx = word_idx + 1) begin
                packed_word = '0;
                keep_word = '0;
                for (lane_idx = 0; lane_idx < 4; lane_idx = lane_idx + 1) begin
                    position = word_idx * 4 + lane_idx;
                    if (position < WEIGHT_BYTES) begin
                        packed_word[lane_idx*8 +: 8] = weights[position];
                        keep_word[lane_idx] = 1'b1;
                    end
                end
                @(negedge clk);
                s_data = packed_word;
                s_keep = keep_word;
                s_last = (word_idx == word_count - 1);
                s_valid = 1'b1;
                do @(posedge clk); while (s_ready !== 1'b1);
                @(negedge clk);
                s_valid = 1'b0;
                s_last = 1'b0;
            end
        end
    endtask

    task automatic send_vector(input bit use_second);
        reg [31:0] packed_word;
        reg [3:0] keep_word;
        integer position;
        integer word_count;
        begin
            word_count = (K + 3) / 4;
            for (word_idx = 0; word_idx < word_count; word_idx = word_idx + 1) begin
                packed_word = '0;
                keep_word = '0;
                for (lane_idx = 0; lane_idx < 4; lane_idx = lane_idx + 1) begin
                    position = word_idx * 4 + lane_idx;
                    if (position < K) begin
                        packed_word[lane_idx*8 +: 8] = use_second ? vector2[position] : vector1[position];
                        keep_word[lane_idx] = 1'b1;
                    end
                end
                @(negedge clk);
                s_data = packed_word;
                s_keep = keep_word;
                s_last = (word_idx == word_count - 1);
                s_valid = 1'b1;
                do @(posedge clk); while (s_ready !== 1'b1);
                @(negedge clk);
                s_valid = 1'b0;
                s_last = 1'b0;
            end
        end
    endtask

    task automatic calculate_expected(input bit use_second);
        begin
            for (row_idx = 0; row_idx < M; row_idx = row_idx + 1) begin
                expected[row_idx] = 0;
                for (k_idx = 0; k_idx < K; k_idx = k_idx + 1) begin
                    lhs = weights[row_idx*K + k_idx];
                    rhs = use_second ? vector2[k_idx] : vector1[k_idx];
                    expected[row_idx] = expected[row_idx] + lhs * rhs;
                end
            end
        end
    endtask

    task automatic run_and_check(input bit use_second);
        begin
            calculate_expected(use_second);
            @(negedge clk);
            output_count = 0;
            last_count = 0;
            saw_last = 1'b0;
            axi_write(32'h00, 1);
            timeout_count = 0;
            while (!saw_last && timeout_count < 30000) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
            if (!saw_last)
                $fatal(1, "Timed out waiting for cached MVM output, second vector=%0b", use_second);
            timeout_count = 0;
            while (!dut.mvm_done && timeout_count < 20) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
            if (!dut.mvm_done)
                $fatal(1, "MVM output completed without top-level done");
            if (output_count != M)
                $fatal(1, "Cached MVM output length %0d, expected %0d", output_count, M);
            if (last_count != 1)
                $fatal(1, "Cached MVM output had %0d TLAST beats, expected one", last_count);
            for (row_idx = 0; row_idx < M; row_idx = row_idx + 1) begin
                if ($signed(expected_output[row_idx]) !== expected[row_idx])
                    $fatal(1, "Vector%0d row%0d mismatch: got %0d expected %0d",
                           use_second ? 2 : 1, row_idx, $signed(expected_output[row_idx]), expected[row_idx]);
            end
            if (!interrupt)
                $fatal(1, "Cached MVM completion interrupt did not assert");
        end
    endtask

    initial begin
        for (row_idx = 0; row_idx < M; row_idx = row_idx + 1)
            for (k_idx = 0; k_idx < K; k_idx = k_idx + 1)
                weights[row_idx*K + k_idx] = ((row_idx*3 + k_idx*5) % 15) - 7;
        for (k_idx = 0; k_idx < K; k_idx = k_idx + 1) begin
            vector1[k_idx] = (k_idx % 7) - 3;
            vector2[k_idx] = 4 - (k_idx % 9);
        end

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        axi_write(32'h08, M);
        axi_write(32'h0c, K);
        axi_write(32'h10, 1);
        axi_write(32'h14, 16);
        axi_write(32'h18, 1);
        axi_write(32'h24, 3); // cached MVM, manual packet target, A weights
        send_weights();
        wait (dut.a_loaded === 1'b1);
        if (dut.loaded_weight_m != M || dut.loaded_weight_k != K)
            $fatal(1, "Weight dimensions were not committed with the packet");

        axi_write(32'h24, 7); // cached MVM, manual packet target, B vector
        send_vector(1'b0);
        wait (dut.b_loaded === 1'b1);
        run_and_check(1'b0);
        if (!dut.a_loaded)
            $fatal(1, "Weight cache was invalidated after the first vector");

        send_vector(1'b1);
        wait (dut.b_loaded === 1'b1);
        run_and_check(1'b1);
        if (!dut.a_loaded || dut.packet_overflow)
            $fatal(1, "Weight reuse or packet status failed after the second vector");

        $display("[PASS] Cached 18x19 MVM crossed M/K tile tails and reused weights for two vectors");
        $finish;
    end
endmodule

`default_nettype wire
