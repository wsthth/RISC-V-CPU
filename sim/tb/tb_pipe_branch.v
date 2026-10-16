`timescale 1ns/1ps
// ============================================================================
// tb_pipe_branch.v - 五级流水线分支/预测器测试
// 运行 branch.s（循环分支 + 无符号比较 + jal/jalr 函数调用），检查 DMEM
// ============================================================================
module tb_pipe_branch;
    reg        clk = 0;
    reg        reset = 1;
    wire [31:0] pc, instr;
    integer errors = 0;
    integer cycles = 0;
    reg  [31:0] pc_prev = 0, pc_prev2 = 0, pc_prev3 = 0, pc_prev4 = 0;
    reg        halted = 0;

    riscv_pipeline dut (
        .clk(clk), .reset(reset),
        .pc(pc), .instr(instr),
        .io_write(), .io_wdata()
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
        $display("=== tb_pipe_branch start ===");
        #10;
        repeat (4) @(posedge clk);
        reset = 0;
        while (!halted && cycles < 5000) begin
            @(posedge clk);
            cycles = cycles + 1;
            if (pc == pc_prev && pc == pc_prev2 && pc == pc_prev3 && pc == pc_prev4)
                halted = 1;
            pc_prev4 = pc_prev3; pc_prev3 = pc_prev2; pc_prev2 = pc_prev; pc_prev = pc;
        end
        $display("cycles=%0d halted=%0d pc=%08X", cycles, halted, pc);
        if (!halted) begin
            $display("FAIL: CPU did not halt (timeout)");
            $display("TEST FAILED (pipe_branch)");
            $finish;
        end
        check_mem(32'h00000100, 32'h00000064, "mem100");  // 100
        check_mem(32'h00000104, 32'h00000032, "mem104");  // 50
        check_mem(32'h00000108, 32'h0000000A, "mem108");  // 10
        check_mem(32'h0000010C, 32'h00000014, "mem10C");  // 20
        check_mem(32'h00000110, 32'h0000000C, "mem110");  // 12
        if (errors == 0)
            $display("TEST PASSED (pipe_branch)");
        else
            $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
