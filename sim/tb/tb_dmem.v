// ============================================================================
// tb_dmem.v - 数据内存回归测试（组合读 SYNC_READ=0，完整非对齐功能）
// 覆盖：word/半字/字节读写 + 符号/零扩展 + 非对齐跨字
// 说明：BRAM 模式（SYNC_READ=1）为对齐访问优化（单地址读写可推断 Block RAM），
//       非对齐跨字仅在组合读模式支持；本 TB 用 SYNC_READ=0 验证内存功能完整。
// ============================================================================
`timescale 1ns/1ps
module tb_dmem;
    reg        clk = 0;
    reg        we;
    reg  [2:0] funct3_r, funct3_w;
    reg  [31:0] rd_addr, wr_addr, wd;
    wire [31:0] rd;
    integer errors = 0;

    dmem #(.SYNC_READ(0)) uut (.clk(clk), .we(we), .funct3_r(funct3_r), .funct3_w(funct3_w),
              .rd_addr(rd_addr), .wr_addr(wr_addr), .wd(wd), .rd(rd));
    always #5 clk = ~clk;

    task check;
        input [31:0] exp;
        input [79:0] name;
        begin
            if (rd !== exp) begin
                $display("FAIL %0s: got %08X expect %08X (raddr=%08X f3r=%b)",
                         name, rd, exp, rd_addr, funct3_r);
                errors = errors + 1;
            end
        end
    endtask

    // 写辅助：设置写端口，等一个边沿完成写
    task do_write;
        input [2:0]  f3;
        input [31:0] addr;
        input [31:0] data;
        begin
            we = 1; funct3_w = f3; wr_addr = addr; wd = data;
            #10;   // posedge 写入
            we = 0;
            #10;   // 与后续读拉开一个边沿
        end
    endtask

    // 读辅助：设置读端口，等一个边沿锁存，再检查
    task do_read;
        input [2:0]  f3;
        input [31:0] addr;
        input [31:0] exp;
        input [79:0] name;
        begin
            funct3_r = f3; rd_addr = addr;
            #10;   // posedge 锁存
            #1;    // rd 组合稳定
            check(exp, name);
        end
    endtask

    initial begin
        $display("=== tb_dmem start ===");
        we = 0; funct3_r = 3'b010; funct3_w = 3'b010;
        rd_addr = 0; wr_addr = 0; wd = 0; #10;

        // 1) word 写 0x0 = AABBCCDD，lw 读回
        do_write(3'b010, 32'h00000000, 32'hAABBCCDD);
        do_read(3'b010, 32'h00000000, 32'hAABBCCDD, "lw");

        // 2) 半字写 0x2 = 0x1122（对齐低半），lh/lhu 读回
        do_write(3'b001, 32'h00000002, 32'h00001122);
        do_read(3'b001, 32'h00000002, 32'h00001122, "lh-aligned-lower");
        do_read(3'b101, 32'h00000002, 32'h00001122, "lhu");
        // 0x0 处半字 = 0xCCDD（0x2 写入前的字），符号/零扩展
        do_read(3'b001, 32'h00000000, 32'hFFFFCCDD, "lh-sign-ext");
        do_read(3'b101, 32'h00000000, 32'h0000CCDD, "lhu-zero-ext");

        // 3) 字节写 0x6 = 0xFF、0x7 = 0x80，lb/lbu 读回
        do_write(3'b000, 32'h00000006, 32'h000000FF);
        do_write(3'b000, 32'h00000007, 32'h00000080);
        do_read(3'b000, 32'h00000006, 32'hFFFFFFFF, "lb-pos");   // 0xFF 符号扩展
        do_read(3'b100, 32'h00000007, 32'h00000080, "lbu");
        do_read(3'b000, 32'h00000007, 32'hFFFFFF80, "lb-neg");

        // 4) 半字写高半 0x4 = 0x7788，lw 合并验证
        do_write(3'b001, 32'h00000004, 32'h00007788);
        do_read(3'b010, 32'h00000004, 32'h80FF7788, "lw-after-sh");

        // 5) 字节覆盖不影响邻字节
        do_write(3'b000, 32'h00000005, 32'h00000055);
        do_read(3'b010, 32'h00000004, 32'h80FF5588, "byte-merge");

        // 6) 非对齐 lh：0x3（跨字）。mem 字节：0x2=22, 0x3=11（sh 0x2 写入 0x1122 小端）
        //    0x4=88 → lh 0x3 = {0x88, 0x11} = 0x8811 符号扩展 → 0xFFFF8811
        do_read(3'b001, 32'h00000003, 32'hFFFF8811, "lh-unalign");

        // 7) 非对齐 lw：0x1 = 字节[4]<<24 | 字节[3]<<16 | 字节[2]<<8 | 字节[1]
        //    = 0x88<<24 | 0x11<<16 | 0x22<<8 | 0xCC = 0x881122CC
        do_read(3'b010, 32'h00000001, 32'h881122CC, "lw-unalign");

        if (errors == 0)
            $display("TEST PASSED (dmem)");
        else
            $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
