`timescale 1ns/1ps
// ============================================================================
// hazard_unit.v - 冒险检测单元
// 检测 Load-Use 数据冒险：EX 段是 load 且其目标寄存器是 ID 段指令的源
// 处理：冻结 PC 与 IF/ID（stall），并在 ID/EX 插入气泡（flushe）
// ============================================================================
module hazard_unit (
    input        memread_e,   // EX 段指令是 load（resultsrc==01 且 valid）
    input  [4:0] rde,         // EX 段目标寄存器
    input  [4:0] rs1_d,       // ID 段源寄存器 1
    input  [4:0] rs2_d,       // ID 段源寄存器 2
    output       stallf,      // 冻结取指（PC 保持）
    output       stalld,      // 冻结译码（IF/ID 保持）
    output       flushe       // ID/EX 气泡
);
    wire lwstall = memread_e && (rde == rs1_d || rde == rs2_d) && (rde != 5'b0);

    assign stallf = lwstall;
    assign stalld = lwstall;
    assign flushe = lwstall;
endmodule
