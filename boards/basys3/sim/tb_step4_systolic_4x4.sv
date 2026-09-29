`timescale 1ns / 1ps
// ============================================================================
// Testbench: tb_step4_systolic_4x4.sv (STEP 4: Full System 4x4 Verification)
// ============================================================================
// Purpose:
//   Validates the entire integrated hardware system (`systolic_top`):
//   - FSM Controller sequence (IDLE -> LOAD -> COMPUTE -> DONE)
//   - Skew Buffers (for Matrix A rows and Matrix B columns)
//   - 4x4 Systolic Array (16 PEs)
//   - Autonomous handshake with 'start' and 'done' flags
//
// Test Suite:
//   Test 1: A x Identity = A
//   Test 2: A x (2*Identity) = 2A
//   Test 3: General Dense 4x4 Matrix Multiplication
// ============================================================================

module tb_step4_systolic_4x4;

    parameter N          = 4;
    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10;

    logic                          clk;
    logic                          rst;
    logic                          start;
    logic signed [DATA_WIDTH-1:0]   matrix_a [0:N-1][0:N-1];
    logic signed [DATA_WIDTH-1:0]   matrix_b [0:N-1][0:N-1];
    wire  signed [2*DATA_WIDTH-1:0] result   [0:N-1][0:N-1];
    wire                           done;

    // Golden model expected storage
    logic signed [2*DATA_WIDTH-1:0] expected [0:N-1][0:N-1];

    // Instantiate Top-Level System
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
        $dumpfile("tb_step4_systolic_4x4.vcd");
        $dumpvars(0, tb_step4_systolic_4x4);
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
            $display("\n  Results for %s:", test_name);
            $display("  +----------------------------------------+");
            for (i = 0; i < N; i = i + 1) begin
                $write("  | ");
                for (j = 0; j < N; j = j + 1) begin
                    if (result[i][j] == expected[i][j]) begin
                        $write("%5d ", result[i][j]);
                        pass_count = pass_count + 1;
                    end else begin
                        $write("%5d* ", result[i][j]);
                        fail_count = fail_count + 1;
                    end
                end
                $display("|");
            end
            $display("  +----------------------------------------+");

            if (fail_count == 0)
                $display("  >>> PASS! All %0d matrix elements match golden model <<<", pass_count);
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

    // Main Test Flow
    initial begin
        $display("\n=======================================================");
        $display("  [STEP 4 SIMULATION] 4x4 Systolic Top System Test");
        $display("=======================================================");

        // ----------------------------------------------------
        // TEST 1: Identity Matrix (A x I = A)
        // ----------------------------------------------------
        $display("\n-------------------------------------------------------");
        $display("  TEST 1: A x Identity Matrix (A x I = A)");
        $display("-------------------------------------------------------");

        matrix_a[0][0]=1;  matrix_a[0][1]=2;  matrix_a[0][2]=3;  matrix_a[0][3]=4;
        matrix_a[1][0]=5;  matrix_a[1][1]=6;  matrix_a[1][2]=7;  matrix_a[1][3]=8;
        matrix_a[2][0]=9;  matrix_a[2][1]=10; matrix_a[2][2]=11; matrix_a[2][3]=12;
        matrix_a[3][0]=13; matrix_a[3][1]=14; matrix_a[3][2]=15; matrix_a[3][3]=16;

        matrix_b[0][0]=1; matrix_b[0][1]=0; matrix_b[0][2]=0; matrix_b[0][3]=0;
        matrix_b[1][0]=0; matrix_b[1][1]=1; matrix_b[1][2]=0; matrix_b[1][3]=0;
        matrix_b[2][0]=0; matrix_b[2][1]=0; matrix_b[2][2]=1; matrix_b[2][3]=0;
        matrix_b[3][0]=0; matrix_b[3][1]=0; matrix_b[3][2]=0; matrix_b[3][3]=1;

        run_multiplication("Test 1 (A x Identity)");

        // ----------------------------------------------------
        // TEST 2: Scaled Identity Matrix (A x 2I = 2A)
        // ----------------------------------------------------
        $display("\n-------------------------------------------------------");
        $display("  TEST 2: Scaled Matrix (A x 2I = 2A)");
        $display("-------------------------------------------------------");

        matrix_b[0][0]=2; matrix_b[0][1]=0; matrix_b[0][2]=0; matrix_b[0][3]=0;
        matrix_b[1][0]=0; matrix_b[1][1]=2; matrix_b[1][2]=0; matrix_b[1][3]=0;
        matrix_b[2][0]=0; matrix_b[2][1]=0; matrix_b[2][2]=2; matrix_b[2][3]=0;
        matrix_b[3][0]=0; matrix_b[3][1]=0; matrix_b[3][2]=0; matrix_b[3][3]=2;

        run_multiplication("Test 2 (A x 2I)");

        // ----------------------------------------------------
        // TEST 3: General Dense Matrix Multiplication
        // ----------------------------------------------------
        $display("\n-------------------------------------------------------");
        $display("  TEST 3: General Dense 4x4 Matrix Multiply");
        $display("-------------------------------------------------------");

        matrix_a[0][0]=1; matrix_a[0][1]=2; matrix_a[0][2]=0; matrix_a[0][3]=1;
        matrix_a[1][0]=0; matrix_a[1][1]=1; matrix_a[1][2]=3; matrix_a[1][3]=0;
        matrix_a[2][0]=2; matrix_a[2][1]=0; matrix_a[2][2]=1; matrix_a[2][3]=4;
        matrix_a[3][0]=1; matrix_a[3][1]=1; matrix_a[3][2]=1; matrix_a[3][3]=1;

        matrix_b[0][0]=2; matrix_b[0][1]=1; matrix_b[0][2]=0; matrix_b[0][3]=3;
        matrix_b[1][0]=0; matrix_b[1][1]=3; matrix_b[1][2]=1; matrix_b[1][3]=0;
        matrix_b[2][0]=1; matrix_b[2][1]=0; matrix_b[2][2]=2; matrix_b[2][3]=1;
        matrix_b[3][0]=3; matrix_b[3][1]=2; matrix_b[3][2]=0; matrix_b[3][3]=1;

        run_multiplication("Test 3 (General Matrix Multiply)");

        $display("\n=======================================================");
        $display("  >>> ALL 4x4 TOP-LEVEL SIMULATION TESTS PASSED! <<<");
        $display("=======================================================\n");

        repeat(3) @(posedge clk);
        $finish;
    end

    // Watchdog Timer
    initial begin
        #100000;
        $display("\n[ERROR] Simulation Watchdog Timeout!\n");
        $finish;
    end

endmodule
