// ============================================================================
// tb_dmem.v - 鏁版嵁鍐呭瓨鍥炲綊娴嬭瘯锛堢粍鍚堣�� SYNC_READ=0锛屽畬鏁撮潪瀵归綈鍔熻兘锛�
// 瑕嗙洊锛歸ord/鍗婂瓧/瀛楄妭璇诲啓 + 绗﹀彿/闆舵墿灞� + 闈炲�归綈璺ㄥ瓧
// 璇存槑锛欱RAM 妯″紡锛圫YNC_READ=1锛変负瀵归綈璁块棶浼樺寲锛堝崟鍦板潃璇诲啓鍙�鎺ㄦ柇 Block RAM锛夛紝
//       闈炲�归綈璺ㄥ瓧浠呭湪缁勫悎璇绘ā寮忔敮鎸侊紱鏈� TB 鐢� SYNC_READ=0 楠岃瘉鍐呭瓨鍔熻兘瀹屾暣銆�
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
              .rd_addr(rd_addr), .rd_addr2(rd_addr + 32'd4), .wr_addr(wr_addr), .wd(wd), .rd(rd));
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

    // 鍐欒緟鍔╋細璁剧疆鍐欑��鍙ｏ紝绛変竴涓�杈规部瀹屾垚鍐�
    task do_write;
        input [2:0]  f3;
        input [31:0] addr;
        input [31:0] data;
        begin
            we = 1; funct3_w = f3; wr_addr = addr; wd = data;
            #10;   // posedge 鍐欏叆
            we = 0;
            #10;   // 涓庡悗缁�璇绘媺寮�涓�涓�杈规部
        end
    endtask

    // 璇昏緟鍔╋細璁剧疆璇荤��鍙ｏ紝绛変竴涓�杈规部閿佸瓨锛屽啀妫�鏌�
    task do_read;
        input [2:0]  f3;
        input [31:0] addr;
        input [31:0] exp;
        input [79:0] name;
        begin
            funct3_r = f3; rd_addr = addr;
            #10;   // posedge 閿佸瓨
            #1;    // rd 缁勫悎绋冲畾
            check(exp, name);
        end
    endtask

    initial begin
        $display("=== tb_dmem start ===");
        we = 0; funct3_r = 3'b010; funct3_w = 3'b010;
        rd_addr = 0; wr_addr = 0; wd = 0; #10;

        // 1) word 鍐� 0x0 = AABBCCDD锛宭w 璇诲洖
        do_write(3'b010, 32'h00000000, 32'hAABBCCDD);
        do_read(3'b010, 32'h00000000, 32'hAABBCCDD, "lw");

        // 2) 鍗婂瓧鍐� 0x2 = 0x1122锛堝�归綈浣庡崐锛夛紝lh/lhu 璇诲洖
        do_write(3'b001, 32'h00000002, 32'h00001122);
        do_read(3'b001, 32'h00000002, 32'h00001122, "lh-aligned-lower");
        do_read(3'b101, 32'h00000002, 32'h00001122, "lhu");
        // 0x0 澶勫崐瀛� = 0xCCDD锛�0x2 鍐欏叆鍓嶇殑瀛楋級锛岀�﹀彿/闆舵墿灞�
        do_read(3'b001, 32'h00000000, 32'hFFFFCCDD, "lh-sign-ext");
        do_read(3'b101, 32'h00000000, 32'h0000CCDD, "lhu-zero-ext");

        // 3) 瀛楄妭鍐� 0x6 = 0xFF銆�0x7 = 0x80锛宭b/lbu 璇诲洖
        do_write(3'b000, 32'h00000006, 32'h000000FF);
        do_write(3'b000, 32'h00000007, 32'h00000080);
        do_read(3'b000, 32'h00000006, 32'hFFFFFFFF, "lb-pos");   // 0xFF 绗﹀彿鎵╁睍
        do_read(3'b100, 32'h00000007, 32'h00000080, "lbu");
        do_read(3'b000, 32'h00000007, 32'hFFFFFF80, "lb-neg");

        // 4) 鍗婂瓧鍐欓珮鍗� 0x4 = 0x7788锛宭w 鍚堝苟楠岃瘉
        do_write(3'b001, 32'h00000004, 32'h00007788);
        do_read(3'b010, 32'h00000004, 32'h80FF7788, "lw-after-sh");

        // 5) 瀛楄妭瑕嗙洊涓嶅奖鍝嶉偦瀛楄妭
        do_write(3'b000, 32'h00000005, 32'h00000055);
        do_read(3'b010, 32'h00000004, 32'h80FF5588, "byte-merge");

        // 6) 闈炲�归綈 lh锛�0x3锛堣法瀛楋級銆俶em 瀛楄妭锛�0x2=22, 0x3=11锛坰h 0x2 鍐欏叆 0x1122 灏忕��锛�
        //    0x4=88 鈫� lh 0x3 = {0x88, 0x11} = 0x8811 绗﹀彿鎵╁睍 鈫� 0xFFFF8811
        do_read(3'b001, 32'h00000003, 32'hFFFF8811, "lh-unalign");

        // 7) 闈炲�归綈 lw锛�0x1 = 瀛楄妭[4]<<24 | 瀛楄妭[3]<<16 | 瀛楄妭[2]<<8 | 瀛楄妭[1]
        //    = 0x88<<24 | 0x11<<16 | 0x22<<8 | 0xCC = 0x881122CC
        do_read(3'b010, 32'h00000001, 32'h881122CC, "lw-unalign");

        if (errors == 0)
            $display("TEST PASSED (dmem)");
        else
            $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
