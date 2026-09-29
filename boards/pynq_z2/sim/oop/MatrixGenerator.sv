`ifndef MATRIX_GENERATOR_SV
`define MATRIX_GENERATOR_SV

// ============================================================================
// Class: MatrixGenerator
// Description: OOP Generator that creates diverse randomized matrix stimuli,
//              including directed edge cases, identity, sparse, and dense modes.
// ============================================================================

class MatrixGenerator;

    int unsigned num_transactions;
    mailbox #(MatrixTransaction) gen2drv;
    mailbox #(MatrixTransaction) gen2scb;
    event done_gen;

    // Constructor
    function new(
        mailbox #(MatrixTransaction) g2d,
        mailbox #(MatrixTransaction) g2s,
        int unsigned count = 10
    );
        this.gen2drv          = g2d;
        this.gen2scb          = g2s;
        this.num_transactions = count;
    endfunction

    // Run Task
    task run();
        MatrixTransaction tx;
        $display("[GENERATOR] Starting Generation of %0d Matrix Transactions...", num_transactions);

        for (int i = 0; i < num_transactions; i++) begin
            tx = new(i + 1, $sformatf("TRANSACTION_%0d", i + 1));

            // Inject directed scenarios for the first few transactions, then random
            if (i == 0) begin
                if (!tx.randomize() with { mode == MODE_IDENTITY; }) begin
                    $error("[GENERATOR] Randomization failed for TX #%0d (Identity)", i + 1);
                end
            end else if (i == 1) begin
                if (!tx.randomize() with { mode == MODE_SCALED_ID; }) begin
                    $error("[GENERATOR] Randomization failed for TX #%0d (Scaled Identity)", i + 1);
                end
            end else if (i == 2) begin
                if (!tx.randomize() with { mode == MODE_SPARSE; }) begin
                    $error("[GENERATOR] Randomization failed for TX #%0d (Sparse)", i + 1);
                end
            end else if (i == 3) begin
                if (!tx.randomize() with { mode == MODE_STRESS_FULL; }) begin
                    $error("[GENERATOR] Randomization failed for TX #%0d (Stress Full)", i + 1);
                end
            end else begin
                if (!tx.randomize()) begin
                    $error("[GENERATOR] Randomization failed for TX #%0d", i + 1);
                end
            end

            // Push clone to Scoreboard and original to Driver
            gen2scb.put(tx.copy());
            gen2drv.put(tx);
        end

        $display("[GENERATOR] All %0d Transactions generated and queued successfully.", num_transactions);
        -> done_gen;
    endtask

endclass : MatrixGenerator

`endif // MATRIX_GENERATOR_SV
