`timescale 1ns/1ps
// ============================================================================
// control_unit.v - 主译码器 + ALU 译码器
//
// 控制信号：
//   regwrite  : 寄存器写使能
//   alusrca   : ALU 源A选择（0=rs1, 1=PC，用于 auipc/分支/jal）
//   alusrcb   : ALU 源B选择（0=rs2, 1=立即数）
//   memwrite  : 数据内存写使能
//   resultsrc : 写回源（00=ALU结果, 01=内存读数据, 10=PC+4）
//   branch    : 是否条件分支（B型）
//   jump      : 是否无条件跳转（jal/jalr）
//   aluop     : 00=ADD  01=由funct译码  10=LUI
//   immsrc    : 000 I  001 S  010 B  011 U  100 J
// ============================================================================
module control_unit (
    input  [6:0] opcode,
    input  [2:0] funct3,
    input  [6:0] funct7,
    output reg       regwrite,
    output reg       alusrca,
    output reg       alusrcb,
    output reg       memwrite,
    output reg [1:0] resultsrc,
    output reg       branch,
    output reg       jump,
    output reg [1:0] aluop,
    output reg [2:0] immsrc,
    output reg [3:0] alucontrol
);
    // ---------------- 主译码器 ----------------
    always @(*) begin
        regwrite = 1'b0; alusrca = 1'b0; alusrcb = 1'b0; memwrite = 1'b0;
        resultsrc = 2'b00; branch = 1'b0; jump = 1'b0; aluop = 2'b00; immsrc = 3'b000;
        case (opcode)
            7'b0110011: begin regwrite = 1'b1;                      aluop = 2'b01; end                 // R 型
            7'b0010011: begin regwrite = 1'b1; alusrcb = 1'b1;      aluop = 2'b01; end                 // I 型 ALU
            7'b0000011: begin regwrite = 1'b1; alusrcb = 1'b1; resultsrc = 2'b01; end                 // 加载
            7'b0100011: begin            alusrcb = 1'b1; memwrite = 1'b1; immsrc = 3'b001; end        // 存储
            7'b1100011: begin                   alusrca = 1'b1; alusrcb = 1'b1; branch = 1'b1; immsrc = 3'b010; end // 分支
            7'b0110111: begin regwrite = 1'b1; alusrcb = 1'b1;      aluop = 2'b10; immsrc = 3'b011; end // lui
            7'b0010111: begin regwrite = 1'b1; alusrca = 1'b1; alusrcb = 1'b1; immsrc = 3'b011; end    // auipc
            7'b1101111: begin regwrite = 1'b1; alusrca = 1'b1; alusrcb = 1'b1; resultsrc = 2'b10; jump = 1'b1; immsrc = 3'b100; end // jal
            7'b1100111: begin regwrite = 1'b1; alusrcb = 1'b1; resultsrc = 2'b10; jump = 1'b1; end     // jalr
            default: ;                                                                                  // fence/ecall/ebreak -> 全零(NOP)
        endcase
    end

    // ---------------- ALU 译码器 ----------------
    always @(*) begin
        case (aluop)
            2'b00: alucontrol = 4'b0000;                        // ADD
            2'b01: begin                                        // 按 funct3/funct7 译码
                case (funct3)
                    3'b000: alucontrol = funct7[5] ? 4'b0001 : 4'b0000; // add/sub
                    3'b001: alucontrol = 4'b0101;               // sll
                    3'b010: alucontrol = 4'b1000;               // slt
                    3'b011: alucontrol = 4'b1001;               // sltu
                    3'b100: alucontrol = 4'b0100;               // xor
                    3'b101: alucontrol = funct7[5] ? 4'b0111 : 4'b0110; // sra/srl
                    3'b110: alucontrol = 4'b0011;               // or
                    3'b111: alucontrol = 4'b0010;               // and
                    default: alucontrol = 4'b0000;
                endcase
            end
            2'b10: alucontrol = 4'b1010;                        // LUI
            default: alucontrol = 4'b0000;
        endcase
    end
endmodule