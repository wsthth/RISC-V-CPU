# -*- coding: utf-8 -*-
# 生成 tb_coremark.v（GBK 编码），基于 tb_rvtest.v 基础判定 + CoreMark 调试监控
import io

TB = r'''`timescale 1ns/1ps
// ============================================================================
// tb_coremark.v - CoreMark 仿真调试 TB（基于 tb_rvtest 自旋判定）
// 用法（run_sim.ps1）：
//   powershell -File run_sim.ps1 -TB tb_coremark -HEX testprog\hex\coremark1.hex
//             -DATA testprog\hex\coremark1.data.hex -Define PREDICT_OFF
// 判定：PC 连续 5 周期不变视为到达终点，此时 gp(x3)==1 为 PASS。
// 监控：CAPTURE 崩溃轨迹 / PC=X 全寄存器快照 / CoreMark size 计算链 / udivsi3。
// ============================================================================
module tb_coremark;
    reg        clk = 0;
    reg        reset = 1;
    wire [31:0] pc, instr;
    integer cycles = 0;
    reg [31:0] pc_p1 = 0, pc_p2 = 0, pc_p3 = 0, pc_p4 = 0;
    reg [31:0] hist_pc [0:63];
    integer hist_idx = 0;
    reg captured = 0;
    reg [31:0] a5_last = 32'hFFFFFFFF;
    reg [31:0] rev_last = 32'hFFFFFFFF;
    reg reboot_logged = 0;
    reg [31:0] last_pce = 32'hFFFFFFFF;
    reg [31:0] last_pce2 = 32'hFFFFFFFF;
    reg [31:0] prev_pc_e = 32'hFFFFFFFF;

`ifdef PREDICT_OFF
    riscv_pipeline #(.PREDICT(0)) dut (
        .clk(clk), .reset(reset),
        .pc(pc), .instr(instr),
        .io_write(), .io_wdata()
    );
`else
    riscv_pipeline dut (
        .clk(clk), .reset(reset),
        .pc(pc), .instr(instr),
        .io_write(), .io_wdata()
    );
`endif

    always #5 clk = ~clk;

    // CoreMark 调试监控（pc 为顶层 IF 输出，pc_e 为 EX 阶段精确地址）
    always @(posedge clk) begin
        if (reset == 0) begin
            // PC 变 X（跑飞）监控
            if (!captured && cycles > 30 && (^pc === 1'bx)) begin
                captured = 1;
                $display("PC=X at cycles=%0d a0=%08X ra=%08X sp=%08X", cycles,
                         dut.rf.mem[10], dut.rf.mem[1], dut.rf.mem[2]);
                $display("  s0=%08X s1=%08X s2=%08X s3=%08X s4=%08X s5=%08X s6=%08X s7=%08X",
                         dut.rf.mem[8], dut.rf.mem[9], dut.rf.mem[18], dut.rf.mem[19],
                         dut.rf.mem[20], dut.rf.mem[21], dut.rf.mem[22], dut.rf.mem[23]);
                $display("  s8=%08X s9=%08X s10=%08X s11=%08X t0=%08X t1=%08X t2=%08X t3=%08X",
                         dut.rf.mem[24], dut.rf.mem[25], dut.rf.mem[26], dut.rf.mem[27],
                         dut.rf.mem[5], dut.rf.mem[6], dut.rf.mem[7], dut.rf.mem[28]);
                $display("  t4=%08X t5=%08X t6=%08X pc_f2=%08X instr_f2=%08X",
                         dut.rf.mem[29], dut.rf.mem[30], dut.rf.mem[31], dut.pc_f2, dut.instr_f2);
                $display("  sig: mispredict=%b branch_taken_e=%b pred_e=%b stallf=%b pred_taken_nonbranch=%b jalr_pred_taken=%b",
                         dut.mispredict, dut.branch_taken_e, dut.pred_e, dut.stallf,
                         dut.pred_taken_nonbranch, dut.jalr_pred_taken);
                $display("  sig: pcf_next=%08X branch_target_e=%08X alu_result_e=%08X rs1e_data=%08X a_r=%08X imem_rd=%08X",
                         dut.pcf_next, dut.branch_target_e, dut.alu_result_e, dut.rs1e_data, dut.a_r, dut.imem_rd);
                $display("  sig: pc_e=%08X valid_e=%b branch_e=%b jump_e=%b regwrite_w=%b",
                         dut.pc_e, dut.valid_e, dut.branch_e, dut.jump_e, dut.regwrite_w);
                $display("pcX hist (newest first):");
                begin : print_pcx
                    integer k, shown;
                    reg [31:0] last;
                    reg [31:0] p;
                    shown = 0; last = 32'hFFFFFFFF;
                    for (k = 0; k < 64 && shown < 24; k = k + 1) begin
                        p = hist_pc[(hist_idx - 1 - k + 64) % 64];
                        if (p !== last) begin
                            $display("  pc=%08X", p);
                            last = p;
                            shown = shown + 1;
                        end
                    end
                end
            end
            // WB 写 x10（a0）监控：定位 a0 何时变 X
            if (dut.rf.we3 && dut.rf.a3 == 10 && (^dut.rf.wd3 === 1'bx)) begin
                $display("[%0d] WB-wr x10 wd3=XXXXXXXX src: alu=%08X rdata=%08X pc4=%08X sel=%b",
                         cycles, dut.alu_result_w, dut.readdata_w, dut.pcplus4_w, dut.resultsrc_w);
            end
            // MMIO 读（barebones_clock/start_time/stop_time 走此路径）
            if (dut.mmio_read_m) begin
                $display("[%0d] MMIO-RD: alu=%08X cyc=%0d rd=%08X", cycles,
                         dut.alu_result_m, dut.cycle_cnt, dut.readdata_m);
            end
            // bss 计时变量写入（crt0 清零 + start_time/stop_time）
            if (dut.memwrite_m && dut.valid_m &&
                (dut.alu_result_m == 32'h677c || dut.alu_result_m == 32'h6780)) begin
                $display("[%0d] SW-bss %08X wd=%08X", cycles, dut.alu_result_m, dut.writedata_m);
            end
            // bss 计时变量读取（get_time 两条 lw）
            if (dut.resultsrc_m[0] && dut.valid_m &&
                (dut.alu_result_m == 32'h677c || dut.alu_result_m == 32'h6780)) begin
                $display("[%0d] LD-bss %08X rd=%08X", cycles, dut.alu_result_m, dut.readdata_m);
            end
            // 崩前 1400600-1400620 每拍 EX+MEM+WB 转发链路（MMIO 计时崩溃点）
            if (dut.pc_e !== 32'hFFFFFFFF && cycles >= 1400600 && cycles <= 1400620) begin
                $display("[%0d] EX pc=%08X v=%b rs2d=%0d rs2e=%08X fwdbe=%0d rde=%0d rgwe=%b ressrc=%b alu=%08X",
                         cycles, dut.pc_e, dut.valid_e, dut.rs2_d, dut.rs2e_data, dut.forwardbe,
                         dut.rd_e, dut.regwrite_e, dut.resultsrc_e, dut.alu_result_e);
                $display("       MEM alu=%08X ressrc=%b rd_dmem=%08X rd_mmio=%b rd_m=%08X memres=%08X",
                         dut.alu_result_m, dut.resultsrc_m, dut.readdata_dmem, dut.mmio_read_m,
                         dut.readdata_m, dut.mem_result_m);
                $display("       WB  rd=%0d rgw=%b rdw=%08X aluW=%08X wb=%08X wd3=%08X",
                         dut.rd_w, dut.regwrite_w, dut.readdata_w, dut.alu_result_w,
                         dut.wb_result_w, dut.writedata_w);
            end
            // 预测开崩溃窗口（v0.9 修复后新崩溃点）：40340-40383 EX 每拍（core_bench_list 区域）
            if (cycles >= 40340 && cycles <= 40383) begin
                $display("[%0d] EX pc=%08X v=%b be=%b je=%b bte=%b pe=%b mp=%b",
                         cycles, dut.pc_e, dut.valid_e, dut.branch_e, dut.jump_e,
                         dut.branch_taken_e, dut.pred_e, dut.mispredict);
                $display("       ac=%08X pn=%08X pcf=%08X ar=%08X btgt=%08X alu=%08X rs1=%08X rs2=%08X",
                         dut.a_comb, dut.pcf_next, dut.pcf, dut.a_r,
                         dut.branch_target_e, dut.alu_result_e, dut.rs1e_data, dut.rs2e_data);
            end
            // PC 回到 _start（程序重启，多发生于 rodata/跳转表读错）
            if (pc == 32'h00000000) begin
                $display("[%0d] PC->0x0 (jump to _start): ra=%08X a0=%08X sp=%08X", cycles,
                         dut.rf.mem[1], dut.rf.mem[10], dut.rf.mem[2]);
            end
            // CoreMark size 计算链精确监控（pc_e = EX 阶段）
            if (dut.rf.we3 && cycles >= 200 && cycles <= 260) begin
                $display("[%0d] RFWR a3=%0d wd3=%08X", cycles, dut.rf.a3, dut.rf.wd3);
            end
            if (dut.pc_e == 32'hb24) begin
                $display("[%0d] slli @EX b24: a1=%08X srca=%08X srcb=%08X res=%08X ctrl=%b",
                         cycles, dut.rf.mem[11], dut.alu_srca, dut.alu_srcb, dut.alu_result_e, dut.alucontrol_e);
            end
            if (dut.pc_e == 32'hb28) begin
                $display("[%0d] srli @EX b28: a1=%08X srca=%08X srcb=%08X res=%08X ctrl=%b",
                         cycles, dut.rf.mem[11], dut.alu_srca, dut.alu_srcb, dut.alu_result_e, dut.alucontrol_e);
            end
            if (dut.pc_e == 32'hb2c) begin
                $display("[%0d] li @EX b2c: srca=%08X srcb=%08X res=%08X ctrl=%b",
                         cycles, dut.alu_srca, dut.alu_srcb, dut.alu_result_e, dut.alucontrol_e);
            end
            if (dut.pc_e == 32'hb30) begin
                $display("[%0d] jal udivsi3 @EX b30: a0=%08X a1=%08X target=%08X",
                         cycles, dut.rf.mem[10], dut.rf.mem[11], dut.branch_target_e);
            end
            if (dut.pc_e == 32'hb34) begin
                $display("[%0d] udivsi3 ret @EX b34: a0=%08X(size?)", cycles, dut.rf.mem[10]);
            end
            if (dut.pc_e == 32'hb80) begin
                $display("[%0d] jal core_list_init @EX b80: a0=%08X a1=%08X a2=%08X target=%08X",
                         cycles, dut.rf.mem[10], dut.rf.mem[11], dut.rf.mem[12], dut.branch_target_e);
            end
            // core_list_init 入口（pc_e 精确执行点，jal WB 已完成）
            if (dut.pc_e == 32'h820) begin
                $display("[%0d] core_list_init EX@820: ra=%08X a0=%08X a1=%08X a2=%08X",
                         cycles, dut.rf.mem[1], dut.rf.mem[10], dut.rf.mem[11], dut.rf.mem[12]);
            end
            // jal b30 返回链：b34 mv s5,a0 后 b38 sw（用 pc_e==b38 采样 a0，jal WB 已完成）
            if (dut.pc_e == 32'hb38) begin
                $display("[%0d] sw a0@b38-EX: a0=%08X s5=%08X addr=%08X sp=%08X", cycles, dut.rf.mem[10], dut.rf.mem[21], dut.alu_result_e, dut.rf.mem[2]);
            end
            // core_list_init/mergesort 返回值存入 64(sp)
            if (dut.pc_e == 32'hb88) begin
                $display("[%0d] sw ret@b88: a0=%08X(list头) addr=%08X(sp+64)", cycles, dut.rf.mem[10], dut.alu_result_e);
            end
            // core_bench_list：0x524 lw s0 完成（0x528 采样 a2/s0）
            if (dut.pc_e == 32'h528) begin
                $display("[%0d] core_bench_list s0-rdy: a2=%08X s0=%08X a0=%08X", cycles, dut.rf.mem[12], dut.rf.mem[8], dut.rf.mem[10]);
            end
            // lw s0,36(a2) 的写回数据：捕获所有写 x8(s0) 的 WB 时刻
            if (dut.rd_w == 5'd8 && dut.regwrite_w) begin
                $display("[%0d] WB-x8: wdata=%08X (pc_e=%08X)", cycles, dut.writedata_w, dut.pc_e);
            end
            if (dut.pc_e == 32'h818) begin
                $display("[%0d] ASSERT@818: s0=%08X ra=%08X sp=%08X", cycles, dut.rf.mem[8], dut.rf.mem[1], dut.rf.mem[2]);
                begin : print_assert_hist
                    integer k2, shown2;
                    reg [31:0] last2;
                    reg [31:0] p2;
                    shown2 = 0; last2 = 32'hFFFFFFFF;
                    for (k2 = 0; k2 < 64 && shown2 < 20; k2 = k2 + 1) begin
                        p2 = hist_pc[(hist_idx - 1 - k2 + 64) % 64];
                        if (p2 !== last2) begin
                            $display("  pc=%08X", p2);
                            last2 = p2;
                            shown2 = shown2 + 1;
                        end
                    end
                end
            end
            // UART 输出捕获（ee_printf → MMIO 0xF0000000 逐字符）
            if (dut.io_write && dut.io_wdata[7:0] != 8'h00) begin
                $display("UART:%c", dut.io_wdata[7:0]);
            end
            // halt 检测：pc_e==0x40 (j 0x40) 且 gp(x3)==1 → 程序正常结束
            // （原 PC 5 拍不变判据在 halt 循环预取振荡下永不满足，故补充本判据）
            if (dut.pc_e == 32'h00000040 && dut.valid_e && dut.rf.mem[3] == 32'h1 && cycles > 100000) begin
                $display("PASS: halt at pc=0x40, gp=1, cycles=%0d", cycles);
                $display("TEST PASSED (coremark)");
                $finish;
            end
            // 死循环时直接读 dmem 数组（链状态 vs lw 读值）
            if (cycles == 1376798 || cycles == 1376811 || cycles == 1376824 || cycles == 1376837 || cycles == 1376850 || cycles == 1376863 || cycles == 1376876 || cycles == 1376889 || cycles == 1376902) begin
                $display("[%0d] DMEM@: 67d4=%08X 67d8=%08X 68ac=%08X 680c=%08X 67fc=%08X 67ec=%08X 67dc=%08X 68b4=%08X", cycles,
                    dut.dmem_i.mem[32'h67d4>>2], dut.dmem_i.mem[32'h67d8>>2], dut.dmem_i.mem[32'h68ac>>2], dut.dmem_i.mem[32'h680c>>2],
                    dut.dmem_i.mem[32'h67fc>>2], dut.dmem_i.mem[32'h67ec>>2], dut.dmem_i.mem[32'h67dc>>2], dut.dmem_i.mem[32'h68b4>>2]);
            end
            // 死循环期间 dump 链表 next 快照
            if (cycles == 1500000) begin
                $display("=== DMEM chain snapshot @1500000 ===");
                for (integer i = 0; i < 31; i = i + 1) begin
                    $display("node[%0d] @%08X: next=%08X", i, 32'h67D4 + (i*8), dut.dmem_i.mem[32'h67D4/4 + i*2]);
                end
            end
            if (dut.pc_e == 32'h9c8) begin
                $display("[%0d] iterate EX@9c8: a0=%08X(seeds)", cycles, dut.rf.mem[10]);
            end
            if (dut.pc_e == 32'hbd4) begin
                $display("[%0d] addi a0@bd4: sp=%08X res=%08X(sp+28)", cycles, dut.rf.mem[2], dut.alu_result_e);
            end
            if (dut.pc_e == 32'h3388) begin
                $display("[%0d] udivsi3 entry: a0=%08X a1=%08X", cycles, dut.rf.mem[10], dut.rf.mem[11]);
            end
            if (dut.pc_e == 32'h3394) begin
                $display("[%0d] udiv beqz-a2: a2=%08X a1=%08X a0=%08X", cycles, dut.rf.mem[12], dut.rf.mem[11], dut.rf.mem[10]);
            end
            if (dut.pc_e == 32'h33b0) begin
                $display("[%0d] udiv loop-start: a2=%08X a3=%08X a1=%08X", cycles, dut.rf.mem[12], dut.rf.mem[13], dut.rf.mem[11]);
            end
            if (dut.pc_e == 32'h33ac || dut.pc_e == 32'h33a0 || dut.pc_e == 32'h33b4 || dut.pc_e == 32'h33c8 || dut.pc_e == 32'h339c) begin
                $display("[%0d] br@%08X: branch=%b jump=%b taken=%b btaken=%b valid=%b imm=%08X alu=%08X tgt=%08X next=%08X",
                         cycles, dut.pc_e, dut.branch_e, dut.jump_e, dut.taken_e, dut.branch_taken_e,
                         dut.valid_e, dut.immext_e, dut.alu_result_e, dut.branch_target_e, dut.pcf_next);
            end
            if (dut.pc_e == 32'h33cc) begin
                $display("[%0d] udivsi3 ret: a0=%08X", cycles, dut.rf.mem[10]);
            end
        end
    end

    initial begin
        $display("=== tb_coremark start ===");
        #10;
        repeat (4) @(posedge clk);
        reset = 0;
        while (cycles < 2000000) begin
            @(posedge clk);
            cycles = cycles + 1;
            hist_pc[hist_idx] = pc;
            hist_idx = (hist_idx + 1) % 64;
            if (cycles > 30 && pc == pc_p1 && pc == pc_p2 && pc == pc_p3 && pc == pc_p4) begin
                repeat (10) @(posedge clk);
                if (dut.rf.mem[3] == 32'h1) begin
                    $display("PASS: gp=1 at pc=%08X, cycles=%0d", pc, cycles);
                    $display("TEST PASSED (coremark)");
                end else begin
                    $display("FAIL: gp=%08X at pc=%08X, cycles=%0d", dut.rf.mem[3], pc, cycles);
                    $display("  dbg x5=%08X x6=%08X x7=%08X x28=%08X",
                             dut.rf.mem[5], dut.rf.mem[6], dut.rf.mem[7], dut.rf.mem[28]);
                    $display("recent PCs (newest first):");
                    begin : print_hist
                        integer k, shown;
                        reg [31:0] last;
                        reg [31:0] p;
                        shown = 0; last = 32'hFFFFFFFF;
                        for (k = 0; k < 64 && shown < 16; k = k + 1) begin
                            p = hist_pc[(hist_idx - 1 - k + 64) % 64];
                            if (p !== last) begin
                                $display("  pc=%08X", p);
                                last = p;
                                shown = shown + 1;
                            end
                        end
                    end
                    $display("TEST FAILED (coremark)");
                end
                $finish;
            end
            pc_p4 = pc_p3; pc_p3 = pc_p2; pc_p2 = pc_p1; pc_p1 = pc;
        end
        $display("FAIL: timeout after %0d cycles, pc=%08X gp=%08X", cycles, pc, dut.rf.mem[3]);
        $display("TEST FAILED (coremark)");
        $finish;
    end
endmodule
'''

p = r'D:\my_project\RISC-V\sim\tb\tb_coremark.v'
io.open(p, 'wb').write(TB.encode('gbk'))
print('tb_coremark.v written, bytes=', len(TB.encode('gbk')))
