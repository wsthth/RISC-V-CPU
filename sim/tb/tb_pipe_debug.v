`timescale 1ns/1ps
// tb_pipe_debug.v - 逐周期打印 EX 段指令执行轨迹（定位流水线 bug）
module tb_pipe_debug;
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

    // EX 段观察
    wire [31:0] ex_pc     = dut.pc_e;
    wire [4:0]  ex_rs1    = dut.rs1_e;
    wire [4:0]  ex_rs2    = dut.rs2_e;
    wire [4:0]  ex_rd     = dut.rd_e;
    wire [31:0] ex_alu    = dut.alu_result_e;
    wire [31:0] ex_srca   = dut.alu_srca;
    wire [31:0] ex_srcb   = dut.alu_srcb;
    wire [1:0]  ex_fa     = dut.forwardae;
    wire [1:0]  ex_fb     = dut.forwardbe;
    wire        ex_valid  = dut.valid_e;
    wire        ex_mis    = dut.mispredict;
    wire        ex_branch = dut.branch_e;
    wire        ex_jump   = dut.jump_e;
    wire        ex_taken  = dut.branch_taken_e;

    always @(posedge clk) begin
        if (!reset && ex_valid) begin
            $display("EX pc=%06X rs1=%0d rs2=%0d rd=%0d fa=%0b fb=%0b srca=%08X srcb=%08X alu=%08X br=%0d jmp=%0d taken=%0d mis=%0d",
                     ex_pc, ex_rs1, ex_rs2, ex_rd, ex_fa, ex_fb,
                     ex_srca, ex_srcb, ex_alu, ex_branch, ex_jump, ex_taken, ex_mis);
        end
    end

    initial begin
        $display("=== tb_pipe_debug start ===");
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
        $display("mem100=%08X mem104=%08X mem108=%08X mem120=%08X mem124=%08X",
                 dut.dmem_i.mem[32'h100>>2], dut.dmem_i.mem[32'h104>>2],
                 dut.dmem_i.mem[32'h108>>2], dut.dmem_i.mem[32'h120>>2],
                 dut.dmem_i.mem[32'h124>>2]);
        $finish;
    end
endmodule
