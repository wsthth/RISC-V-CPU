`timescale 1ns/1ps
// ============================================================================
// forward_unit.v - 数据旁路转发单元
// ForwardAE/BE（2-bit）：
//   00 = 无转发（取寄存器堆原值）
//   01 = 从 MEM/WB 转发（EX/MEM -> EX 前 1 周期结果）
//   10 = 从 EX/MEM 转发（MEM/WB -> EX 前 2 周期结果）
// 优先级：EX/MEM（更新的结果）优先于 MEM/WB
// ============================================================================
module forward_unit (
    input  [4:0] rs1_e,
    input  [4:0] rs2_e,
    input  [4:0] rdm,        // EX/MEM 段目标寄存器
    input  [4:0] rdw,        // MEM/WB 段目标寄存器
    input        regwrite_m, // EX/MEM 段写使能
    input        regwrite_w, // MEM/WB 段写使能
    output reg [1:0] forwardae,
    output reg [1:0] forwardbe
);
    always @(*) begin
        // Forward A（rs1）
        if (regwrite_m && (rdm != 5'b0) && (rdm == rs1_e))
            forwardae = 2'b10;
        else if (regwrite_w && (rdw != 5'b0) && (rdw == rs1_e))
            forwardae = 2'b01;
        else
            forwardae = 2'b00;

        // Forward B（rs2）
        if (regwrite_m && (rdm != 5'b0) && (rdm == rs2_e))
            forwardbe = 2'b10;
        else if (regwrite_w && (rdw != 5'b0) && (rdw == rs2_e))
            forwardbe = 2'b01;
        else
            forwardbe = 2'b00;
    end
endmodule
