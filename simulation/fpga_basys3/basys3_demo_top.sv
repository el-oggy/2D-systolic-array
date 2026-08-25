`timescale 1ns / 1ps
// ============================================================================
// Module: basys3_demo_top.sv
// Description: Basys 3 FPGA Hardware Demonstration Wrapper for Systolic Array
//
// User Controls:
//   - clk       : 100 MHz oscillator (Pin W5)
//   - btnC      : Synchronous Reset
//   - btnU      : Trigger Start Pulse
//   - sw[1:0]   : Select Matrix Preset
//                   2'b00 : Matrix A x Identity
//                   2'b01 : Matrix A x 2*Identity
//                   2'b10 : General Dense Matrix Multiplication
//   - sw[5:4]   : Select Output Matrix Row (0..3) to inspect
//   - sw[3:2]   : Select Output Matrix Column (0..3) to inspect
//   - led[0]    : Computation Done Indicator
//   - led[1]    : Compute Active
//   - led[5:2]  : Echoes selected (Row, Col) index
//   - led[15:8] : Displays lower 8 bits of selected result
//   - seg/an    : Displays 16-bit result value in HEX on 4-Digit 7-Segment Display
// ============================================================================

module basys3_demo_top (
    input  wire        clk,
    input  wire        btnC,        // Reset button
    input  wire        btnU,        // Start button
    input  wire [15:0] sw,          // Slide switches
    output wire [15:0] led,         // Status LEDs
    output wire [6:0]  seg,         // 7-segment cathodes
    output wire        dp,          // Decimal point
    output wire [3:0]  an           // 7-segment anodes
);

    localparam N          = 4;
    localparam DATA_WIDTH = 8;

    // Synchronize buttons
    reg btnC_sync, btnC_d;
    reg btnU_sync, btnU_d;

    always_ff @(posedge clk) begin
        btnC_sync <= btnC;
        btnC_d    <= btnC_sync;
        btnU_sync <= btnU;
        btnU_d    <= btnU_sync;
    end

    wire rst        = btnC_d;
    wire start_pulse = btnU_sync && !btnU_d; // Rising edge trigger

    // Matrix ROM Storage
    reg signed [DATA_WIDTH-1:0] matrix_a [0:N-1][0:N-1];
    reg signed [DATA_WIDTH-1:0] matrix_b [0:N-1][0:N-1];
    wire signed [2*DATA_WIDTH-1:0] result [0:N-1][0:N-1];
    wire done;

    // Load ROM Presets based on sw[1:0]
    always_comb begin
        // Matrix A default
        matrix_a[0][0]=8'sd1;  matrix_a[0][1]=8'sd2;  matrix_a[0][2]=8'sd3;  matrix_a[0][3]=8'sd4;
        matrix_a[1][0]=8'sd5;  matrix_a[1][1]=8'sd6;  matrix_a[1][2]=8'sd7;  matrix_a[1][3]=8'sd8;
        matrix_a[2][0]=8'sd9;  matrix_a[2][1]=8'sd10; matrix_a[2][2]=8'sd11; matrix_a[2][3]=8'sd12;
        matrix_a[3][0]=8'sd13; matrix_a[3][1]=8'sd14; matrix_a[3][2]=8'sd15; matrix_a[3][3]=8'sd16;

        case (sw[1:0])
            2'b00: begin // Identity
                matrix_b[0][0]=8'sd1; matrix_b[0][1]=8'sd0; matrix_b[0][2]=8'sd0; matrix_b[0][3]=8'sd0;
                matrix_b[1][0]=8'sd0; matrix_b[1][1]=8'sd1; matrix_b[1][2]=8'sd0; matrix_b[1][3]=8'sd0;
                matrix_b[2][0]=8'sd0; matrix_b[2][1]=8'sd0; matrix_b[2][2]=8'sd1; matrix_b[2][3]=8'sd0;
                matrix_b[3][0]=8'sd0; matrix_b[3][1]=8'sd0; matrix_b[3][2]=8'sd0; matrix_b[3][3]=8'sd1;
            end
            2'b01: begin // 2*Identity
                matrix_b[0][0]=8'sd2; matrix_b[0][1]=8'sd0; matrix_b[0][2]=8'sd0; matrix_b[0][3]=8'sd0;
                matrix_b[1][0]=8'sd0; matrix_b[1][1]=8'sd2; matrix_b[1][2]=8'sd0; matrix_b[1][3]=8'sd0;
                matrix_b[2][0]=8'sd0; matrix_b[2][1]=8'sd0; matrix_b[2][2]=8'sd2; matrix_b[2][3]=8'sd0;
                matrix_b[3][0]=8'sd0; matrix_b[3][1]=8'sd0; matrix_b[3][2]=8'sd0; matrix_b[3][3]=8'sd2;
            end
            default: begin // Dense Matrix
                matrix_a[0][0]=8'sd1; matrix_a[0][1]=8'sd2; matrix_a[0][2]=8'sd0; matrix_a[0][3]=8'sd1;
                matrix_a[1][0]=8'sd0; matrix_a[1][1]=8'sd1; matrix_a[1][2]=8'sd3; matrix_a[1][3]=8'sd0;
                matrix_a[2][0]=8'sd2; matrix_a[2][1]=8'sd0; matrix_a[2][2]=8'sd1; matrix_a[2][3]=8'sd4;
                matrix_a[3][0]=8'sd1; matrix_a[3][1]=8'sd1; matrix_a[3][2]=8'sd1; matrix_a[3][3]=8'sd1;

                matrix_b[0][0]=8'sd2; matrix_b[0][1]=8'sd1; matrix_b[0][2]=8'sd0; matrix_b[0][3]=8'sd3;
                matrix_b[1][0]=8'sd0; matrix_b[1][1]=8'sd3; matrix_b[1][2]=8'sd1; matrix_b[1][3]=8'sd0;
                matrix_b[2][0]=8'sd1; matrix_b[2][1]=8'sd0; matrix_b[2][2]=8'sd2; matrix_b[2][3]=8'sd1;
                matrix_b[3][0]=8'sd3; matrix_b[3][1]=8'sd2; matrix_b[3][2]=8'sd0; matrix_b[3][3]=8'sd1;
            end
        endcase
    end

    // Systolic Top Instance
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

    // Selected Output Value based on sw[5:4] (row) and sw[3:2] (col)
    wire [1:0] sel_row = sw[5:4];
    wire [1:0] sel_col = sw[3:2];
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

    // LED status assignments
    assign led[0]    = done;
    assign led[1]    = !done && !rst;
    assign led[3:2]  = sel_col;
    assign led[5:4]  = sel_row;
    assign led[7:6]  = sw[1:0];
    assign led[15:8] = selected_result[7:0];

endmodule
