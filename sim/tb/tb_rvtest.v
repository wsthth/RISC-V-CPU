`timescale 1ns/1ps
// ============================================================================
// tb_rvtest.v - riscv-tests 官方测试集通用仿真 TB
// 用法（run_sim.ps1）：
//   powershell -File run_sim.ps1 -TB tb_rvtest -HEX testprog\rvtest\hex\add.hex
//             [-DATA testprog\rvtest\hex\add.data.hex]
// 判定：程序经 TEST_PASSFAIL 后进入 test_end 自旋；PC 连续 5 周期不变视为
// 到达终点，此时 gp(x3)==1 为 PASS，gp==0 为 FAIL（x1=TESTNUM 报告测试号）。
// ============================================================================
module tb_rvtest;
    reg        clk = 0;
    reg        reset = 1;
    wire [31:0] pc, instr;
    integer cycles = 0;
    reg [31:0] pc_p1 = 0, pc_p2 = 0, pc_p3 = 0, pc_p4 = 0;
    reg [31:0] hist_pc [0:63];
    integer hist_idx = 0;

    riscv_pipeline dut (
        .clk(clk), .reset(reset),
        .pc(pc), .instr(instr),
        .io_write(), .io_wdata()
    );

    always #5 clk = ~clk;

    initial begin
        $display("=== tb_rvtest start ===");
        #10;
        repeat (4) @(posedge clk);
        reset = 0;
        while (cycles < 20000) begin
            @(posedge clk);
            cycles = cycles + 1;
            hist_pc[hist_idx] = pc;
            hist_idx = (hist_idx + 1) % 64;
            // 自旋检测：PC 连续 5 周期不变（test_end 自旋）
            if (cycles > 30 && pc == pc_p1 && pc == pc_p2 && pc == pc_p3 && pc == pc_p4) begin
                repeat (10) @(posedge clk);   // 等流水线排空、gp 稳定
                if (dut.rf.mem[3] == 32'h1) begin
                    $display("PASS: gp=1 at pc=%08X, cycles=%0d", pc, cycles);
                    $display("TEST PASSED (rvtest)");
                end else begin
                    $display("FAIL: gp=%08X TESTNUM(x3)=%0d at pc=%08X, cycles=%0d",
                             dut.rf.mem[3], dut.rf.mem[3], pc, cycles);
                    // 调试辅助：打印常用临时寄存器（t0/t1/t2/t3 = x5/x6/x7/x28）
                    $display("  dbg x5=%08X x6=%08X x7=%08X x28=%08X",
                             dut.rf.mem[5], dut.rf.mem[6], dut.rf.mem[7], dut.rf.mem[28]);
                    // 打印最近 16 个不同 PC（定位失败测试）
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
                    $display("TEST FAILED (rvtest)");
                end
                $finish;
            end
            pc_p4 = pc_p3; pc_p3 = pc_p2; pc_p2 = pc_p1; pc_p1 = pc;
        end
        $display("FAIL: timeout after %0d cycles, pc=%08X gp=%08X TESTNUM=%0d",
                 cycles, pc, dut.rf.mem[3], dut.rf.mem[1]);
        $display("TEST FAILED (rvtest)");
        $finish;
    end
endmodule
