`ifndef MATRIX_SCOREBOARD_SV
`define MATRIX_SCOREBOARD_SV

// ============================================================================
// Class: MatrixScoreboard
// Description: Automated OOP Scoreboard. Compares hardware sampled outputs
//              against golden mathematical model, maintains coverage and pass/fail
//              statistics for automated randomized stress testing.
// ============================================================================

class MatrixScoreboard;

    localparam int N          = 16;
    localparam int DATA_WIDTH = 8;

    mailbox #(MatrixTransaction) gen2scb;
    mailbox #(MatrixTransaction) mon2scb;

    // Statistical Metrics
    int unsigned total_tests;
    int unsigned passed_tests;
    int unsigned failed_tests;
    longint unsigned total_elements_verified;
    longint unsigned total_mismatches;
    int min_latency;
    int max_latency;
    real total_latency;

    // Constructor
    function new(
        mailbox #(MatrixTransaction) g2s,
        mailbox #(MatrixTransaction) m2s
    );
        this.gen2scb                 = g2s;
        this.mon2scb                 = m2s;
        this.total_tests             = 0;
        this.passed_tests            = 0;
        this.failed_tests            = 0;
        this.total_elements_verified = 0;
        this.total_mismatches        = 0;
        this.min_latency             = 999999;
        this.max_latency             = 0;
        this.total_latency           = 0.0;
    endfunction

    // Run Task
    task run();
        MatrixTransaction exp_tx;
        MatrixTransaction act_tx;
        int tx_mismatches;
        string diff_report;

        forever begin
            gen2scb.get(exp_tx);
            mon2scb.get(act_tx);

            total_tests++;
            total_elements_verified += (N * N);

            // Copy actual hardware results into expected transaction object for comparison
            exp_tx.actual_c = act_tx.actual_c;
            exp_tx.latency  = act_tx.latency;

            // Track Latency Stats
            if (act_tx.latency < min_latency) min_latency = act_tx.latency;
            if (act_tx.latency > max_latency) max_latency = act_tx.latency;
            total_latency += act_tx.latency;

            // Perform 256-element comparison
            if (exp_tx.compare(tx_mismatches, diff_report)) begin
                passed_tests++;
                $display("----------------------------------------------------------------------------");
                $display("[SCOREBOARD] [PASS] TX #%0d | Mode: %-16s | Latency: %0d cycles | 256/256 Matches",
                         total_tests, exp_tx.mode.name(), act_tx.latency);
                $display("  Sample C[0][0]=%0d, C[0][1]=%0d, C[15][15]=%0d (Matches Golden Reference)",
                         act_tx.actual_c[0][0], act_tx.actual_c[0][1], act_tx.actual_c[15][15]);
                $display("----------------------------------------------------------------------------");
            end else begin
                failed_tests++;
                total_mismatches += tx_mismatches;
                $error("[SCOREBOARD] [FAIL] TX #%0d | Mode: %-16s | %0d mismatches out of 256 elements!",
                       total_tests, exp_tx.mode.name(), tx_mismatches);
                $write("%s", diff_report);
            end
        end
    endtask

    // Final Report Summary
    function void print_summary();
        real pass_pct;
        real avg_lat;
        pass_pct = (total_tests > 0) ? (real'(passed_tests) / real'(total_tests) * 100.0) : 0.0;
        avg_lat  = (total_tests > 0) ? (total_latency / real'(total_tests)) : 0.0;

        $display("\n");
        $display("================================================================================");
        $display("                 OOP SYSTEMVERILOG VERIFICATION SCOREBOARD REPORT               ");
        $display("================================================================================");
        $display("  Target Accelerator Array Size   : %0d x %0d (%0d Processing Elements)", N, N, N*N);
        $display("  Data Precision                  : INT%0d Inputs -> INT%0d Accumulation", DATA_WIDTH, 2*DATA_WIDTH);
        $display("--------------------------------------------------------------------------------");
        $display("  Total Matrix Transactions Run   : %0d", total_tests);
        $display("  Passed Transactions             : %0d", passed_tests);
        $display("  Failed Transactions             : %0d", failed_tests);
        $display("  Total Matrix Elements Checked   : %0d", total_elements_verified);
        $display("  Total Element Mismatches        : %0d", total_mismatches);
        $display("  Element Accuracy Rate           : %0.2f%%", 
                 (total_elements_verified > 0) ? ((real'(total_elements_verified - total_mismatches) / real'(total_elements_verified)) * 100.0) : 0.0);
        $display("  Transaction Pass Rate           : %0.2f%%", pass_pct);
        $display("--------------------------------------------------------------------------------");
        $display("  Hardware Latency (Clock Cycles) : Min = %0d | Max = %0d | Avg = %0.1f", 
                 min_latency, max_latency, avg_lat);
        $display("================================================================================");

        if (failed_tests == 0 && total_tests > 0) begin
            $display("  >>> [SUCCESS] 100%% VERIFICATION PASSED - 0 MISMATCHES DETECTED! <<<");
        end else begin
            $display("  >>> [FAILURE] VERIFICATION DETECTED MISMATCHES IN HARDWARE OUTPUT! <<<");
        end
        $display("================================================================================\n");
    endfunction

endclass : MatrixScoreboard

`endif // MATRIX_SCOREBOARD_SV
