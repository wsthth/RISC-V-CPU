`timescale 1ns/1ps
// ============================================================================
// alu.v - RV32I ALU
// ALUControl[3:0]:
//   0000 ADD   0001 SUB   0010 AND   0011 OR    0100 XOR
//   0101 SLL   0110 SRL   0111 SRA   1000 SLT   1001 SLTU   1010 LUI(B<<12)
// ============================================================================
module alu #(parameter W = 32) (
    input  [W-1:0] a,
    input  [W-1:0] b,
    input  [3:0]   alucontrol,
    output reg [W-1:0] result,
    output wire  zero
);
    always @(*) begin
        case (alucontrol)
            4'b0000: result = a + b;
            4'b0001: result = a - b;
            4'b0010: result = a & b;
            4'b0011: result = a | b;
            4'b0100: result = a ^ b;
            4'b0101: result = a << b[4:0];
            4'b0110: result = a >> b[4:0];
            4'b0111: result = $signed(a) >>> b[4:0];
            4'b1000: result = ($signed(a) < $signed(b)) ? 32'b1 : 32'b0;
            4'b1001: result = (a < b) ? 32'b1 : 32'b0;
            4'b1010: result = b << 12;              // lui：B 为符号扩展的 32 位 U 型立即数
            default: result = a + b;
        endcase
    end
    assign zero = (result == {W{1'b0}});
endmodule