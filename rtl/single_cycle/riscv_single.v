`timescale 1ns/1ps
// ============================================================================
// riscv_single.v - RV32I 单周期处理器（教材第 7 章结构）
// 数据通路：PC -> IMEM -> 译码 -> 寄存器堆 -> ALU -> DMEM -> 写回
// 支持 RV32I 全集（整数指令），分支在组合逻辑中判定
// ============================================================================
module riscv_single (
    input        clk,
    input        reset,
    output wire [31:0] pc,
    output wire [31:0] instr,
    output wire [31:0] alu_result,
    output wire        memwrite,
    output wire [31:0] writedata,
    output wire [31:0] readdata
);
    // ---- 指令字段 ----
    wire [6:0]  opcode = instr[6:0];
    wire [4:0]  rs1    = instr[19:15];
    wire [4:0]  rs2    = instr[24:20];
    wire [4:0]  rd     = instr[11:7];
    wire [2:0]  funct3 = instr[14:12];
    wire [6:0]  funct7 = instr[31:25];

    // ---- 内部线网 ----
    wire [31:0] pcnext, pcplus4;
    wire [31:0] rd1, rd2;
    wire [31:0] immext, srca, srcb;
    wire [31:0] result;
    wire        regwrite, alusrca, alusrcb, memwrite_i, branch, jump, pcsrc, taken;
    wire [1:0]  resultsrc;
    wire [1:0]  aluop;
    wire [2:0]  immsrc;
    wire [3:0]  alucontrol;
    wire [31:0] write_data;
    wire [31:0] jump_target;

    // ---- 取指 ----
    flopr #(.W(32)) pcreg (.clk(clk), .reset(reset), .d(pcnext), .q(pc));
    imem imem_i (.a(pc), .rd(instr));
    assign pcplus4 = pc + 32'd4;

    // ---- 寄存器堆 ----
    regfile rf (.clk(clk), .we3(regwrite), .a1(rs1), .a2(rs2), .a3(rd),
                .wd3(write_data), .rd1(rd1), .rd2(rd2));
    assign writedata = rd2;

    // ---- 立即数扩展 ----
    extend ext (.instr(instr[31:7]), .immsrc(immsrc), .immext(immext));

    // ---- ALU ----
    mux2 #(.W(32)) muxa (.d0(rd1), .d1(pc), .s(alusrca), .y(srca));
    mux2 #(.W(32)) muxb (.d0(rd2), .d1(immext), .s(alusrcb), .y(srcb));
    alu alu_i (.a(srca), .b(srcb), .alucontrol(alucontrol), .result(result), .zero());
    assign alu_result = result;

    // ---- 数据内存 ----
    dmem dmem_i (.clk(clk), .we(memwrite_i), .funct3(funct3), .a(result),
                 .wd(rd2), .rd(readdata));
    assign memwrite = memwrite_i;

    // ---- 写回 ----
    mux4 #(.W(32)) muxwb (.d0(result), .d1(readdata), .d2(pcplus4), .d3(32'b0),
                          .s(resultsrc), .y(write_data));

    // ---- 控制与分支 ----
    control_unit cu (.opcode(opcode), .funct3(funct3), .funct7(funct7),
                     .regwrite(regwrite), .alusrca(alusrca), .alusrcb(alusrcb),
                     .memwrite(memwrite_i), .resultsrc(resultsrc), .branch(branch),
                     .jump(jump), .aluop(aluop), .immsrc(immsrc), .alucontrol(alucontrol));
    branch_unit bu (.rs1(rd1), .rs2(rd2), .funct3(funct3), .taken(taken));

    // ---- PC 更新 ----
    assign pcsrc = (branch & taken) | jump;
    assign jump_target = (opcode == 7'b1100111) ? {result[31:1], 1'b0} : result; // jalr 目标对齐
    mux2 #(.W(32)) muxpc (.d0(pcplus4), .d1(jump_target), .s(pcsrc), .y(pcnext));
endmodule