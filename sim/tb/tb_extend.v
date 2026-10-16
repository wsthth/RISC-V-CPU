// ============================================================================
// tb_extend.v - 立即数扩展测试（I/S/B/U/J 五型 + 边界）
// ============================================================================
`timescale 1ns/1ps
module tb_extend;
    reg  [31:7] instr;
    reg  [2:0]  immsrc;
    wire [31:0] immext;
    integer errors = 0;

    extend uut (.instr(instr), .immsrc(immsrc), .immext(immext));

    task check;
        input [31:0] exp;
        input [79:0] name;
        begin
            if (immext !== exp) begin
                $display("FAIL %0s: got %08X expect %08X (instr=%08X src=%b)",
                         name, immext, exp, {instr, 7'b0}, immsrc);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("=== tb_extend start ===");
        // I 型：正立即数 0x123
        instr = 32'h12300000 >> 7; immsrc = 3'b000; #10;
        check(32'h00000123, "I-pos");
        // I 型：负立即数 -1 (0xFFF)
        instr = 32'hFFF00000 >> 7; immsrc = 3'b000; #10;
        check(32'hFFFFFFFF, "I-neg");
        // I 型：-2048
        instr = 32'h80000000 >> 7; immsrc = 3'b000; #10;
        check(32'hFFFFF800, "I-neg2048");
        // S 型：imm[11:5]=0x01, imm[4:0]=0x05 -> 0x25
        instr = {7'b0000001, 13'b0, 5'b00101}; immsrc = 3'b001; #10;
        check(32'h00000025, "S-pos");
        // S 型：负数 -1
        instr = {7'b1111111, 13'b0, 5'b11111}; immsrc = 3'b001; #10;
        check(32'hFFFFFFFF, "S-neg");
        // B 型：imm=0x1C (bit12=0,bit11=0,imm10:5=0,imm4:1=0xE)
        instr = {1'b0, 6'b000000, 5'b0, 5'b0, 3'b000, 4'b1110, 1'b0}; immsrc = 3'b010; #10;
        check(32'h0000001C, "B-pos");
        // B 型：负数 -4
        instr = {1'b1, 6'b111111, 5'b0, 5'b0, 3'b000, 4'b1110, 1'b1}; immsrc = 3'b010; #10;
        check(32'hFFFFFFFC, "B-neg");
        // U 型：指令 0x12345000（imm=0x12345）
        instr = 32'h12345000 >> 7; immsrc = 3'b011; #10;
        check(32'h12345000, "U-imm");
        // J 型：偏移 0x100（指令 0x1000006F）
        instr = 32'h1000006F >> 7; immsrc = 3'b100; #10;
        check(32'h00000100, "J-pos");
        // J 型：偏移 -2（指令 0xFFFFF06F）
        instr = 32'hFFFFF06F >> 7; immsrc = 3'b100; #10;
        check(32'hFFFFFFFE, "J-neg");
        if (errors == 0)
            $display("TEST PASSED (extend)");
        else
            $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
