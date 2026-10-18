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
    input  [6:0] opcode_d,    // ID 阶段指令 opcode（排除无源寄存器指令）
    output       stallf,      // 冻结取指（PC 保持）
    output       stalld,      // 冻结 IF2（指令保持）
    output       flushe       // ID/EX 冒泡
);
    // LUI(0110111)/AUIPC(0010111)/JAL(1101111) 的 rs1/rs2 字段是立即数或
    // 无意义（LUI/AUIPC 不用源寄存器，JAL 只用隐式 ra 目标）——若把它们当
    // 源寄存器参与 load-use 检测，会与 EX 级 load 的 rd 撞号误停一拍，
    // 误停触发 stall_release 跳取指，导致 lui/addi 等指令重复执行
    // （ld_st 测试：lui x7 的 imm 字段恰为 2，与 lw x2 的 rd 匹配——FAIL 根因）。
    wire no_rs = (opcode_d == 7'b0110111)  // LUI
               || (opcode_d == 7'b0010111)  // AUIPC
               || (opcode_d == 7'b1101111); // JAL
    wire lwstall = memread_e && (rde == rs1_d || rde == rs2_d) && (rde != 5'b0) && ~no_rs;

    assign stallf = lwstall;
    assign stalld = lwstall;
    assign flushe = lwstall;
endmodule
