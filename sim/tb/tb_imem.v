// ============================================================================
// tb_imem.v - 指令内存回归测试（同步读，SYNC_READ=1）
// 加载当前目录 program.hex（脚本复制，等价 basic.hex）：
//   地址 0 应为 addi x5,x0,256 = 0x10000293
//   地址 4 应为 addi x6,x0,10  = 0x00500313
// ============================================================================
`timescale 1ns/1ps
module tb_imem;
    reg        clk = 0;
    reg        reset = 0;
    reg  [31:0] a;
    wire [31:0] rd;
    integer errors = 0;

    imem uut (.clk(clk), .reset(reset), .a(a), .rd(rd));
    always #5 clk = ~clk;

    task check;
        input [31:0] exp;
        input [79:0] name;
        begin
            if (rd !== exp) begin
                $display("FAIL %0s: got %08X expect %08X (addr=%08X)",
                         name, rd, exp, a);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("=== tb_imem start ===");
        reset = 1; #10; reset = 0;  // 复位 rd_r/addr_r，防仿真初始 X
        a = 32'h0; #10;   // t=5 边沿锁存 mem[0]
        if (rd !== 32'h10000293) begin
            $display("FAIL imem[0]: got %08X expect 10000293", rd);
            errors = errors + 1;
        end
        a = 32'h4; #10;   // t=15 边沿锁存 mem[1]
        if (rd !== 32'h00500313) begin
            $display("FAIL imem[1]: got %08X expect 00500313", rd);
            errors = errors + 1;
        end
        if (errors == 0)
            $display("TEST PASSED (imem)");
        else
            $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
