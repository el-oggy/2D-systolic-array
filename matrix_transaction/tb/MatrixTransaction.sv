`ifndef MATRIX_TRANSACTION_SV
`define MATRIX_TRANSACTION_SV

// ============================================================================
// Class: MatrixTransaction
// Description: OOP Transaction object encapsulating 16x16 matrices, random
//              constraints, golden reference compute, and verification checks.
// ============================================================================

// Global Test Scenario Modes
typedef enum {
    MODE_RANDOM_SMALL,  // Small values [-15, 15] to prevent INT16 overflow
    MODE_IDENTITY,      // B = Identity matrix (A x I = A)
    MODE_SCALED_ID,     // B = 2 * Identity (A x 2I = 2A)
    MODE_SPARSE,        // 80% zeros, AI inference sparsity
    MODE_STRESS_FULL    // Extreme INT8 range [-128, 127]
} test_mode_e;

class MatrixTransaction;

    localparam int N          = 16;
    localparam int DATA_WIDTH = 8;

    // Transaction ID and Metadata
    int unsigned trans_id;
    string       test_name;
    int          start_cycle;
    int          done_cycle;
    int          latency;

    rand test_mode_e mode;

    // Stimulus Matrices (4-state logic signed to match interface)
    rand logic signed [DATA_WIDTH-1:0]   a [0:N-1][0:N-1];
    rand logic signed [DATA_WIDTH-1:0]   b [0:N-1][0:N-1];

    // Reference & Hardware Output Matrices
    logic signed [2*DATA_WIDTH-1:0] expected_c [0:N-1][0:N-1];
    logic signed [2*DATA_WIDTH-1:0] actual_c   [0:N-1][0:N-1];

    // ------------------------------------------------------------------------
    // Constraints
    // ------------------------------------------------------------------------
    constraint c_mode_default {
        mode dist {
            MODE_RANDOM_SMALL := 40,
            MODE_SPARSE       := 30,
            MODE_STRESS_FULL  := 15,
            MODE_IDENTITY     := 10,
            MODE_SCALED_ID    := 5
        };
    }

    // Constraint for Small Random Range
    constraint c_small_values {
        if (mode == MODE_RANDOM_SMALL) {
            foreach (a[i, j]) a[i][j] inside {[-15 : 15]};
            foreach (b[i, j]) b[i][j] inside {[-15 : 15]};
        }
    }

    // Constraint for Identity Matrix
    constraint c_identity_matrix {
        if (mode == MODE_IDENTITY) {
            foreach (a[i, j]) a[i][j] inside {[-20 : 20]};
            foreach (b[i, j]) {
                if (i == j) b[i][j] == 1;
                else        b[i][j] == 0;
            }
        }
    }

    // Constraint for Scaled Identity Matrix
    constraint c_scaled_identity {
        if (mode == MODE_SCALED_ID) {
            foreach (a[i, j]) a[i][j] inside {[-15 : 15]};
            foreach (b[i, j]) {
                if (i == j) b[i][j] == 2;
                else        b[i][j] == 0;
            }
        }
    }

    // Constraint for Sparse AI Matrices (80% Zeros)
    constraint c_sparse_distribution {
        if (mode == MODE_SPARSE) {
            foreach (a[i, j]) {
                a[i][j] dist {
                    0          := 80,
                    [-10 : 10] := 20
                };
            }
            foreach (b[i, j]) {
                b[i][j] dist {
                    0          := 80,
                    [-10 : 10] := 20
                };
            }
        }
    }

    // Constraint for Stress Mode (Extreme INT8 Boundaries)
    constraint c_stress_boundaries {
        if (mode == MODE_STRESS_FULL) {
            foreach (a[i, j]) {
                a[i][j] dist {
                    -128       := 10,
                     127       := 10,
                    [-15 : 15] := 80
                };
            }
            foreach (b[i, j]) {
                b[i][j] dist {
                    -128       := 5,
                     127       := 5,
                    [-10 : 10] := 90
                };
            }
        }
    }

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    function new(int unsigned id = 0, string name = "MATRIX_TX");
        this.trans_id    = id;
        this.test_name   = name;
        this.start_cycle = 0;
        this.done_cycle  = 0;
        this.latency     = 0;
    endfunction

    // ------------------------------------------------------------------------
    // Post-Randomize: Compute Golden Expected Matrix
    // ------------------------------------------------------------------------
    function void post_randomize();
        compute_expected();
    endfunction

    // ------------------------------------------------------------------------
    // Golden Reference Model: C_exp[i][j] = sum(A[i][k] * B[k][j])
    // ------------------------------------------------------------------------
    function void compute_expected();
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                expected_c[i][j] = '0;
                for (int k = 0; k < N; k++) begin
                    expected_c[i][j] += (a[i][k] * b[k][j]);
                end
            end
        end
    endfunction

    // ------------------------------------------------------------------------
    // Deep Copy Method
    // ------------------------------------------------------------------------
    function MatrixTransaction copy();
        MatrixTransaction clone;
        clone = new(this.trans_id, this.test_name);
        clone.mode        = this.mode;
        clone.start_cycle = this.start_cycle;
        clone.done_cycle  = this.done_cycle;
        clone.latency     = this.latency;
        clone.a           = this.a;
        clone.b           = this.b;
        clone.expected_c  = this.expected_c;
        clone.actual_c    = this.actual_c;
        return clone;
    endfunction

    // ------------------------------------------------------------------------
    // Comparison Method against Hardware Output
    // ------------------------------------------------------------------------
    function bit compare(output int mismatches, output string report_str);
        mismatches = 0;
        report_str = "";
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                if (actual_c[i][j] !== expected_c[i][j]) begin
                    mismatches++;
                    if (mismatches <= 5) begin
                        report_str = {report_str, $sformatf(
                            "    Mismatch at C[%0d][%0d]: HW = %0d, EXP = %0d (diff = %0d)\n",
                            i, j, actual_c[i][j], expected_c[i][j], actual_c[i][j] - expected_c[i][j]
                        )};
                    end
                end
            end
        end
        return (mismatches == 0);
    endfunction

    // ------------------------------------------------------------------------
    // Display Method
    // ------------------------------------------------------------------------
    function void display(string prefix = "");
        $display("%s[TX #%0d] Mode: %s, Latency: %0d cycles",
                 prefix, trans_id, mode.name(), latency);
        $display("%s  Sample A[0..1][0..1]: [%4d %4d | %4d %4d]",
                 prefix, a[0][0], a[0][1], a[1][0], a[1][1]);
        $display("%s  Sample B[0..1][0..1]: [%4d %4d | %4d %4d]",
                 prefix, b[0][0], b[0][1], b[1][0], b[1][1]);
        $display("%s  Sample EXP C[0][0..1]: [%6d %6d], ACT C[0][0..1]: [%6d %6d]",
                 prefix, expected_c[0][0], expected_c[0][1], actual_c[0][0], actual_c[0][1]);
    endfunction

endclass : MatrixTransaction

`endif // MATRIX_TRANSACTION_SV
