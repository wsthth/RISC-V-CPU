`timescale 1ns/1ps
// ============================================================================
// mux2.v / mux3.v / mux4.v - 参数化多路选择器
// ============================================================================
module mux2 #(parameter W = 32) (
    input  [W-1:0] d0, d1,
    input          s,
    output wire [W-1:0] y
);
    assign y = s ? d1 : d0;
endmodule

module mux3 #(parameter W = 32) (
    input  [W-1:0] d0, d1, d2,
    input  [1:0]   s,
    output wire [W-1:0] y
);
    assign y = s[1] ? d2 : (s[0] ? d1 : d0);
endmodule

module mux4 #(parameter W = 32) (
    input  [W-1:0] d0, d1, d2, d3,
    input  [1:0]   s,
    output wire [W-1:0] y
);
    assign y = s[1] ? (s[0] ? d3 : d2) : (s[0] ? d1 : d0);
endmodule