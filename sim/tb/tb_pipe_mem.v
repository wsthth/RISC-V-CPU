`timescale 1ns/1ps
// tb_pipe_mem.v - 监视 MEM 段 dmem 读写（定位内存被误写问题）
module tb_pipe_mem;
    reg        clk = 0;
    reg        reset = 1;
    wire [31:0] pc, instr;
    integer cycles = 0;
    reg  [31:0] pc_prev = 0, pc_prev2 = 0, pc_prev3 = 0, pc_prev4 = 0;
    reg        halted = 0;

    riscv_pipeline dut (
        .clk(clk), .reset(reset),
        .pc(pc), .instr(instr),
        .io_write(), .io_wdata()
    );

    always #5 clk = ~clk;

    wire        m_we   = dut.dmem_i.we;
    wire [31:0] m_addr = dut.alu_result_m;
    wire [31:0] m_wd   = dut.writedata_m;
    wire [31:0] m_rd   = dut.readdata_m;
    wire        m_valid = dut.valid_m;

    always @(posedge clk) begin
        if (!reset && m_valid) begin
            $display("MEM a=%06X we=%0d wd=%08X rd=%08X", m_addr, m_we, m_wd, m_rd);
        end
    end

    initial begin
        $display("=== tb_pipe_mem start ===");
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
        $display("cycles=%0d halted=%0d", cycles, halted);
        $display("dmem[0x200]=%08X dmem[0x204]=%08X", dut.dmem_i.mem[32'h200>>2], dut.dmem_i.mem[32'h204>>2]);
        $finish;
    end
endmodule
