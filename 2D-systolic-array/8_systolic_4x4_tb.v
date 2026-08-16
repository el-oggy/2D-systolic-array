// ============================================================
// systolic_4x4_tb.v — Full System Testbench (4×4 matrices)
// ============================================================
// Tests the COMPLETE system: top-level wrapper with controller,
// skew buffers, and 4×4 systolic array.
//
// Test matrices:
//   A = | 1  2  3  4|    B = | 1  0  0  0|
//       | 5  6  7  8|        | 0  1  0  0|
//       | 9 10 11 12|        | 0  0  1  0|
//       |13 14 15 16|        | 0  0  0  1|
//
// B is the IDENTITY matrix, so C = A × B = A
// This makes verification trivial!
//
// Then we also test with non-trivial matrices:
//   A = |1 2 3 4|    B = |2 0 0 0|
//       |5 6 7 8|        |0 2 0 0|
//       |0 0 0 0|        |0 0 2 0|
//       |1 1 1 1|        |0 0 0 2|
//
// C = A × 2I = 2A (every element doubled)
// ============================================================

`timescale 1ns / 1ps

module systolic_4x4_tb;

    // ---- Parameters ----
    parameter N = 4;
    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10;

    // ---- Signals ----
    reg  clk, rst, start;
    reg  signed [DATA_WIDTH-1:0] matrix_a [0:N-1][0:N-1];
    reg  signed [DATA_WIDTH-1:0] matrix_b [0:N-1][0:N-1];
    wire signed [2*DATA_WIDTH-1:0] result [0:N-1][0:N-1];
    wire done;

    // Expected result storage
    reg signed [2*DATA_WIDTH-1:0] expected [0:N-1][0:N-1];

    // ---- Instantiate the Top-Level ----
    systolic_top #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .matrix_a(matrix_a),
        .matrix_b(matrix_b),
        .result(result),
        .done(done)
    );

    // ---- Clock Generator ----
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Dump waveforms ----
    initial begin
        $dumpfile("systolic_4x4_tb.vcd");
        $dumpvars(0, systolic_4x4_tb);
    end

    // ---- Helper: compute expected result in software ----
    task compute_expected;
        integer i, j, k;
        begin
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    expected[i][j] = 0;
                    for (k = 0; k < N; k = k + 1)
                        expected[i][j] = expected[i][j] + matrix_a[i][k] * matrix_b[k][j];
                end
        end
    endtask

    // ---- Helper: check results ----
    integer pass_count;
    integer fail_count;
    task check_results;
        input [8*20-1:0] test_name;  // String name for the test
        integer i, j;
        begin
            pass_count = 0;
            fail_count = 0;
            $display("\n  Results for %0s:", test_name);
            $display("  ┌────────────────────────────────────────┐");
            for (i = 0; i < N; i = i + 1) begin
                $write("  │ ");
                for (j = 0; j < N; j = j + 1) begin
                    if (result[i][j] == expected[i][j]) begin
                        $write("%5d ", result[i][j]);
                        pass_count = pass_count + 1;
                    end else begin
                        $write("%5d!", result[i][j]);
                        fail_count = fail_count + 1;
                    end
                end
                $display("│");
            end
            $display("  └────────────────────────────────────────┘");

            if (fail_count == 0)
                $display("  >>> PASS! All %0d elements correct <<<", pass_count);
            else
                $display("  >>> FAIL! %0d/%0d elements wrong <<<", fail_count, pass_count + fail_count);
        end
    endtask

    // ---- Helper: print matrix ----
    task print_matrix;
        input [8*20-1:0] name;
        integer i, j;
        begin
            $display("  %0s:", name);
            for (i = 0; i < N; i = i + 1) begin
                $write("    | ");
                for (j = 0; j < N; j = j + 1)
                    $write("%3d ", matrix_a[i][j]);
                $display("|");
            end
        end
    endtask

    // ---- Main Test Sequence ----
    integer i, j;
    initial begin
        $display("================================================");
        $display("  4×4 Systolic Array — Full System Test");
        $display("================================================");

        // ---- RESET ----
        rst   = 1;
        start = 0;
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                matrix_a[i][j] = 0;
                matrix_b[i][j] = 0;
            end

        repeat(3) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // ============================================
        // TEST 1: A × Identity = A
        // ============================================
        $display("\n────────────────────────────────────────────");
        $display("  TEST 1: A × I = A (identity matrix test)");
        $display("────────────────────────────────────────────");

        // Load A = |1 2 3 4| |5 6 7 8| |9 10 11 12| |13 14 15 16|
        matrix_a[0][0]=1;  matrix_a[0][1]=2;  matrix_a[0][2]=3;  matrix_a[0][3]=4;
        matrix_a[1][0]=5;  matrix_a[1][1]=6;  matrix_a[1][2]=7;  matrix_a[1][3]=8;
        matrix_a[2][0]=9;  matrix_a[2][1]=10; matrix_a[2][2]=11; matrix_a[2][3]=12;
        matrix_a[3][0]=13; matrix_a[3][1]=14; matrix_a[3][2]=15; matrix_a[3][3]=16;

        // Load B = Identity
        matrix_b[0][0]=1; matrix_b[0][1]=0; matrix_b[0][2]=0; matrix_b[0][3]=0;
        matrix_b[1][0]=0; matrix_b[1][1]=1; matrix_b[1][2]=0; matrix_b[1][3]=0;
        matrix_b[2][0]=0; matrix_b[2][1]=0; matrix_b[2][2]=1; matrix_b[2][3]=0;
        matrix_b[3][0]=0; matrix_b[3][1]=0; matrix_b[3][2]=0; matrix_b[3][3]=1;

        compute_expected;

        // Start computation
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for done
        wait(done == 1);
        @(posedge clk);

        check_results("A x Identity");

        $display("\n  Expected (should equal A):");
        for (i = 0; i < N; i = i + 1) begin
            $write("    | ");
            for (j = 0; j < N; j = j + 1)
                $write("%5d ", expected[i][j]);
            $display("|");
        end

        // ============================================
        // TEST 2: A × 2I = 2A (scalar multiply test)
        // ============================================
        $display("\n────────────────────────────────────────────");
        $display("  TEST 2: A × 2I = 2A (double every element)");
        $display("────────────────────────────────────────────");

        // Keep A the same, change B to 2*Identity
        matrix_b[0][0]=2; matrix_b[0][1]=0; matrix_b[0][2]=0; matrix_b[0][3]=0;
        matrix_b[1][0]=0; matrix_b[1][1]=2; matrix_b[1][2]=0; matrix_b[1][3]=0;
        matrix_b[2][0]=0; matrix_b[2][1]=0; matrix_b[2][2]=2; matrix_b[2][3]=0;
        matrix_b[3][0]=0; matrix_b[3][1]=0; matrix_b[3][2]=0; matrix_b[3][3]=2;

        compute_expected;

        // Reset and restart — need enough cycles for array_rst to clear accumulators
        rst = 1;
        repeat(3) @(posedge clk);
        rst = 0;
        @(posedge clk);

        start = 1;
        @(posedge clk);
        start = 0;

        wait(done == 1);
        @(posedge clk);

        check_results("A x 2I");

        // ============================================
        // TEST 3: General matrix multiplication
        // ============================================
        $display("\n────────────────────────────────────────────");
        $display("  TEST 3: General 4×4 matrix multiply");
        $display("────────────────────────────────────────────");

        matrix_a[0][0]=1; matrix_a[0][1]=2; matrix_a[0][2]=0; matrix_a[0][3]=1;
        matrix_a[1][0]=0; matrix_a[1][1]=1; matrix_a[1][2]=3; matrix_a[1][3]=0;
        matrix_a[2][0]=2; matrix_a[2][1]=0; matrix_a[2][2]=1; matrix_a[2][3]=4;
        matrix_a[3][0]=1; matrix_a[3][1]=1; matrix_a[3][2]=1; matrix_a[3][3]=1;

        matrix_b[0][0]=2; matrix_b[0][1]=1; matrix_b[0][2]=0; matrix_b[0][3]=3;
        matrix_b[1][0]=0; matrix_b[1][1]=3; matrix_b[1][2]=1; matrix_b[1][3]=0;
        matrix_b[2][0]=1; matrix_b[2][1]=0; matrix_b[2][2]=2; matrix_b[2][3]=1;
        matrix_b[3][0]=3; matrix_b[3][1]=2; matrix_b[3][2]=0; matrix_b[3][3]=1;

        compute_expected;

        $display("  Matrix A:");
        for (i = 0; i < N; i = i + 1) begin
            $write("    | ");
            for (j = 0; j < N; j = j + 1)
                $write("%3d ", matrix_a[i][j]);
            $display("|");
        end
        $display("  Matrix B:");
        for (i = 0; i < N; i = i + 1) begin
            $write("    | ");
            for (j = 0; j < N; j = j + 1)
                $write("%3d ", matrix_b[i][j]);
            $display("|");
        end
        $display("  Expected C = A × B:");
        for (i = 0; i < N; i = i + 1) begin
            $write("    | ");
            for (j = 0; j < N; j = j + 1)
                $write("%5d ", expected[i][j]);
            $display("|");
        end

        // Reset and restart — need enough cycles for array_rst to clear accumulators
        rst = 1;
        repeat(3) @(posedge clk);
        rst = 0;
        @(posedge clk);

        start = 1;
        @(posedge clk);
        start = 0;

        wait(done == 1);
        @(posedge clk);

        check_results("General 4x4");

        // ============================================
        // SUMMARY
        // ============================================
        $display("\n================================================");
        $display("  ALL TESTS COMPLETE!");
        $display("================================================\n");

        repeat(3) @(posedge clk);
        $finish;
    end

    // ---- Timeout watchdog ----
    initial begin
        #100000;
        $display("ERROR: Simulation timed out!");
        $finish;
    end

endmodule
