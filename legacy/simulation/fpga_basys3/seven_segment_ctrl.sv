`timescale 1ns / 1ps
// ============================================================================
// Module: seven_segment_ctrl.sv
// Description: Time-Multiplexed 4-Digit 7-Segment Display Controller for Basys 3
// ============================================================================

module seven_segment_ctrl (
    input  wire        clk,        // 100MHz system clock
    input  wire        rst,        // Synchronous reset
    input  wire [15:0] value,      // 16-bit binary value to display in HEX
    output reg  [6:0]  seg,        // Cathode segments (a, b, c, d, e, f, g) active-low
    output reg         dp,         // Decimal point active-low
    output reg  [3:0]  an          // Anode enables active-low
);

    // Clock divider for ~1kHz multiplexing frequency (100MHz / 2^17 ~= 763Hz)
    reg [17:0] refresh_counter;
    wire [1:0] active_digit;

    always_ff @(posedge clk) begin
        if (rst)
            refresh_counter <= 18'd0;
        else
            refresh_counter <= refresh_counter + 18'd1;
    end

    assign active_digit = refresh_counter[17:16];

    // Nibble extraction
    reg [3:0] current_nibble;

    always_comb begin
        dp = 1'b1; // Turn off decimal point
        case (active_digit)
            2'b00: begin
                an = 4'b1110; // Digit 0 (Rightmost)
                current_nibble = value[3:0];
            end
            2'b01: begin
                an = 4'b1101; // Digit 1
                current_nibble = value[7:4];
            end
            2'b10: begin
                an = 4'b1011; // Digit 2
                current_nibble = value[11:8];
            end
            2'b11: begin
                an = 4'b0111; // Digit 3 (Leftmost)
                current_nibble = value[15:12];
            end
        endcase
    end

    // 7-segment hex decoder (active-low segments)
    always_comb begin
        case (current_nibble)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            4'hF: seg = 7'b0001110;
            default: seg = 7'b1111111;
        endcase
    end

endmodule
