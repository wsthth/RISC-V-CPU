// ============================================================================
// tb_imem.v - 指令内存加载测试
// 依赖：运行目录 program.hex（脚本复制，这里用 asm_selftest.hex）
// 检查：地址0 应为 add x1,x2,x3 = 0x003100B3
// ============================================================================
`timescale 1ns/1ps
module tb_imem;
    reg  [31:0] a;
    wire [31:0] rd;
    integer errors = 0;

    imem uut (.a(a), .rd(rd));

    initial begin
        $display("=== tb_imem start ===");
        a = 32'h0; #10;
        if (rd !== 32'h003100B3) begin
            $display("FAIL imem[0]: got %08X expect 003100B3", rd);
            errors = errors + 1;
        end
        a = 32'h4; #10;   // sub x4,x5,x6 = 0x40628233
        if (rd !== 32'h40628233) begin
            $display("FAIL imem[1]: got %08X expect 40628233", rd);
            errors = errors + 1;
        end
        if (errors == 0)
            $display("TEST PASSED (imem)");
        else
            $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
