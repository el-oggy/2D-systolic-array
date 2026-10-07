`timescale 1ns / 1ps

// ============================================================================
// Testbench: tb_adaptive_gemm
// Description: Comprehensive Self-Checking SystemVerilog Regression Testbench
//              for Adaptive Systolic Array Matrix Multiplier.
//              Verifies:
//              1. 16x16x16 Standard Matrix Multiplier
//              2. 3x3x3 Irregular Matrix with Zero-Padding
//              3. 5x7x5 Non-Square Irregular Matrix
//              4. 8x8x8 Sub-Tile Active Region
//              5. 10x13x10 Irregular Matrix
//              6. 16x32x16 Multi-K Partial-Sum Accumulation
//              7. 32x32x32 Full Multi-Tile Output-Stationary GEMM
//              Generates VCD waveform to results/adaptive_16x16_waveform.vcd
// ============================================================================

module tb_adaptive_gemm;

    localparam int ROWS       = 16;
    localparam int COLS       = 16;
    localparam int TILE_K     = 16;
    localparam int DATA_WIDTH = 8;
    localparam int ACC_WIDTH  = 32;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    reg start = 0;
    reg soft_reset = 0;
    reg [15:0] m_dim = 16, k_dim = 16, n_dim = 16;
    reg [7:0] active_m_in = 16, active_n_in = 16;

    wire busy, done, load_en, shift_en, array_en, clr_acc, c_capture;
    wire active_mask [0:ROWS-1][0:COLS-1];
    wire [15:0] curr_mt, curr_nt, curr_kt;
    wire [7:0] actual_m, actual_k, actual_n;
    wire [31:0] cycles_counter, tiles_counter;

    reg signed [DATA_WIDTH-1:0] mat_a [0:63][0:63];
    reg signed [DATA_WIDTH-1:0] mat_b [0:63][0:63];
    reg signed [ACC_WIDTH-1:0]  mat_c_golden [0:63][0:63];
    reg signed [ACC_WIDTH-1:0]  mat_c_hw [0:63][0:63];

    reg signed [DATA_WIDTH-1:0] a_tile [0:ROWS-1][0:TILE_K-1];
    reg signed [DATA_WIDTH-1:0] b_tile [0:TILE_K-1][0:COLS-1];
    wire signed [DATA_WIDTH-1:0] a_skewed [0:ROWS-1];
    wire signed [DATA_WIDTH-1:0] b_skewed [0:COLS-1];
    wire signed [ACC_WIDTH-1:0] c_out [0:ROWS-1][0:COLS-1];
    wire overflow;

    // Unit Under Test (UUT) - Controller
    tile_controller #(
        .ARRAY_ROWS (ROWS),
        .ARRAY_COLS (COLS),
        .TILE_K     (TILE_K)
    ) u_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .soft_reset     (soft_reset),
        .m_dim          (m_dim),
        .k_dim          (k_dim),
        .n_dim          (n_dim),
        .active_m_in    (active_m_in),
        .active_n_in    (active_n_in),
        .busy           (busy),
        .done           (done),
        .load_en        (load_en),
        .shift_en       (shift_en),
        .array_en       (array_en),
        .clr_acc        (clr_acc),
        .c_capture      (c_capture),
        .active_mask    (active_mask),
        .curr_mt        (curr_mt),
        .curr_nt        (curr_nt),
        .curr_kt        (curr_kt),
        .actual_m       (actual_m),
        .actual_k       (actual_k),
        .actual_n       (actual_n),
        .cycles_counter (cycles_counter),
        .tiles_counter  (tiles_counter)
    );

    // Skew Buffers
    skew_buffers #(
        .ARRAY_ROWS (ROWS),
        .ARRAY_COLS (COLS),
        .TILE_K     (TILE_K),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_skew (
        .clk        (clk),
        .rst_n      (rst_n),
        .load_en    (load_en),
        .shift_en   (shift_en),
        .actual_m   (actual_m),
        .actual_k   (actual_k),
        .actual_n   (actual_n),
        .a_tile_in  (a_tile),
        .b_tile_in  (b_tile),
        .a_skewed_o (a_skewed),
        .b_skewed_o (b_skewed)
    );

    // 2D Systolic Array Mesh
    systolic_array #(
        .ARRAY_ROWS (ROWS),
        .ARRAY_COLS (COLS),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .MAC_IMPL   ("DSP")
    ) u_mesh (
        .clk         (clk),
        .rst_n       (rst_n),
        .clr_acc     (clr_acc),
        .array_en    (array_en),
        .active_mask (active_mask),
        .a_in        (a_skewed),
        .b_in        (b_skewed),
        .c_out       (c_out),
        .overflow    (overflow)
    );

    // Synchronous memory feeder for the mesh simulation
    integer lr, lc, lk;
    always @(negedge clk) begin
        if (load_en) begin
            for (lr = 0; lr < ROWS; lr = lr + 1) begin
                for (lk = 0; lk < TILE_K; lk = lk + 1) begin
                    if (((curr_mt * ROWS + lr) < m_dim) && ((curr_kt * TILE_K + lk) < k_dim)) begin
                        a_tile[lr][lk] = mat_a[curr_mt * ROWS + lr][curr_kt * TILE_K + lk];
                    end else begin
                        a_tile[lr][lk] = 8'sd0;
                    end
                end
            end
            for (lk = 0; lk < TILE_K; lk = lk + 1) begin
                for (lc = 0; lc < COLS; lc = lc + 1) begin
                    if (((curr_kt * TILE_K + lk) < k_dim) && ((curr_nt * COLS + lc) < n_dim)) begin
                        b_tile[lk][lc] = mat_b[curr_kt * TILE_K + lk][curr_nt * COLS + lc];
                    end else begin
                        b_tile[lk][lc] = 8'sd0;
                    end
                end
            end
        end
    end

    // Capture C output
    integer cap_r, cap_c;
    always @(posedge clk) begin
        if (c_capture) begin
            for (cap_r = 0; cap_r < ROWS; cap_r = cap_r + 1) begin
                for (cap_c = 0; cap_c < COLS; cap_c = cap_c + 1) begin
                    if (((curr_mt * ROWS + cap_r) < m_dim) && ((curr_nt * COLS + cap_c) < n_dim)) begin
                        mat_c_hw[curr_mt * ROWS + cap_r][curr_nt * COLS + cap_c] <= c_out[cap_r][cap_c];
                    end
                end
            end
        end
    end

    integer ti, tj, tp, mismatches, total_mismatches;
    reg signed [63:0] g_sum;

    task run_test(input [127:0] t_name, input integer m, input integer k, input integer n, input integer am, input integer an);
    begin
        mismatches = 0;
        $display("------------------------------------------------------------------");
        $display("RUNNING: %0s | Shape: %0dx%0dx%0d | Active: %0dx%0d", t_name, m, k, n, am, an);

        // Reset accelerator between tests
        rst_n = 1'b0;
        start = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Pseudorandom input generation
        for (ti = 0; ti < m; ti = ti + 1)
            for (tj = 0; tj < k; tj = tj + 1)
                mat_a[ti][tj] = $signed(($urandom % 17) - 8);

        for (ti = 0; ti < k; ti = ti + 1)
            for (tj = 0; tj < n; tj = tj + 1)
                mat_b[ti][tj] = $signed(($urandom % 17) - 8);

        // Golden model computation
        for (ti = 0; ti < m; ti = ti + 1) begin
            for (tj = 0; tj < n; tj = tj + 1) begin
                g_sum = 0;
                for (tp = 0; tp < k; tp = tp + 1) begin
                    g_sum = g_sum + (mat_a[ti][tp] * mat_b[tp][tj]);
                end
                mat_c_golden[ti][tj] = g_sum[31:0];
            end
        end

        for (ti = 0; ti < 64; ti = ti + 1)
            for (tj = 0; tj < 64; tj = tj + 1)
                mat_c_hw[ti][tj] = 32'hdeadbeef;

        for (lr = 0; lr < ROWS; lr = lr + 1)
            for (lk = 0; lk < TILE_K; lk = lk + 1)
                a_tile[lr][lk] = 8'sd0;
        for (lk = 0; lk < TILE_K; lk = lk + 1)
            for (lc = 0; lc < COLS; lc = lc + 1)
                b_tile[lk][lc] = 8'sd0;

        @(posedge clk);
        m_dim       <= m[15:0];
        k_dim       <= k[15:0];
        n_dim       <= n[15:0];
        active_m_in <= am[7:0];
        active_n_in <= an[7:0];
        start       <= 1;

        @(posedge clk);
        start       <= 0;

        wait(busy == 1);
        wait(done == 1);
        #1;

        $display("  Hardware completed in %0d cycles (tiles = %0d)", cycles_counter, tiles_counter);

        for (ti = 0; ti < m; ti = ti + 1) begin
            for (tj = 0; tj < n; tj = tj + 1) begin
                if (mat_c_hw[ti][tj] !== mat_c_golden[ti][tj]) begin
                    if (mismatches < 5) begin
                        $display("  [FAIL] Mismatch at C[%0d][%0d]: HW = %0d, Golden = %0d",
                                 ti, tj, mat_c_hw[ti][tj], mat_c_golden[ti][tj]);
                    end
                    mismatches = mismatches + 1;
                end
            end
        end

        if (mismatches == 0) begin
            $display("  [PASS] %0s verified BIT-EXACT against golden model! (%0d elements checked)", t_name, m * n);
        end else begin
            $display("  [FAIL] %0s had %0d element mismatches.", t_name, mismatches);
            total_mismatches = total_mismatches + mismatches;
        end
        repeat (4) @(posedge clk);
    end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        start = 0;
        soft_reset = 0;
        m_dim = 16;
        k_dim = 16;
        n_dim = 16;
        active_m_in = 16;
        active_n_in = 16;
        total_mismatches = 0;

        // VCD waveform dump
        $dumpfile("results/adaptive_16x16_waveform.vcd");
        $dumpvars(0, tb_adaptive_gemm);

        #20;
        rst_n = 1;
        #20;

        $display("\n==================================================================");
        $display("   ADAPTIVE SYSTOLIC ARRAY HARDWARE VERIFICATION REGRESSION      ");
        $display("==================================================================");

        run_test("16x16x16 Baseline", 16, 16, 16, 16, 16);
        run_test("3x3x3 Small Irregular", 3, 3, 3, 3, 3);
        run_test("5x7x5 Irregular Non-Square", 5, 7, 5, 5, 5);
        run_test("8x8x8 Sub-Tile", 8, 8, 8, 8, 8);
        run_test("10x13x10 Irregular Matrix", 10, 13, 10, 10, 10);
        run_test("16x32x16 Multi-K Accumulation", 16, 32, 16, 16, 16);
        run_test("32x32x32 Full Multi-Tile GEMM", 32, 32, 32, 16, 16);

        $display("\n==================================================================");
        if (total_mismatches == 0) begin
            $display("   >>> ALL 7 BENCHMARK SUITES PASSED BIT-EXACTLY (0 ERRORS)! <<<  ");
        end else begin
            $display("   >>> REGRESSION FAILED WITH %0d TOTAL ERRORS. <<<", total_mismatches);
        end
        $display("==================================================================\n");
        $finish;
    end

endmodule
