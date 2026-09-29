`ifndef MATRIX_ENVIRONMENT_SV
`define MATRIX_ENVIRONMENT_SV

// ============================================================================
// Class: MatrixEnvironment
// Description: Top-level OOP verification environment orchestrating the
//              Generator, Driver, Monitor, and Scoreboard via SystemVerilog
//              inter-process mailboxes.
// ============================================================================

class MatrixEnvironment;

    virtual matrix_if vif;

    // Component Instances
    MatrixGenerator  gen;
    MatrixDriver     drv;
    MatrixMonitor    mon;
    MatrixScoreboard scb;

    // Communication Channels (Mailboxes)
    mailbox #(MatrixTransaction) gen2drv;
    mailbox #(MatrixTransaction) gen2scb;
    mailbox #(MatrixTransaction) mon2scb;

    int unsigned test_count;

    // Constructor
    function new(virtual matrix_if vif_inst, int unsigned count = 20);
        this.vif        = vif_inst;
        this.test_count = count;

        // Instantiate Mailboxes
        gen2drv = new();
        gen2scb = new();
        mon2scb = new();

        // Instantiate Verification Components
        gen = new(gen2drv, gen2scb, test_count);
        drv = new(vif, gen2drv);
        mon = new(vif, mon2scb);
        scb = new(gen2scb, mon2scb);
    endfunction

    // Run Task
    task run();
        $display("[ENV] Starting 2D Systolic Array Verification Environment (%0d Tests)...", test_count);

        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join_none

        // Wait until all transactions have been processed by scoreboard
        wait (scb.total_tests == test_count);

        // Allow trailing clock cycles for settling
        repeat (10) @(posedge vif.clk);

        $display("[ENV] All %0d Transactions Completed.", test_count);

        // Print final verification report
        scb.print_summary();
    endtask

endclass : MatrixEnvironment

`endif // MATRIX_ENVIRONMENT_SV
