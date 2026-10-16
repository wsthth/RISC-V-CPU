// ============================================================================
// tb_single.v - 单周期 RV32I CPU 整机测试
// 运行 basic.s（脚本复制为 program.hex），停机后检查 DMEM[0x100..0x124]
// ============================================================================
`timescale 1ns/1ps
module tb_single;
    reg        clk = 0;
    reg        reset = 1;
    wire [31:0] pc, instr;
    integer errors = 0;
    integer cycles = 0;
    reg  [31:0] pc_prev = 0, pc_prev2 = 0, pc_prev3 = 0, pc_prev4 = 0;
    reg        halted = 0;

    riscv_single dut (
        .clk(clk), .reset(reset),
        .pc(pc), .instr(instr),
        .alu_result(), .memwrite(), .writedata(), .readdata()
    );

    always #5 clk = ~clk;

    task check_mem;
        input [31:0] addr;
        input [31:0] exp;
        input [79:0] name;
        begin
            if (dut.dmem_i.mem[addr[31:2]] !== exp) begin
                $display("FAIL %0s[%08X]: got %08X expect %08X",
                         name, addr, dut.dmem_i.mem[addr[31:2]], exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("=== tb_single start ===");
        #10;
        // 复位 4 周期
        repeat (4) @(posedge clk);
        reset = 0;
        // 运行直到停机（PC 连续 5 周期不变 = 自环）或超时
        while (!halted && cycles < 1000) begin
            @(posedge clk);
            cycles = cycles + 1;
            if (pc == pc_prev && pc == pc_prev2 && pc == pc_prev3 && pc == pc_prev4)
                halted = 1;
            pc_prev4 = pc_prev3; pc_prev3 = pc_prev2; pc_prev2 = pc_prev; pc_prev = pc;
        end
        $display("cycles=%0d halted=%0d pc=%08X", cycles, halted, pc);
        if (!halted) begin
            $display("FAIL: CPU did not halt (timeout)");
            $display("TEST FAILED (single)");
            $finish;
        end
        // 检查结果
        check_mem(32'h00000100, 32'h0000000D, "mem100");  // 13
        check_mem(32'h00000104, 32'h00000008, "mem104");  // 8
        check_mem(32'h00000108, 32'h00000005, "mem108");  // 5
        check_mem(32'h0000010C, 32'h00000007, "mem10C");  // 7
        check_mem(32'h00000110, 32'h00000001, "mem110");  // 1
        check_mem(32'h00000114, 32'h00000001, "mem114");  // 1
        check_mem(32'h00000118, 32'h00000001, "mem118");  // 1
        check_mem(32'h0000011C, 32'h00000000, "mem11C");  // 0
        check_mem(32'h00000120, 32'h0000000A, "mem120");  // 10
        check_mem(32'h00000124, 32'h0000002A, "mem124");  // 42
        if (errors == 0)
            $display("TEST PASSED (single)");
        else
            $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
