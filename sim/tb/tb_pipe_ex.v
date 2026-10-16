`timescale 1ns/1ps
// tb_pipe_ex.v - 打印 EX 段译码细节（aluop/alucontrol/输入/输出），定位 lui 问题
module tb_pipe_ex;
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

    always @(posedge clk) begin
        if (!reset && dut.valid_e) begin
            $display("EX pc=%06X aluop=%0b aluc=%b srca=%08X srcb=%08X alu=%08X regwrite=%0d rd=%0d",
                     dut.pc_e, dut.aluop_e, dut.alucontrol_e,
                     dut.alu_srca, dut.alu_srcb, dut.alu_result_e,
                     dut.regwrite_e, dut.rd_e);
        end
    end

    initial begin
        $display("=== tb_pipe_ex start ===");
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
        $finish;
    end
endmodule
