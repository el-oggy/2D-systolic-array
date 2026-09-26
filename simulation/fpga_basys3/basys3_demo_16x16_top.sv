`timescale 1ns / 1ps
// ============================================================================
// Module: basys3_demo_16x16_top.sv
// Description: Basys 3 FPGA Hardware Top Wrapper for 16x16 (256 PEs) Systolic Array
//
// Target Board: Digilent Basys 3 (Artix-7 XC7A35T-1CPG236C)
//
// User Controls & Mappings:
//   - clk       : 100 MHz onboard oscillator (Pin W5)
//   - btnC      : Global Reset (Center button)
//   - btnU      : Start Computation Pulse (Top button)
//   - sw[3:0]   : Select Output Column (0 to 15, 4 bits)
//   - sw[7:4]   : Select Output Row    (0 to 15, 4 bits)
//   - sw[9:8]   : Select Matrix Preset:
//                   2'b00 : 16x16 Matrix A x Identity (C = A)
//                   2'b01 : 16x16 Matrix A x 2*Identity (C = 2A)
//                   2'b10 : 16x16 Dense Signed Matrix Multiplication
//   - led[0]    : Computation DONE flag (Lights up when C is ready)
//   - led[1]    : Computation BUSY flag (Active during pipeline compute)
//   - led[5:2]  : Echoes selected Column index sw[3:0]
//   - led[9:6]  : Echoes selected Row index sw[7:4]
//   - led[15:10]: Lower 6 bits of selected 16-bit result element
//   - seg / an  : 4-Digit 7-Segment Display showing the selected 16-bit HEX element C[row][col]
// ============================================================================

module basys3_demo_16x16_top (
    input  wire        clk,
    input  wire        btnC,        // Reset button
    input  wire        btnU,        // Start button
    input  wire [15:0] sw,          // Slide switches
    output wire [15:0] led,         // Status LEDs
    output wire [6:0]  seg,         // 7-segment cathodes
    output wire        dp,          // Decimal point
    output wire [3:0]  an           // 7-segment anodes
);

    localparam N          = 16; // 16x16 Grid = 256 PEs
    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH  = 16;

    // Button synchronizer & single-cycle edge detection
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

    // Matrix ROM Storage (16x16 = 256 elements each)
    reg signed [DATA_WIDTH-1:0]   matrix_a [0:N-1][0:N-1];
    reg signed [DATA_WIDTH-1:0]   matrix_b [0:N-1][0:N-1];
    wire signed [ACC_WIDTH-1:0]   result   [0:N-1][0:N-1];
    wire                          done;

    integer r, c;
    always_comb begin
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                // Preset Matrix A
                matrix_a[r][c] = ((r * 16 + c) % 127) - 63;

                case (sw[9:8])
                    2'b00: begin // 16x16 Identity Matrix
                        matrix_b[r][c] = (r == c) ? 8'sd1 : 8'sd0;
                    end
                    2'b01: begin // 16x16 2 * Identity Matrix
                        matrix_b[r][c] = (r == c) ? 8'sd2 : 8'sd0;
                    end
                    default: begin // 16x16 Dense Signed Pattern
                        matrix_a[r][c] = ((r * 7 + c * 3 + 5) % 15) - 7;
                        matrix_b[r][c] = ((r * 5 + c * 11 + 2) % 17) - 8;
                    end
                endcase
            end
        end
    end

    // Instantiate 16x16 Systolic Top Accelerator
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

    // Row (sw[7:4]) and Column (sw[3:0]) Selection (0 to 15)
    wire [3:0] sel_row = sw[7:4];
    wire [3:0] sel_col = sw[3:0];
    wire signed [15:0] selected_result = result[sel_row][sel_col];

    // 4-Digit 7-Segment Controller
    seven_segment_ctrl u_7seg (
        .clk  (clk),
        .rst  (rst),
        .value(selected_result),
        .seg  (seg),
        .dp   (dp),
        .an   (an)
    );

    // Board Status LEDs
    assign led[0]    = done;
    assign led[1]    = !done && !rst;
    assign led[5:2]  = sel_col;
    assign led[9:6]  = sel_row;
    assign led[15:10]= selected_result[5:0];

endmodule
