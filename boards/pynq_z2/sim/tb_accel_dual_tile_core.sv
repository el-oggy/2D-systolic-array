`timescale 1ns / 1ps
`default_nettype none

module tb_accel_dual_tile_core;
    localparam int ROWS = 16;
    localparam int COLS = 16;
    localparam int TILE_K = 16;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic start = 1'b0;
    logic [15:0] m_dim = 16'd3;
    logic [15:0] k_dim = 16'd3;
    logic [15:0] n_dim = 16'd3;
    logic [7:0] active_m = 8'd3;
    logic [7:0] active_n = 8'd3;
    logic signed [7:0] a_0 [0:ROWS-1][0:TILE_K-1];
    logic signed [7:0] b_0 [0:TILE_K-1][0:COLS-1];
    logic signed [7:0] a_1 [0:ROWS-1][0:TILE_K-1];
    logic signed [7:0] b_1 [0:TILE_K-1][0:COLS-1];
    wire signed [31:0] c_0 [0:ROWS-1][0:COLS-1];
    wire signed [31:0] c_1 [0:ROWS-1][0:COLS-1];
    wire busy, done, overflow_0, overflow_1, invalid_shape;
    wire [31:0] cycles_counter, tiles_counter;
    integer expected_0 [0:ROWS-1][0:COLS-1];
    integer expected_1 [0:ROWS-1][0:COLS-1];
    integer r, c, k, errors;

    always #5 clk = ~clk;

    accel_dual_tile_core dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .m_dim(m_dim), .k_dim(k_dim), .n_dim(n_dim),
        .active_m(active_m), .active_n(active_n),
        .a_tile_0(a_0), .b_tile_0(b_0), .a_tile_1(a_1), .b_tile_1(b_1),
        .c_tile_0(c_0), .c_tile_1(c_1),
        .busy(busy), .done(done), .overflow_0(overflow_0), .overflow_1(overflow_1),
        .invalid_shape(invalid_shape), .cycles_counter(cycles_counter), .tiles_counter(tiles_counter)
    );

    task automatic run_shape(input integer m, input integer kk, input integer n,
                             input integer am, input integer an, input integer extreme);
        begin
            m_dim = m;
            k_dim = kk;
            n_dim = n;
            active_m = am;
            active_n = an;
            for (r = 0; r < ROWS; r = r + 1) begin
                for (k = 0; k < TILE_K; k = k + 1) begin
                    a_0[r][k] = extreme ? -128 : (((r + 2*k) % 5) - 2);
                    a_1[r][k] = extreme ? -128 : (((2*r + k) % 7) - 3);
                end
            end
            for (k = 0; k < TILE_K; k = k + 1) begin
                for (c = 0; c < COLS; c = c + 1) begin
                    b_0[k][c] = extreme ? -128 : (((2*k + c) % 3) - 1);
                    b_1[k][c] = extreme ? -128 : (((k + 2*c) % 5) - 2);
                end
            end
            for (r = 0; r < ROWS; r = r + 1) begin
                for (c = 0; c < COLS; c = c + 1) begin
                    expected_0[r][c] = 0;
                    expected_1[r][c] = 0;
                    if (r < am && c < an)
                        for (k = 0; k < kk; k = k + 1) begin
                            expected_0[r][c] = expected_0[r][c] + a_0[r][k] * b_0[k][c];
                            expected_1[r][c] = expected_1[r][c] + a_1[r][k] * b_1[k][c];
                        end
                end
            end

            rst_n = 1'b0;
            start = 1'b0;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait (done);
            #1;

            if (invalid_shape) begin
                $display("[FAIL] Shape %0dx%0dx%0d was rejected", m, kk, n);
                errors = errors + 1;
            end
            for (r = 0; r < m; r = r + 1) begin
                for (c = 0; c < n; c = c + 1) begin
                    if (c_0[r][c] !== expected_0[r][c]) begin
                        $display("[FAIL] Engine 0 %0dx%0dx%0d C[%0d][%0d]: got %0d expected %0d", m, kk, n, r, c, c_0[r][c], expected_0[r][c]);
                        errors = errors + 1;
                    end
                    if (c_1[r][c] !== expected_1[r][c]) begin
                        $display("[FAIL] Engine 1 %0dx%0dx%0d C[%0d][%0d]: got %0d expected %0d", m, kk, n, r, c, c_1[r][c], expected_1[r][c]);
                        errors = errors + 1;
                    end
                end
            end
            if (overflow_0 || overflow_1) begin
                $display("[FAIL] Unexpected overflow for %0dx%0dx%0d", m, kk, n);
                errors = errors + 1;
            end
            $display("[INFO] Dual core %0dx%0dx%0d completed in %0d cycles", m, kk, n, cycles_counter);
        end
    endtask

    initial begin
        errors = 0;
        run_shape(3, 3, 3, 3, 3, 0);
        run_shape(16, 16, 16, 16, 16, 0);
        run_shape(16, 16, 16, 8, 6, 0);
        run_shape(16, 16, 16, 16, 16, 1);
        if (errors == 0)
            $display("[PASS] Dual tile core produced bit-exact DSP/LUT results, including signed int8 extremes at K=16.");
        else
            $display("[FAIL] Dual tile core had %0d errors.", errors);
        $finish(errors != 0);
    end
endmodule

`default_nettype wire
