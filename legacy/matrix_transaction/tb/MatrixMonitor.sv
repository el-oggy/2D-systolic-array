`ifndef MATRIX_MONITOR_SV
`define MATRIX_MONITOR_SV

// ============================================================================
// Class: MatrixMonitor
// Description: Monitors the systolic array interface, samples the completed
//              output matrix C when 'done' asserts, and passes to Scoreboard.
// ============================================================================

class MatrixMonitor;

    localparam int N          = 16;
    localparam int DATA_WIDTH = 8;

    virtual matrix_if vif;
    mailbox #(MatrixTransaction) mon2scb;
    int unsigned monitored_count;

    // Constructor
    function new(
        virtual matrix_if vif_inst,
        mailbox #(MatrixTransaction) m2s
    );
        this.vif             = vif_inst;
        this.mon2scb         = m2s;
        this.monitored_count = 0;
    endfunction

    // Run Task
    task run();
        MatrixTransaction tx;
        int cycle_start;
        int cycle_done;

        forever begin
            // Wait for start signal assertion
            @(posedge vif.clk);
            if (vif.start === 1'b1) begin
                cycle_start = $time / 10; // Clock period is 10ns

                // Ensure done deasserts as accelerator enters LOAD/COMPUTE
                wait (vif.done === 1'b0);

                // Wait for hardware computation to complete
                @(posedge vif.done);
                cycle_done = $time / 10;
                monitored_count++;

                // Sample the output matrix C from hardware
                tx = new(monitored_count, $sformatf("MON_TX_%0d", monitored_count));
                tx.start_cycle = cycle_start;
                tx.done_cycle  = cycle_done;
                tx.latency     = cycle_done - cycle_start;

                for (int i = 0; i < N; i++) begin
                    for (int j = 0; j < N; j++) begin
                        tx.actual_c[i][j] = vif.result[i][j];
                    end
                end

                $display("[MONITOR] Captured Matrix C for TX #%0d (Done at sim time %0t ps, Latency = %0d cycles)",
                         monitored_count, $time, tx.latency);

                mon2scb.put(tx);
            end
        end
    endtask

endclass : MatrixMonitor

`endif // MATRIX_MONITOR_SV
