`timescale 1ns / 1ps
// ============================================================================
// Module: basys3_demo_8x8_top.sv
// Description: Basys 3 Hardware Wrapper for 8x8 (64 PEs) Systolic Array
//
// User Controls on Basys 3 Board:
//   - clk       : 100 MHz onboard oscillator (Pin W5)
//   - btnC      : Reset button
//   - btnU      : Start Computation pulse
//   - sw[1:0]   : Select Matrix Preset
//                   2'b00 : 8x8 Matrix A x 8x8 Identity (C = A)
//                   2'b01 : 8x8 Matrix A x 2*Identity (C = 2A)
//                   2'b10 : 8x8 Dense General Matrix Multiplication
//   - sw[7:5]   : Select Output Row index (0 to 7 -> 3 bits)
//   - sw[4:2]   : Select Output Column index (0 to 7 -> 3 bits)
//   - led[0]    : Done flag (Lights up when computation finishes!)
//   - led[1]    : Active status flag
//   - led[7:2]  : Displays selected (Row[2:0], Col[2:0]) bits
//   - led[15:8] : Displays lower 8 bits of selected result
//   - seg / an  : Displays 16-bit result value in HEX on 4-Digit 7-Segment Display
// ============================================================================

module basys3_demo_8x8_top (
    input  wire        clk,
    input  wire        btnC,        // Reset button
    input  wire        btnU,        // Start button
    input  wire [15:0] sw,          // Slide switches
    output wire [15:0] led,         // Status LEDs
    output wire [6:0]  seg,         // 7-segment cathodes
    output wire        dp,          // Decimal point
    output wire [3:0]  an           // 7-segment anodes
);

    localparam N          = 8; // 8x8 Grid = 64 PEs
    localparam DATA_WIDTH = 8;

    // Button synchronizer & edge detect
    reg btnC_sync, btnC_d;
    reg btnU_sync, btnU_d;

    always_ff @(posedge clk) begin
        btnC_sync <= btnC;
        btnC_d    <= btnC_sync;
        btnU_sync <= btnU;
        btnU_d    <= btnU_sync;
    end

    wire rst         = btnC_d;
    wire start_pulse = btnU_sync && !btnU_d;

    // Matrix ROM Storage (8x8)
    reg signed [DATA_WIDTH-1:0]   matrix_a [0:N-1][0:N-1];
    reg signed [DATA_WIDTH-1:0]   matrix_b [0:N-1][0:N-1];
    wire signed [2*DATA_WIDTH-1:0] result   [0:N-1][0:N-1];
    wire                          done;

    integer r, c;
    always_comb begin
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                // Default Matrix A: values 1 to 64
                matrix_a[r][c] = (r * N) + c + 1;

                case (sw[1:0])
                    2'b00: begin // 8x8 Identity
                        matrix_b[r][c] = (r == c) ? 8'sd1 : 8'sd0;
                    end
                    2'b01: begin // 8x8 2*Identity
                        matrix_b[r][c] = (r == c) ? 8'sd2 : 8'sd0;
                    end
                    default: begin // 8x8 Dense Matrix
                        matrix_a[r][c] = ((r + c) % 5) - 2;
                        matrix_b[r][c] = ((r * 2 + c) % 7) - 3;
                    end
                endcase
            end
        end
    end

    // Instantiate 8x8 Systolic Top Module
    systolic_top #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_systolic_top (
        .clk     (clk),
        .rst     (rst),
        .start   (start_pulse),
        .matrix_a(matrix_a),
        .matrix_b(matrix_b),
        .result  (result),
        .done    (done)
    );

    // Row (sw[7:5]) and Column (sw[4:2]) Selection (0 to 7)
    wire [2:0] sel_row = sw[7:5];
    wire [2:0] sel_col = sw[4:2];
    wire signed [15:0] selected_result = result[sel_row][sel_col];

    // 7-Segment Controller
    seven_segment_ctrl u_7seg (
        .clk  (clk),
        .rst  (rst),
        .value(selected_result),
        .seg  (seg),
        .dp   (dp),
        .an   (an)
    );

    // LED outputs
    assign led[0]    = done;
    assign led[1]    = !done && !rst;
    assign led[4:2]  = sel_col;
    assign led[7:5]  = sel_row;
    assign led[9:8]  = sw[1:0];
    assign led[15:10]= selected_result[5:0];

endmodule
