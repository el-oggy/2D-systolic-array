`timescale 1ns / 1ps
`default_nettype none

module tb_ping_pong_bram;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic wr_en = 1'b0;
    logic [3:0] wr_addr = 0;
    logic [7:0] wr_data = 0;
    logic commit = 1'b0;
    logic rd_en = 1'b0;
    logic [3:0] rd_addr = 0;
    wire [7:0] rd_data;
    wire active_bank;
    integer i;
    integer errors = 0;

    always #5 clk = ~clk;

    ping_pong_bram #(.DATA_WIDTH(8), .DEPTH(16), .ADDR_WIDTH(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .commit(commit), .rd_en(rd_en), .rd_addr(rd_addr),
        .rd_data(rd_data), .active_bank(active_bank)
    );

    task automatic read_and_check(input logic [3:0] addr, input logic [7:0] expected);
        begin
            @(negedge clk);
            rd_en = 1'b1;
            rd_addr = addr;
            @(posedge clk);
            #1;
            if (rd_data !== expected) begin
                $display("[FAIL] addr %0d: got %0d expected %0d", addr, rd_data, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Fill inactive bank 1, then atomically publish it.
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk);
            wr_en = 1'b1;
            wr_addr = i[3:0];
            wr_data = (8'd40 + i);
            @(posedge clk);
        end
        @(negedge clk);
        wr_en = 1'b0;
        commit = 1'b1;
        @(posedge clk);
        #1;
        if (active_bank !== 1'b1) begin
            $display("[FAIL] First commit did not select bank 1");
            errors = errors + 1;
        end

        // Read the active bank while filling the other bank concurrently.
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk);
            commit = 1'b0;
            rd_en = 1'b1;
            rd_addr = i[3:0];
            wr_en = 1'b1;
            wr_addr = i[3:0];
            wr_data = (8'd90 + i);
            @(posedge clk);
            #1;
            if (rd_data !== (8'd40 + i)) begin
                $display("[FAIL] Concurrent read addr %0d: got %0d expected %0d", i, rd_data, 40+i);
                errors = errors + 1;
            end
        end

        @(negedge clk);
        wr_en = 1'b0;
        rd_en = 1'b0;
        commit = 1'b1;
        @(posedge clk);
        #1;
        if (active_bank !== 1'b0) begin
            $display("[FAIL] Second commit did not select bank 0");
            errors = errors + 1;
        end
        @(negedge clk);
        commit = 1'b0;
        read_and_check(4'd0, 8'd90);
        read_and_check(4'd15, 8'd105);

        if (errors == 0)
            $display("[PASS] Ping-pong tile-bank swap and concurrent read/write checks passed.");
        else
            $display("[FAIL] Ping-pong tile-buffer errors: %0d", errors);
        $finish(errors != 0);
    end
endmodule

`default_nettype wire
