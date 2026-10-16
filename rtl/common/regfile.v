`timescale 1ns/1ps
// ============================================================================
// regfile.v - 32x32 通用寄存器堆
// 2 读端口（组合读）+ 1 写端口（时钟沿写）
// x0 硬连线为 0：读 x0 恒返回 0
// ============================================================================
module regfile #(parameter W = 32) (
    input             clk,
    input             we3,
    input  [4:0]      a1,   // 读地址1
    input  [4:0]      a2,   // 读地址2
    input  [4:0]      a3,   // 写地址
    input  [W-1:0]    wd3,  // 写数据
    output wire [W-1:0] rd1,
    output wire [W-1:0] rd2
);
    reg [W-1:0] mem [0:31];
    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1)
            mem[i] = {W{1'b0}};
    end

    assign rd1 = (a1 == 5'b0) ? {W{1'b0}} : mem[a1];
    assign rd2 = (a2 == 5'b0) ? {W{1'b0}} : mem[a2];

    always @(posedge clk) begin
        if (we3)
            mem[a3] <= wd3;
    end
endmodule