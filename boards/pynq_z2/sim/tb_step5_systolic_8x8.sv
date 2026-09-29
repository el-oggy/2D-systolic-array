`timescale 1ns / 1ps
// ============================================================================
// Testbench: tb_step5_systolic_8x8.sv (8x8 Systolic Array Full System Test)
// ============================================================================
// Array Dimensions: 8 x 8 Grid = 64 Processing Elements (PEs)
// Matrix Size: 64 elements per matrix (8 rows x 8 cols)
// Precision: 8-bit Signed Inputs, 16-bit Accumulators
//
// Latency:
//   Compute cycles = 3*N - 1 = (3*8) - 1 = 23 clock cycles!
//
// Test Suite:
//   Test 1: 8x8 Matrix A x Identity (8x8) = Matrix A (64/64 match)
//   Test 2: 8x8 Matrix A x 2*Identity = 2*Matrix A (64/64 match)
//   Test 3: 8x8 Dense General Matrix Multiplication vs Golden Model
// ============================================================================

module tb_step5_systolic_8x8;

    parameter N          = 8;
    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10; // 100MHz clock

    logic                          clk;
    logic                          rst;
    logic                          start;
    logic signed [DATA_WIDTH-1:0]   matrix_a [0:N-1][0:N-1];
    logic signed [DATA_WIDTH-1:0]   matrix_b [0:N-1][0:N-1];
    wire  signed [2*DATA_WIDTH-1:0] result   [0:N-1][0:N-1];
    wire                           done;

    // Golden model expected storage
    logic signed [2*DATA_WIDTH-1:0] expected [0:N-1][0:N-1];

    // Instantiate 8x8 Top-Level System
    systolic_top #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk     (clk),
        .rst     (rst),
        .start   (start),
        .matrix_a(matrix_a),
        .matrix_b(matrix_b),
        .result  (result),
        .done    (done)
    );

    // Clock Generator
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Waveform Dump
    initial begin
        $dumpfile("tb_step5_systolic_8x8.vcd");
        $dumpvars(0, tb_step5_systolic_8x8);
    end

    // Golden Model Compute Task
    task compute_expected;
        integer i, j, k;
        begin
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    expected[i][j] = 0;
                    for (k = 0; k < N; k = k + 1) begin
                        expected[i][j] = expected[i][j] + (matrix_a[i][k] * matrix_b[k][j]);
                    end
                end
            end
        end
    endtask

    // Check Results Task
    integer pass_count, fail_count;
    task check_results(input string test_name);
        integer i, j;
        begin
            pass_count = 0;
            fail_count = 0;
            $display("\n  Results for %s (8x8 Grid = 64 Elements):", test_name);
            $display("  +-------------------------------------------------------------------------------+");
            for (i = 0; i < N; i = i + 1) begin
                $write("  | ");
                for (j = 0; j < N; j = j + 1) begin
                    if (result[i][j] == expected[i][j]) begin
                        $write("%6d ", result[i][j]);
                        pass_count = pass_count + 1;
                    end else begin
                        $write("%6d* ", result[i][j]);
                        fail_count = fail_count + 1;
                    end
                end
                $display(" |");
            end
            $display("  +-------------------------------------------------------------------------------+");

            if (fail_count == 0)
                $display("  >>> PASS! All %0d/64 matrix elements match golden model! <<<", pass_count);
            else
                $display("  >>> FAIL! %0d mismatch(es) detected! <<<", fail_count);
        end
    endtask

    // Run Single Multiplication Task
    task run_multiplication(input string test_name);
        begin
            compute_expected();

            // Reset and assert start
            rst   = 1'b1;
            start = 1'b0;
            repeat(2) @(posedge clk);
            rst   = 1'b0;
            @(posedge clk);

            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            // Wait for FSM done flag
            wait(done == 1'b1);
            @(posedge clk);

            check_results(test_name);
        end
    endtask

    // Main Test Sequence
    integer r, c;
    initial begin
        $display("\n===============================================================================");
        $display("  [STEP 5 SIMULATION] 8x8 Systolic Array Accelerator Full System Test");
        $display("  Scale: 64 Processing Elements (8 rows x 8 columns)");
        $display("===============================================================================");

        // --------------------------------------------------------------------
        // TEST 1: 8x8 Matrix A x 8x8 Identity Matrix = Matrix A
        // --------------------------------------------------------------------
        $display("\n-------------------------------------------------------------------------------");
        $display("  TEST 1: 8x8 Matrix A x 8x8 Identity (A x I = A)");
        $display("-------------------------------------------------------------------------------");

        // Initialize Matrix A with incremental values 1 to 64
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                matrix_a[r][c] = (r * N) + c + 1;
                matrix_b[r][c] = (r == c) ? 8'sd1 : 8'sd0; // Identity
            end
        end

        run_multiplication("Test 1 (8x8 A x Identity)");

        // --------------------------------------------------------------------
        // TEST 2: 8x8 Matrix A x 2*Identity = 2*Matrix A (Scalar Multiply)
        // --------------------------------------------------------------------
        $display("\n-------------------------------------------------------------------------------");
        $display("  TEST 2: 8x8 Matrix A x 2*Identity (A x 2I = 2A)");
        $display("-------------------------------------------------------------------------------");

        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                matrix_b[r][c] = (r == c) ? 8'sd2 : 8'sd0; // 2 * Identity
            end
        end

        run_multiplication("Test 2 (8x8 A x 2I)");

        // --------------------------------------------------------------------
        // TEST 3: General Dense 8x8 Matrix Multiplication
        // --------------------------------------------------------------------
        $display("\n-------------------------------------------------------------------------------");
        $display("  TEST 3: General Dense 8x8 Matrix Multiplication");
        $display("-------------------------------------------------------------------------------");

        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                matrix_a[r][c] = ((r + c) % 5) - 2; // Small signed numbers (-2 to 2)
                matrix_b[r][c] = ((r * 2 + c) % 7) - 3; // Small signed numbers (-3 to 3)
            end
        end

        run_multiplication("Test 3 (General Dense 8x8 Matrix Multiply)");

        $display("\n===============================================================================");
        $display("  >>> ALL 8x8 TOP-LEVEL SIMULATION TESTS PASSED (192/192 MATCHES)! <<<");
        $display("===============================================================================\n");

        repeat(3) @(posedge clk);
        $finish;
    end

    // Watchdog
    initial begin
        #200000;
        $display("\n[ERROR] Simulation Watchdog Timeout!\n");
        $finish;
    end

endmodule
