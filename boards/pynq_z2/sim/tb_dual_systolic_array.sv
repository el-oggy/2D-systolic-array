`timescale 1ns / 1ps
`default_nettype none

module tb_dual_systolic_array;
    localparam int ROWS = 16;
    localparam int COLS = 16;
    localparam int K    = 16;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic clr_acc_0 = 1'b1;
    logic clr_acc_1 = 1'b1;
    logic array_en_0 = 1'b0;
    logic array_en_1 = 1'b0;
    logic active_mask_0 [0:ROWS-1][0:COLS-1];
    logic active_mask_1 [0:ROWS-1][0:COLS-1];
    logic signed [7:0] wave_a_0 [0:ROWS-1];
    logic signed [7:0] wave_b_0 [0:COLS-1];
    logic signed [7:0] wave_a_1 [0:ROWS-1];
    logic signed [7:0] wave_b_1 [0:COLS-1];
    wire signed [31:0] result_0 [0:ROWS-1][0:COLS-1];
    wire signed [31:0] result_1 [0:ROWS-1][0:COLS-1];
    wire overflow_0;
    wire overflow_1;

    logic signed [7:0] a_0 [0:ROWS-1][0:K-1];
    logic signed [7:0] b_0 [0:K-1][0:COLS-1];
    logic signed [7:0] a_1 [0:ROWS-1][0:K-1];
    logic signed [7:0] b_1 [0:K-1][0:COLS-1];
    integer expected_0 [0:ROWS-1][0:COLS-1];
    integer expected_1 [0:ROWS-1][0:COLS-1];
    integer t, r, c, k, errors;

    always #5 clk = ~clk;

    dual_systolic_array #(
        .ARRAY_ROWS(ROWS),
        .ARRAY_COLS(COLS),
        .DSP_PE_LIMIT(200)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .clr_acc_0(clr_acc_0),
        .array_en_0(array_en_0),
        .active_mask_0(active_mask_0),
        .a_in_0(wave_a_0),
        .b_in_0(wave_b_0),
        .c_out_0(result_0),
        .overflow_0(overflow_0),
        .clr_acc_1(clr_acc_1),
        .array_en_1(array_en_1),
        .active_mask_1(active_mask_1),
        .a_in_1(wave_a_1),
        .b_in_1(wave_b_1),
        .c_out_1(result_1),
        .overflow_1(overflow_1)
    );

    initial begin
        errors = 0;
        for (r = 0; r < ROWS; r = r + 1) begin
            for (c = 0; c < COLS; c = c + 1) begin
                active_mask_0[r][c] = 1'b1;
                active_mask_1[r][c] = 1'b1;
                expected_0[r][c] = 0;
                expected_1[r][c] = 0;
            end
        end

        for (r = 0; r < ROWS; r = r + 1) begin
            for (k = 0; k < K; k = k + 1) begin
                a_0[r][k] = ((r + 2*k) % 5) - 2;
                a_1[r][k] = ((2*r + k) % 7) - 3;
            end
        end
        for (k = 0; k < K; k = k + 1) begin
            for (c = 0; c < COLS; c = c + 1) begin
                b_0[k][c] = ((2*k + c) % 3) - 1;
                b_1[k][c] = ((k + 2*c) % 5) - 2;
            end
        end
        for (r = 0; r < ROWS; r = r + 1) begin
            for (c = 0; c < COLS; c = c + 1) begin
                for (k = 0; k < K; k = k + 1) begin
                    expected_0[r][c] = expected_0[r][c] + a_0[r][k] * b_0[k][c];
                    expected_1[r][c] = expected_1[r][c] + a_1[r][k] * b_1[k][c];
                end
            end
        end

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        clr_acc_0 = 1'b0;
        clr_acc_1 = 1'b0;

        // Feed distinct GEMMs concurrently. A and B wavefronts are skewed by
        // row and column, respectively, so each PE receives matched operands.
        for (t = 0; t < ROWS + COLS + K - 2; t = t + 1) begin
            for (r = 0; r < ROWS; r = r + 1) begin
                k = t - r;
                wave_a_0[r] = (k >= 0 && k < K) ? a_0[r][k] : 8'sd0;
                wave_a_1[r] = (k >= 0 && k < K) ? a_1[r][k] : 8'sd0;
            end
            for (c = 0; c < COLS; c = c + 1) begin
                k = t - c;
                wave_b_0[c] = (k >= 0 && k < K) ? b_0[k][c] : 8'sd0;
                wave_b_1[c] = (k >= 0 && k < K) ? b_1[k][c] : 8'sd0;
            end
            array_en_0 = 1'b1;
            array_en_1 = 1'b1;
            @(posedge clk);
            @(negedge clk);
        end
        array_en_0 = 1'b0;
        array_en_1 = 1'b0;
        #1;

        for (r = 0; r < ROWS; r = r + 1) begin
            for (c = 0; c < COLS; c = c + 1) begin
                if (result_0[r][c] !== expected_0[r][c]) begin
                    $display("[FAIL] Engine 0 C[%0d][%0d]: got %0d expected %0d", r, c, result_0[r][c], expected_0[r][c]);
                    errors = errors + 1;
                end
                if (result_1[r][c] !== expected_1[r][c]) begin
                    $display("[FAIL] Engine 1 C[%0d][%0d]: got %0d expected %0d", r, c, result_1[r][c], expected_1[r][c]);
                    errors = errors + 1;
                end
            end
        end
        if (overflow_0 || overflow_1) begin
            $display("[FAIL] Unexpected overflow: engine0=%0b engine1=%0b", overflow_0, overflow_1);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("[PASS] Dual mesh: 200-DSP hybrid engine and LUT engine computed independent 16x16x16 GEMMs concurrently (512 MAC lanes). ");
        else
            $display("[FAIL] Dual mesh mismatch count: %0d", errors);
        $finish(errors != 0);
    end
endmodule

`default_nettype wire
