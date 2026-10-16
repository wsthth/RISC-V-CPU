`timescale 1ns/1ps
// ============================================================================
// flopr.v - 带异步复位的 D 触发器（PC 用）
// ============================================================================
module flopr #(parameter W = 32) (
    input             clk,
    input             reset,
    input  [W-1:0]    d,
    output reg [W-1:0] q
);
    always @(posedge clk or posedge reset) begin
        if (reset)
            q <= {W{1'b0}};
        else
            q <= d;
    end
endmodule