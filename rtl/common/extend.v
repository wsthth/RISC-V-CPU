`timescale 1ns/1ps
// ============================================================================
// extend.v - 立即数扩展单元
// ImmSrc[2:0]: 000 I型  001 S型  010 B型  011 U型  100 J型
// ============================================================================
module extend (
    input  [31:7] instr,
    input  [2:0]  immsrc,
    output reg [31:0] immext
);
    always @(*) begin
        case (immsrc)
            3'b000: immext = {{20{instr[31]}}, instr[31:20]};                     // I
            3'b001: immext = {{20{instr[31]}}, instr[31:25], instr[11:7]};        // S
            3'b010: immext = {{20{instr[31]}}, instr[7], instr[30:25],
                              instr[11:8], 1'b0};                                  // B
            3'b011: immext = {instr[31:12], 12'b0};                               // U
            3'b100: immext = {{12{instr[31]}}, instr[19:12], instr[20],
                              instr[30:21], 1'b0};                                 // J
            default: immext = 32'b0;
        endcase
    end
endmodule