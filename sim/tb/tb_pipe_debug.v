`timescale 1ns/1ps
// tb_pipe_debug.v - �����ڴ�ӡ EX ��ָ��ִ�й켣����λ��ˮ�� bug��
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

    // EX �ι۲�
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
    // MEM / IF2 �ι۲�
    wire [31:0] mem_addr  = dut.alu_result_m;
    wire [2:0]  mem_f3    = dut.funct3_m;
    wire        mem_valid = dut.valid_m;
    wire [31:0] mem_rd    = dut.readdata_m;
    wire [31:0] f2_pc     = dut.pc_f2;
    wire [31:0] f2_instr  = dut.instr_f;
    wire        f2_valid  = dut.valid_f2;
    wire        f2_stall  = dut.stallf;
    // WB �ι۲�
    wire [4:0]  wb_rd     = dut.rd_w;
    wire        wb_regwr  = dut.regwrite_w;
    wire [1:0]  wb_rsrc   = dut.resultsrc_w;
    wire [31:0] wb_alu    = dut.alu_result_w;
    wire [31:0] wb_rddata = dut.readdata_w;
    wire [31:0] wb_res    = dut.wb_result_w;
    wire        wb_valid  = dut.valid_w;

    // ID �ι۲�
    wire [31:0] id_pc     = dut.pc_id;
    wire [31:0] id_instr  = dut.instr_id;
    wire        id_valid  = dut.valid_id;
    wire        pred_f    = dut.pred_f2;
    wire        pred_d    = dut.pred_id;
    wire        pred_ex   = dut.pred_e;
    wire        pred_f_now = dut.pred_taken_f;
    wire        br_res    = dut.branch_resolved_e;
    wire [31:0] br_rs1    = dut.rs1e_data;
    wire [31:0] br_rs2    = dut.rs2e_data;

    wire [31:0] pred_target = dut.pred_target_f;
    wire [31:0] br_pc       = dut.pc_e;
    wire [31:0] br_target   = dut.branch_target_e;

    always @(posedge clk) begin
        $display("%4d | IF: pcf=%06X pcfn=%06X mis=%0d a=%06X ar=%06X ptar=%06X vf2=%0d | %sEX pc=%06X brs1=%08X brs2=%08X mis=%0d brpc=%06X btar=%06X brres=%0d | F2: pc=%06X v%0d | ID: pc=%06X v%0d | WB: rd=%0d rw=%0d res=%08X",
                 cycles+1, dut.pcf, dut.pcf_next, dut.mispredict, dut.imem_i.a, dut.imem_addr, pred_target, dut.valid_f2,
                 (ex_valid ? "" : "(bub) "), ex_pc, br_rs1, br_rs2, ex_mis, br_pc, br_target, br_res,
                 f2_pc, f2_valid, id_pc, id_valid,
                 wb_rd, wb_regwr, wb_res);
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
