`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 19.08.2026 09:55:43
// Design Name: 
// Module Name: processing_element
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module processing_element #(
     parameter DATA_WIDTH = 8 
    )(
    input wire clk,
    input wire rst,
    input wire en,
    
    input wire signed [DATA_WIDTH-1:0]a_in,
    output reg signed [DATA_WIDTH-1:0]a_out,
    
    input wire signed [DATA_WIDTH-1:0]b_in,
    output reg signed [DATA_WIDTH-1:0]b_out,
    
    
    output reg signed [2*DATA_WIDTH-1:0]acc
    );
        always@(posedge clk)begin
        if(rst)begin
        a_out <= 0;
        b_out <= 0;
        acc   <= 0;
        end
        else if (en) begin
        acc <= acc + (a_in * b_in);
        
        a_out <= a_in;
        b_out <= b_in;
        end
        end
endmodule
