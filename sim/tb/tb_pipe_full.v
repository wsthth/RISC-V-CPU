`timescale 1ns/1ps
// ============================================================================
// tb_pipe_full.v - RV32I 全指令集系统级测试（五级流水线）
// 运行 full.s，检查 DMEM[0x300..0x3BC]，含陷阱（不应执行路径）检查
// ============================================================================
module tb_pipe_full;
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
        input [31:0] off;
        input [31:0] exp;
        input [79:0] name;
        begin
            if (dut.dmem_i.mem[(32'h00000300 + off) >> 2] !== exp) begin
                $display("FAIL %0s[+%04X]: got %08X expect %08X",
                         name, off, dut.dmem_i.mem[(32'h00000300 + off) >> 2], exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("=== tb_pipe_full start ===");
        #10;
        repeat (4) @(posedge clk);
        reset = 0;
        while (!halted && cycles < 3000) begin
            @(posedge clk);
            cycles = cycles + 1;
            if (pc == pc_prev && pc == pc_prev2 && pc == pc_prev3 && pc == pc_prev4)
                halted = 1;
            pc_prev4 = pc_prev3; pc_prev3 = pc_prev2; pc_prev2 = pc_prev; pc_prev = pc;
        end
        $display("cycles=%0d halted=%0d pc=%08X", cycles, halted, pc);
        if (!halted) begin
            $display("FAIL: CPU did not halt (timeout)");
            $display("TEST FAILED (pipe_full)");
            $finish;
        end
        // ---- 1. lui / auipc ----
        check_mem(32'h00, 32'h12345000, "lui");
        if ((dut.dmem_i.mem[(32'h00000304) >> 2] & 32'hFFFFF000) != 0) begin
            $display("FAIL auipc: high 20 bits nonzero %08X",
                     dut.dmem_i.mem[(32'h00000304) >> 2]);
            errors = errors + 1;
        end
        // ---- 2. R 型算术 ----
        check_mem(32'h08, 32'h00000089, "add");    // 137
        check_mem(32'h0C, 32'h0000003F, "sub");    // 63
        // ---- 3. R 型移位 ----
        check_mem(32'h10, 32'h00000010, "sll");
        check_mem(32'h14, 32'h08000000, "srl");
        check_mem(32'h18, 32'hF8000000, "sra");
        // ---- 4. slt / sltu ----
        check_mem(32'h1C, 32'h00000001, "slt");
        check_mem(32'h20, 32'h00000000, "sltu");
        // ---- 5. 逻辑 ----
        check_mem(32'h24, 32'h00000000, "and");
        check_mem(32'h28, 32'hFFFFFFFF, "or");
        check_mem(32'h2C, 32'hFFFFFFFF, "xor");
        // ---- 6. I 型立即数 ----
        check_mem(32'h30, 32'h00000005, "addi");
        check_mem(32'h34, 32'h00000001, "slti");
        check_mem(32'h38, 32'h00000001, "sltiu");
        check_mem(32'h3C, 32'h000000F5, "xori");
        check_mem(32'h40, 32'h000000FA, "ori");
        check_mem(32'h44, 32'h0000000A, "andi");
        // ---- 7. 移位立即数 ----
        check_mem(32'h48, 32'h00000008, "slli");
        check_mem(32'h4C, 32'h10000000, "srli");
        check_mem(32'h50, 32'hF0000000, "srai");
        // ---- 8. load/store ----
        check_mem(32'h54, 32'h00000055, "lb");
        check_mem(32'h58, 32'hFFFFFF88, "lb_sx");
        check_mem(32'h5C, 32'h00000088, "lbu");
        check_mem(32'h60, 32'h00006655, "lh");
        check_mem(32'h64, 32'h00008877, "lhu");
        check_mem(32'h68, 32'h88776655, "lw");
        check_mem(32'h6C, 32'h000000DD, "sb");
        check_mem(32'h70, 32'h00003344, "sh");
        check_mem(32'h74, 32'hDEADBEEF, "sw");
        // ---- 9. 分支（偏移与 full.s 一一对应）----
        check_mem(32'h7C, 32'h00000005, "beq");
        check_mem(32'h80, 32'h00000000, "trap_bne");
        check_mem(32'h84, 32'h00000005, "bne");
        check_mem(32'h88, 32'h00000000, "trap_blt");
        check_mem(32'h8C, 32'hFFFFFFFF, "blt");
        check_mem(32'h90, 32'h00000190, "bge_path");   // 400
        check_mem(32'h94, 32'h00000001, "bge");
        check_mem(32'h98, 32'h000001F4, "bltu_path");  // 500
        check_mem(32'h9C, 32'hFFFFFFFF, "bltu");
        check_mem(32'hA0, 32'h00000258, "bgeu_path");  // 600
        check_mem(32'hA4, 32'h00000001, "bgeu");
        // ---- 10. jal / jalr ----
        check_mem(32'hA8, 32'h00000000, "trap_jal");
        check_mem(32'hAC, 32'h000001E0, "jal_ra");
        check_mem(32'hB0, 32'h00000000, "trap_jalr");
        check_mem(32'hB4, 32'h000001FC, "jalr_link");
        check_mem(32'hB8, 32'h00000000, "trap_jalr2");
        check_mem(32'hBC, 32'h00000001, "jalr_done");
        // ---- 陷阱检查（不应执行路径）----
        check_mem(32'h78, 32'h00000000, "trap_beq");    // 120
        if (errors == 0)
            $display("TEST PASSED (pipe_full)");
        else
            $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
