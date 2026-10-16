`timescale 1ns/1ps
// ============================================================================
// hazard_unit.v - 冒险检测单元（Load-Use）
// 检测 EX 阶段 load 的目标寄存器与 ID 阶段指令源寄存器相同。
// BRAM 化后 dmem 读地址在 EX/MEM 边沿锁存，MEM 阶段数据可用并可通过
// d2（mem_result_m）转发，因此只需要 1 拍停顿：stall 后使用者进入 EX 时，
// load 已在 MEM/WB 阶段，数据可经转发获得。
// stallf: 冻结取指（PC 保持）；stalld: 冻结 IF2（指令保持）；flushe: ID/EX 冒泡
// ============================================================================
module hazard_unit (
    input        memread_e,   // EX 阶段指令是 load（resultsrc==01 且 valid）
    input  [4:0] rde,         // EX 阶段目标寄存器
    input  [4:0] rs1_d,       // ID 阶段源寄存器 1
    input  [4:0] rs2_d,       // ID 阶段源寄存器 2
    output       stallf,      // 冻结取指（PC 保持）
    output       stalld,      // 冻结 IF2（指令保持）
    output       flushe       // ID/EX 冒泡
);
    wire lwstall = memread_e && (rde == rs1_d || rde == rs2_d) && (rde != 5'b0);

    assign stallf = lwstall;
    assign stalld = lwstall;
    assign flushe = lwstall;
endmodule
