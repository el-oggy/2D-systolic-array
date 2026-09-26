`ifndef MATRIX_DRIVER_SV
`define MATRIX_DRIVER_SV

// ============================================================================
// Class: MatrixDriver
// Description: Translates high-level MatrixTransaction objects into pin-level
//              signals on the systolic_top interface.
// ============================================================================

class MatrixDriver;

    localparam int N          = 16;
    localparam int DATA_WIDTH = 8;

    virtual matrix_if vif;
    mailbox #(MatrixTransaction) gen2drv;
    int unsigned driven_count;

    // Constructor
    function new(
        virtual matrix_if vif_inst,
        mailbox #(MatrixTransaction) g2d
    );
        this.vif          = vif_inst;
        this.gen2drv      = g2d;
        this.driven_count = 0;
    endfunction

    // Reset Task
    task reset_dut();
        $display("[DRIVER] Applying Synchronous Hardware Reset...");
        vif.rst   <= 1'b1;
        vif.start <= 1'b0;
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                vif.matrix_a[i][j] <= '0;
                vif.matrix_b[i][j] <= '0;
            end
        end
        repeat (5) @(posedge vif.clk);
        vif.rst <= 1'b0;
        @(posedge vif.clk);
        $display("[DRIVER] Reset Deasserted. Ready for stimulus injection.");
    endtask

    // Run Task
    task run();
        MatrixTransaction tx;

        // Apply initial reset
        reset_dut();

        forever begin
            gen2drv.get(tx);
            driven_count++;

            $display("[DRIVER] Driving TX #%0d (%s) at sim time %0t ps",
                     tx.trans_id, tx.mode.name(), $time);

            // Apply matrices and pulse start
            @(posedge vif.clk);
            vif.matrix_a <= tx.a;
            vif.matrix_b <= tx.b;
            vif.start    <= 1'b1;

            @(posedge vif.clk);
            vif.start    <= 1'b0;

            // Wait for systolic compute completion before next transaction
            @(posedge vif.done);
            // Allow result to settle and one guard cycle
            repeat (2) @(posedge vif.clk);
        end
    endtask

endclass : MatrixDriver

`endif // MATRIX_DRIVER_SV
