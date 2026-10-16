`timescale 1ns/1ps
// ============================================================================
// branch_unit.v - 分支条件判定
// funct3: 000 beq  001 bne  100 blt  101 bge  110 bltu  111 bgeu
// ============================================================================
module branch_unit (
    input  [31:0] rs1,
    input  [31:0] rs2,
    input  [2:0]  funct3,
    output wire   taken
);
    wire eq  = (rs1 == rs2);
    wire ne  = ~eq;
    wire lt  = ($signed(rs1) < $signed(rs2));
    wire ltu = (rs1 < rs2);
    wire ge  = ~lt;
    wire geu = ~ltu;

    assign taken = (funct3 == 3'b000) ? eq  :
                   (funct3 == 3'b001) ? ne  :
                   (funct3 == 3'b100) ? lt  :
                   (funct3 == 3'b101) ? ge  :
                   (funct3 == 3'b110) ? ltu :
                   (funct3 == 3'b111) ? geu : 1'b0;
endmodule