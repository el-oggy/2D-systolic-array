`timescale 1ns / 1ps

module tb_pe_mac;

    localparam int DATA_WIDTH = 8;
    localparam int ACC_WIDTH  = 32;

    logic                          clk;
    logic                          rst_n;
    logic                          clr_acc;
    logic                          en;
    logic signed [DATA_WIDTH-1:0]  a_i;
    logic signed [DATA_WIDTH-1:0]  b_i;

    logic signed [DATA_WIDTH-1:0]  a_o;
    logic signed [DATA_WIDTH-1:0]  b_o;
    logic signed [ACC_WIDTH-1:0]   acc_o;
    logic                          overflow_o;

    // Instantiate Unit Under Test (UUT)
    pe_mac #(
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .MAC_IMPL   ("DSP")
    ) uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .clr_acc    (clr_acc),
        .en         (en),
        .a_i        (a_i),
        .b_i        (b_i),
        .a_o        (a_o),
        .b_o        (b_o),
        .acc_o      (acc_o),
        .overflow_o (overflow_o)
    );

    // 100 MHz clock generation
    always #5 clk = ~clk;

    int error_count = 0;

    initial begin
        clk     = 0;
        rst_n   = 0;
        clr_acc = 0;
        en      = 0;
        a_i     = 0;
        b_i     = 0;

        // Apply Reset
        #20;
        rst_n = 1;
        #10;

        // Test 1: Verify reset state
        if (acc_o !== 0 || a_o !== 0 || b_o !== 0) begin
            $display("[FAIL] PE reset failed! acc_o=%d, a_o=%d, b_o=%d", acc_o, a_o, b_o);
            error_count++;
        end else begin
            $display("[PASS] PE reset verified.");
        end

        // Test 2: Basic MAC operation (3 * 5 = 15, then + (-2 * 4 = -8) -> 7)
        @(posedge clk);
        en  <= 1;
        a_i <= 8'sd3;
        b_i <= 8'sd5;

        @(posedge clk);
        a_i <= -8'sd2;
        b_i <= 8'sd4;

        @(posedge clk);
        en  <= 0;
        a_i <= 0;
        b_i <= 0;

        @(posedge clk);
        if (acc_o !== 32'sd7) begin
            $display("[FAIL] MAC computation mismatch: expected 7, got %d", acc_o);
            error_count++;
        end else begin
            $display("[PASS] Basic MAC computation passed (acc = %d).", acc_o);
        end

        // Test 3: Data forwarding test
        // Verify a_o and b_o delayed by 1 cycle
        @(posedge clk);
        en  <= 1;
        a_i <= 8'sd42;
        b_i <= -8'sd17;
        @(posedge clk);
        #1;
        if (a_o !== 8'sd42 || b_o !== -8'sd17) begin
            $display("[FAIL] Forwarding mismatch: a_o=%d, b_o=%d", a_o, b_o);
            error_count++;
        end else begin
            $display("[PASS] Data forwarding passed.");
        end

        // Test 4: Gating / Inactive PE test
        @(posedge clk);
        en  <= 0;
        a_i <= 8'sd100;
        b_i <= 8'sd100;
        @(posedge clk);
        #1;
        if (a_o !== 0 || b_o !== 0) begin
            $display("[FAIL] Inactive gating failed: expected zeros on outputs, got a_o=%d, b_o=%d", a_o, b_o);
            error_count++;
        end else begin
            $display("[PASS] Inactive PE clock/data gating passed.");
        end

        // Test 5: Clear accumulator
        @(posedge clk);
        clr_acc <= 1;
        @(posedge clk);
        clr_acc <= 0;
        @(posedge clk);
        #1;
        if (acc_o !== 0) begin
            $display("[FAIL] clr_acc failed: acc_o=%d", acc_o);
            error_count++;
        end else begin
            $display("[PASS] Accumulator clear passed.");
        end

        #20;
        if (error_count == 0) begin
            $display("==================================================");
            $display("   ALL PE_MAC TESTS PASSED SUCCESSFULLY!          ");
            $display("==================================================");
        end else begin
            $display("PE_MAC TESTS FAILED with %d errors.", error_count);
        end

        $finish;
    end

endmodule
