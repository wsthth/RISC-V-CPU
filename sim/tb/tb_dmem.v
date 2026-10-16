// ============================================================================
// tb_dmem.v - 数据内存测试：字/半字/字节读写 + 符号扩展 + 未对齐
// ============================================================================
`timescale 1ns/1ps
module tb_dmem;
    reg        clk = 0;
    reg        we;
    reg  [2:0] funct3;
    reg  [31:0] a, wd;
    wire [31:0] rd;
    integer errors = 0;

    dmem uut (.clk(clk), .we(we), .funct3(funct3), .a(a), .wd(wd), .rd(rd));
    always #5 clk = ~clk;

    task check;
        input [31:0] exp;
        input [79:0] name;
        begin
            if (rd !== exp) begin
                $display("FAIL %0s: got %08X expect %08X (addr=%08X f3=%b)",
                         name, rd, exp, a, funct3);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("=== tb_dmem start ===");
        we = 0; funct3 = 3'b010; a = 0; wd = 0; #10;

        // 字写
        we = 1; funct3 = 3'b010; a = 32'h00000000; wd = 32'hAABBCCDD; #10;
        we = 0; a = 32'h00000000; #10; check(32'hAABBCCDD, "lw");

        // 半字写/读（未对齐地址 2）
        we = 1; funct3 = 3'b001; a = 32'h00000002; wd = 32'h00001122; #10;
        we = 0; funct3 = 3'b001; a = 32'h00000002; #10; check(32'h00001122, "lh-aligned-lower");
        we = 0; funct3 = 3'b101; a = 32'h00000002; #10; check(32'h00001122, "lhu");
        // 读 0x0 处半字 = 0xCCDD（符号扩展）
        funct3 = 3'b001; a = 32'h00000000; #10; check(32'hFFFFCCDD, "lh-sign-ext");
        funct3 = 3'b101; a = 32'h00000000; #10; check(32'h0000CCDD, "lhu-zero-ext");

        // 字节写/读
        we = 1; funct3 = 3'b000; a = 32'h00000006; wd = 32'h000000FF; #10;
        we = 1; funct3 = 3'b000; a = 32'h00000007; wd = 32'h00000080; #10;
        we = 0; funct3 = 3'b000; a = 32'h00000006; #10; check(32'hFFFFFFFF, "lb-pos");  // 0xFF 符号扩展
        funct3 = 3'b100; a = 32'h00000007; #10; check(32'h00000080, "lbu");
        funct3 = 3'b000; a = 32'h00000007; #10; check(32'hFFFFFF80, "lb-neg");

        // 半字高半写
        we = 1; funct3 = 3'b001; a = 32'h00000004; wd = 32'h00007788; #10;
        we = 0; funct3 = 3'b010; a = 32'h00000004; #10; check(32'h80FF7788, "lw-after-sh");
        // 字节覆盖不影响邻居
        we = 1; funct3 = 3'b000; a = 32'h00000005; wd = 32'h00000055; #10;
        we = 0; funct3 = 3'b010; a = 32'h00000004; #10; check(32'h80FF5588, "byte-merge");
        if (errors == 0)
            $display("TEST PASSED (dmem)");
        else
            $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
