`timescale 1ns / 1ps
`default_nettype none

module tb_accel_top_axis;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic rst_n = 1'b0;

    logic [31:0] awaddr = '0, wdata = '0, araddr = '0;
    logic [2:0] awprot = '0, arprot = '0;
    logic awvalid = 0, wvalid = 0, bready = 0;
    wire awready, wready, bvalid;
    wire [1:0] bresp;
    logic [3:0] wstrb = 4'hf;
    logic arvalid = 0, rready = 0;
    wire arready, rvalid;
    wire [31:0] rdata;
    wire [1:0] rresp;

    logic [31:0] s_data = '0;
    logic [3:0] s_keep = 4'hf;
    logic s_valid = 0, s_last = 0;
    wire s_ready;
    wire [31:0] m_data;
    wire [3:0] m_keep;
    wire m_valid, m_last;
    logic m_ready = 0;
    wire interrupt;

    accel_top #(.ARRAY_ROWS(16), .ARRAY_COLS(16), .ACC_WIDTH(20),
                .MAC_IMPL("HYBRID"), .DSP_PE_LIMIT(197)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awprot(awprot), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(arprot), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .s_axis_tdata(s_data), .s_axis_tkeep(s_keep), .s_axis_tvalid(s_valid),
        .s_axis_tready(s_ready), .s_axis_tlast(s_last),
        .m_axis_tdata(m_data), .m_axis_tkeep(m_keep), .m_axis_tvalid(m_valid),
        .m_axis_tready(m_ready), .m_axis_tlast(m_last), .interrupt(interrupt)
    );

    logic signed [7:0] matrix_a [0:255];
    logic signed [7:0] matrix_b [0:255];
    logic signed [31:0] expected [0:8];
    logic signed [31:0] output_words [0:8];
    integer output_count = 0;
    logic saw_last = 0;
    integer i, lane, word_idx;
    integer ready_count = 0;

    always @(negedge clk) begin
        if (!rst_n) begin
            ready_count = 0;
            m_ready = 0;
        end else begin
            ready_count = ready_count + 1;
            m_ready = ((ready_count % 4) != 0);
        end
    end

    always @(posedge clk) begin
        if (m_valid && m_ready) begin
            if (output_count < 9)
                output_words[output_count] <= m_data;
            output_count <= output_count + 1;
            if (m_last) saw_last <= 1'b1;
        end
    end

    task automatic axi_write(input logic [31:0] addr, input logic [31:0] value);
        begin
            @(negedge clk);
            awaddr = addr; wdata = value; awvalid = 1; wvalid = 1;
            do @(posedge clk); while (!(awready && wready));
            @(negedge clk);
            awvalid = 0; wvalid = 0; bready = 1;
            wait (bvalid === 1'b1);
            @(negedge clk); bready = 0;
        end
    endtask

    task automatic axi_write_aw_first(input logic [31:0] addr, input logic [31:0] value);
        begin
            @(negedge clk);
            awaddr = addr; awvalid = 1; wvalid = 0; bready = 0;
            do @(posedge clk); while (!awready);
            @(negedge clk); awvalid = 0;
            repeat (2) @(negedge clk);
            wdata = value; wstrb = 4'hf; wvalid = 1;
            do @(posedge clk); while (!wready);
            @(negedge clk); wvalid = 0; bready = 1;
            wait (bvalid === 1'b1);
            @(negedge clk); bready = 0;
        end
    endtask

    task automatic axi_write_w_first(input logic [31:0] addr, input logic [31:0] value);
        begin
            @(negedge clk);
            wdata = value; wstrb = 4'hf; wvalid = 1; awvalid = 0; bready = 0;
            do @(posedge clk); while (!wready);
            @(negedge clk); wvalid = 0;
            repeat (2) @(negedge clk);
            awaddr = addr; awvalid = 1;
            do @(posedge clk); while (!awready);
            @(negedge clk); awvalid = 0; bready = 1;
            wait (bvalid === 1'b1);
            @(negedge clk); bready = 0;
        end
    endtask

    task automatic send_packet(input bit send_b);
        reg [31:0] packed_word;
        begin
            for (word_idx = 0; word_idx < 64; word_idx = word_idx + 1) begin
                packed_word = '0;
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    if (send_b)
                        packed_word[lane*8 +: 8] = matrix_b[word_idx*4 + lane];
                    else
                        packed_word[lane*8 +: 8] = matrix_a[word_idx*4 + lane];
                end
                @(negedge clk);
                s_data = packed_word; s_keep = 4'hf; s_last = (word_idx == 63); s_valid = 1;
                do @(posedge clk); while (!s_ready);
                @(negedge clk); s_valid = 0; s_last = 0;
            end
        end
    endtask

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            matrix_a[i] = 0;
            matrix_b[i] = 0;
        end
        matrix_a[0] = -1; matrix_a[1] = 2; matrix_a[2] = 3;
        matrix_a[16] = 4; matrix_a[17] = -5; matrix_a[18] = 6;
        matrix_a[32] = 7; matrix_a[33] = 8; matrix_a[34] = -9;
        matrix_b[0] = 1; matrix_b[2] = 2;
        matrix_b[16+1] = 1;
        matrix_b[32] = 3; matrix_b[34] = 1;
        expected[0] = 8;   expected[1] = 2;  expected[2] = 1;
        expected[3] = 22;  expected[4] = -5; expected[5] = 14;
        expected[6] = -20; expected[7] = 8;  expected[8] = 5;

        repeat (5) @(posedge clk);
        rst_n = 1;
        axi_write_aw_first(32'h08, 3);
        axi_write_w_first(32'h0c, 3);
        axi_write(32'h10, 3);
        axi_write(32'h14, 3);
        axi_write(32'h18, 3);

        send_packet(1'b0);
        send_packet(1'b1);
        wait (!dut.invalid_shape);
        if (dut.u_a_pingpong.active_bank !== 1'b1 || dut.u_b_pingpong.active_bank !== 1'b1)
            $fatal(1, "First input packet commits did not swap both input banks");
        axi_write(32'h00, 1);

        // Change the programmed dimensions and stage the next tile while the
        // first job is prefetching/computing. The first job must use its
        // captured 3x3x3 shape and active input bank.
        axi_write(32'h08, 2);
        axi_write(32'h0c, 2);
        axi_write(32'h10, 2);
        axi_write(32'h14, 2);
        axi_write(32'h18, 2);
        for (i = 0; i < 256; i = i + 1) begin
            matrix_a[i] = 0;
            matrix_b[i] = 0;
        end
        matrix_a[0] = 2; matrix_a[1] = 3;
        matrix_a[16] = -1; matrix_a[17] = 4;
        matrix_b[0] = -2; matrix_b[1] = 1;
        matrix_b[16] = 5; matrix_b[17] = 2;
        send_packet(1'b0);
        send_packet(1'b1);

        fork
            begin wait (saw_last); end
            begin repeat (5000) @(posedge clk); $fatal(1, "Timeout waiting for first AXI result packet"); end
        join_any
        disable fork;
        if (output_count != 9 || !saw_last)
            $fatal(1, "Timed out waiting for 3x3 result packet; count=%0d last=%0b", output_count, saw_last);
        for (i = 0; i < 9; i = i + 1) begin
            if (output_words[i] !== expected[i])
                $fatal(1, "Output[%0d] mismatch: got %0d expected %0d", i, output_words[i], expected[i]);
        end
        if (!interrupt) $fatal(1, "Completion interrupt did not assert");
        if (dut.hw_cycles != 29) $fatal(1, "Expected 3x3 count including BRAM C capture (29), got %0d", dut.hw_cycles);
        wait (dut.a_loaded && dut.b_loaded);
        if (dut.u_a_pingpong.active_bank !== 1'b0 || dut.u_b_pingpong.active_bank !== 1'b0)
            $fatal(1, "Next input packets did not commit to the alternate banks");

        expected[0] = 11; expected[1] = 8;
        expected[2] = 22; expected[3] = 7;
        @(negedge clk); output_count = 0; saw_last = 0;
        wait (dut.prefetch_state == 3'd0 && dut.a_loaded && dut.b_loaded);
        axi_write(32'h00, 1);
        fork
            begin wait (saw_last); end
            begin repeat (5000) @(posedge clk); $fatal(1, "Timeout waiting for second AXI result packet"); end
        join_any
        disable fork;
        if (output_count != 4 || !saw_last)
            $fatal(1, "Second result packet length mismatch: count=%0d last=%0b lim=%0d,%0d actual=%0d,%0d cfg=%0d,%0d,%0d run=%0d,%0d,%0d", output_count, saw_last, dut.u_axis_out.lim_r, dut.u_axis_out.lim_c, dut.actual_m, dut.actual_n, dut.cfg_m_dim, dut.cfg_k_dim, dut.cfg_n_dim, dut.run_m_dim, dut.run_k_dim, dut.run_n_dim);
        for (i = 0; i < 4; i = i + 1) begin
            if (output_words[i] !== expected[i])
                $fatal(1, "Second output[%0d] mismatch: got %0d expected %0d", i, output_words[i], expected[i]);
        end
        if (dut.hw_cycles != 26) $fatal(1, "Expected 2x2x2 count including BRAM C capture (26), got %0d", dut.hw_cycles);

        // Problem-statement workload: an MxK matrix multiplied by a Kx1
        // vector. The one-column B layout exercises its strided tile reads.
        axi_write(32'h08, 3);
        axi_write(32'h0c, 3);
        axi_write(32'h10, 1);
        axi_write(32'h14, 3);
        axi_write(32'h18, 1);
        for (i = 0; i < 256; i = i + 1) begin
            matrix_a[i] = 0;
            matrix_b[i] = 0;
        end
        matrix_a[0] = -1; matrix_a[1] = 2; matrix_a[2] = 3;
        matrix_a[16] = 4; matrix_a[17] = -5; matrix_a[18] = 6;
        matrix_a[32] = 7; matrix_a[33] = 8; matrix_a[34] = -9;
        matrix_b[0] = 2;
        matrix_b[16] = -1;
        matrix_b[32] = 3;
        @(negedge clk); output_count = 0; saw_last = 0;
        send_packet(1'b0);
        send_packet(1'b1);
        wait (!dut.invalid_shape);
        axi_write(32'h00, 1);
        fork
            begin wait (saw_last); end
            begin repeat (5000) @(posedge clk); $fatal(1, "Timeout waiting for MVM AXI result packet"); end
        join_any
        disable fork;
        if (output_count != 3 || !saw_last)
            $fatal(1, "MVM result packet length mismatch: count=%0d last=%0b", output_count, saw_last);
        if (output_words[0] !== 5 || output_words[1] !== 31 || output_words[2] !== -21)
            $fatal(1, "MVM mismatch: got [%0d,%0d,%0d] expected [5,31,-21]",
                   output_words[0], output_words[1], output_words[2]);

        $display("[PASS] AXI top verified adjacent GEMM jobs and a 3x3-by-3x1 MVM on DSP_PE_LIMIT=197");
        $finish;
    end
endmodule

`default_nettype wire
