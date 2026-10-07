`timescale 1ns / 1ps
`default_nettype none

module tb_skew_buffers;
    localparam int ROWS = 4;
    localparam int COLS = 4;
    localparam int K = 4;
    localparam int WIDTH = 8;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic load_en = 1'b0;
    logic shift_en = 1'b0;
    logic [7:0] actual_m = 8'd3;
    logic [7:0] actual_k = 8'd3;
    logic [7:0] actual_n = 8'd2;
    logic signed [WIDTH-1:0] a_tile [0:ROWS-1][0:K-1];
    logic signed [WIDTH-1:0] b_tile [0:K-1][0:COLS-1];
    wire signed [WIDTH-1:0] a_skewed [0:ROWS-1];
    wire signed [WIDTH-1:0] b_skewed [0:COLS-1];
    int errors = 0;

    always #5 clk = ~clk;

    skew_buffers #(
        .ARRAY_ROWS(ROWS), .ARRAY_COLS(COLS), .TILE_K(K), .DATA_WIDTH(WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n), .load_en(load_en), .shift_en(shift_en),
        .actual_m(actual_m), .actual_k(actual_k), .actual_n(actual_n),
        .a_tile_in(a_tile), .b_tile_in(b_tile),
        .a_skewed_o(a_skewed), .b_skewed_o(b_skewed)
    );

    initial begin
        for (int r = 0; r < ROWS; r++)
            for (int k = 0; k < K; k++)
                a_tile[r][k] = 8'sd10 + r * 8'sd10 + k;
        for (int k = 0; k < K; k++)
            for (int c = 0; c < COLS; c++)
                b_tile[k][c] = 8'sd50 + k * 8'sd10 + c;

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        load_en = 1'b1;
        @(negedge clk);
        load_en = 1'b0;
        shift_en = 1'b1;

        // Check every skewed value and inactive padding through the drain.
        for (int cycle = 0; cycle < ROWS + COLS + K; cycle++) begin
            @(posedge clk);
            #1;
            for (int r = 0; r < ROWS; r++) begin
                logic signed [WIDTH-1:0] expected_a;
                expected_a = ((r < actual_m) && (cycle >= r) &&
                              (cycle < r + actual_k))
                    ? (8'sd10 + r * 8'sd10 + (cycle - r)) : '0;
                if (a_skewed[r] !== expected_a) begin
                    $fatal(1,"A skew mismatch cycle=%0d row=%0d expected=%0d got=%0d",
                           cycle, r, expected_a, a_skewed[r]);
                    errors++;
                end
            end
            for (int c = 0; c < COLS; c++) begin
                logic signed [WIDTH-1:0] expected_b;
                expected_b = ((c < actual_n) && (cycle >= c) &&
                              (cycle < c + actual_k))
                    ? (8'sd50 + (cycle - c) * 8'sd10 + c) : '0;
                if (b_skewed[c] !== expected_b) begin
                    $fatal(1,"B skew mismatch cycle=%0d col=%0d expected=%0d got=%0d",
                           cycle, c, expected_b, b_skewed[c]);
                    errors++;
                end
            end
        end

        shift_en = 1'b0;
        if (errors == 0)
            $display("[PASS] Compact skew buffers match row/column delays and partial-tile zero padding.");
        else
            $fatal(1, "Skew-buffer test failed with %0d errors", errors);
        $finish;
    end
endmodule

`default_nettype wire
