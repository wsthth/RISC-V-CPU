// ============================================================================
// tb_alu.v - ALU 模块测试
// ============================================================================
`timescale 1ns/1ps
module tb_alu;
    reg  [31:0] a, b;
    reg  [3:0]  ctrl;
    wire [31:0] result;
    wire        zero;
    integer errors = 0;

    alu uut (.a(a), .b(b), .alucontrol(ctrl), .result(result), .zero(zero));

    task check;
        input [31:0] exp;
        input [79:0] name;
        begin
            if (result !== exp) begin
                $display("FAIL %0s: got %08X expect %08X (a=%08X b=%08X ctrl=%b)",
                         name, result, exp, a, b, ctrl);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("=== tb_alu start ===");
        // ADD
        a = 32'h00000005; b = 32'h00000007; ctrl = 4'b0000; #10; check(32'h0000000C, "ADD");
        // SUB
        a = 32'h00000007; b = 32'h00000005; ctrl = 4'b0001; #10; check(32'h00000002, "SUB");
        // 负数：0 - 1
        a = 32'h0; b = 32'h1; ctrl = 4'b0001; #10; check(32'hFFFFFFFF, "SUB-neg");
        // AND / OR / XOR
        a = 32'h0000FF00; b = 32'h0F0F0F0F; ctrl = 4'b0010; #10; check(32'h00000F00, "AND");
        a = 32'h0000FF00; b = 32'h0F0F0F0F; ctrl = 4'b0011; #10; check(32'h0F0FFF0F, "OR");
        a = 32'h0000FF00; b = 32'h0F0F0F0F; ctrl = 4'b0100; #10; check(32'h0F0FF00F, "XOR");
        // 移位
        a = 32'h80000001; b = 32'd4; ctrl = 4'b0101; #10; check(32'h00000010, "SLL");
        a = 32'h80000001; b = 32'd4; ctrl = 4'b0110; #10; check(32'h08000000, "SRL");
        a = 32'h80000001; b = 32'd4; ctrl = 4'b0111; #10; check(32'hF8000000, "SRA");
        // 比较
        a = 32'hFFFFFFFF; b = 32'h00000001; ctrl = 4'b1000; #10; check(32'h1, "SLT");
        a = 32'hFFFFFFFF; b = 32'h00000001; ctrl = 4'b1001; #10; check(32'h0, "SLTU");
        a = 32'h00000001; b = 32'hFFFFFFFF; ctrl = 4'b1001; #10; check(32'h1, "SLTU-2");
        // LUI
        a = 32'h0; b = 32'h00012345; ctrl = 4'b1010; #10; check(32'h12345000, "LUI");
        // zero 标志
        a = 32'h5; b = 32'h5; ctrl = 4'b0001; #10;
        if (!zero) begin $display("FAIL ZERO flag"); errors = errors + 1; end
        if (errors == 0)
            $display("TEST PASSED (alu)");
        else
            $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
