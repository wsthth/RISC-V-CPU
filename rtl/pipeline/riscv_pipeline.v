`timescale 1ns/1ps
// ============================================================================
// riscv_pipeline.v - RV32I 五级流水线处理器（IF/ID/EX/MEM/WB）
//
// 特性：
//   * 完整 RV32I 整数指令集
//   * 数据冒险：EX/MEM 与 MEM/WB 两级旁路转发 + Load-Use 停顿
//   * 控制冒险：2-bit 饱和计数器分支预测 + BTB，分支/跳转在 EX 解析，
//     预测错误冲刷 IF/ID 与 ID/EX 两级
//   * jal/jalr 在 EX 段解析；jalr 目标低 1 位清零（RISC-V 规范）
//   * 可选 MMIO：向 0xFxxxxxxx 地址写数据时输出 io_write/io_wdata（FPGA 演示用）
// ============================================================================
module riscv_pipeline (
    input        clk,
    input        reset,
    // ---- 观察端口（TB/调试）----
    output wire [31:0] pc,
    output wire [31:0] instr,
    output wire        io_write,
    output wire [31:0] io_wdata
);
    // ================= 全部内部信号声明 =================
    // ---- IF ----
    wire [31:0] pcf, pcf_next, pcplus4_f, instr_f;
    wire        pred_taken_f;
    wire [31:0] pred_target_f;
    // ---- 冒险控制 ----
    wire        stallf, stalld, flushe;
    wire        mispredict;
    // ---- IF/ID ----
    wire [31:0] pc_d, instr_d;
    wire        pred_d, valid_d;
    // ---- ID ----
    wire [4:0]  rs1_d, rs2_d, rd_d;
    wire [2:0]  funct3_d;
    wire [6:0]  funct7_d, opcode_d;
    wire [31:0] rd1_d, rd2_d, immext_d;
    wire        regwrite_d, alusrca_d, alusrcb_d, memwrite_d, branch_d, jump_d;
    wire [1:0]  resultsrc_d, aluop_d;
    wire [2:0]  immsrc_d;
    wire [3:0]  alucontrol_d;
    wire        jalr_d;
    // ---- ID/EX 输出 ----
    wire        regwrite_e, alusrca_e, alusrcb_e, memwrite_e, branch_e, jump_e;
    wire [1:0]  resultsrc_e, aluop_e;
    wire        jalr_e, valid_e;
    wire [31:0] pc_e, rd1_e, rd2_e, immext_e;
    wire [4:0]  rs1_e, rs2_e, rd_e;
    wire [2:0]  funct3_e;
    wire [6:0]  funct7_e;
    wire [6:0]  opcode_e;
    wire        pred_e;
    wire        memread_e;
    // ---- EX ----
    wire [31:0] rs1e_data, rs2e_data, alu_srca, alu_srcb, alu_result_e;
    reg  [3:0]  alucontrol_e;
    wire        taken_e, branch_taken_e;
    wire [31:0] branch_target_e, pcplus4_e;
    wire [1:0]  forwardae, forwardbe;
    wire        branch_resolved_e;
    // ---- EX/MEM 输出 ----
    wire        regwrite_m, memwrite_m;
    wire [1:0]  resultsrc_m;
    wire [2:0]  funct3_m;
    wire [31:0] pcplus4_m, alu_result_m, writedata_m;
    wire [4:0]  rd_m;
    wire        valid_m;
    // ---- MEM ----
    wire [31:0] readdata_m;
    wire        io_write_m;
    // ---- MEM/WB 输出 ----
    wire        regwrite_w;
    wire [1:0]  resultsrc_w;
    wire [31:0] readdata_w, alu_result_w, pcplus4_w;
    wire [4:0]  rd_w;
    wire        valid_w;
    // ---- WB ----
    wire [31:0] writedata_w;

    // ================= IF 段 =================
    flopr #(.W(32)) pcreg (.clk(clk), .reset(reset), .d(pcf_next), .q(pcf));
    imem imem_i (.a(pcf), .rd(instr_f));
    assign pcplus4_f = pcf + 32'd4;
    assign pc = pcf;

    // ================= IF/ID 寄存器 =================
    reg_ifid ifid_reg (
        .clk(clk), .reset(reset),
        .enable(~stalld), .flush(mispredict),
        .pc_in(pcf), .instr_in(instr_f), .pred_in(pred_taken_f),
        .pc(pc_d), .instr(instr_d), .pred(pred_d), .valid(valid_d)
    );
    assign instr = instr_d;

    // ================= ID 段 =================
    assign rs1_d = instr_d[19:15];
    assign rs2_d = instr_d[24:20];
    assign rd_d  = instr_d[11:7];
    assign funct3_d = instr_d[14:12];
    assign funct7_d = instr_d[31:25];
    assign opcode_d = instr_d[6:0];
    assign jalr_d = (opcode_d == 7'b1100111);

    // 寄存器堆读（组合读，同步写）。写回与 ID 段读同沿发生时，直接旁路 WB 结果
    wire [31:0] rf_rd1, rf_rd2;
    regfile rf (
        .clk(clk), .we3(regwrite_w & valid_w), .a1(rs1_d), .a2(rs2_d), .a3(rd_w),
        .wd3(writedata_w), .rd1(rf_rd1), .rd2(rf_rd2)
    );
    assign rd1_d = ((regwrite_w & valid_w) && (rd_w == rs1_d) && (rd_w != 5'b0))
                   ? writedata_w : rf_rd1;
    assign rd2_d = ((regwrite_w & valid_w) && (rd_w == rs2_d) && (rd_w != 5'b0))
                   ? writedata_w : rf_rd2;
    extend ext (.instr(instr_d[31:7]), .immsrc(immsrc_d), .immext(immext_d));
    control_unit cu (
        .opcode(opcode_d), .funct3(funct3_d), .funct7(funct7_d),
        .regwrite(regwrite_d), .alusrca(alusrca_d), .alusrcb(alusrcb_d),
        .memwrite(memwrite_d), .resultsrc(resultsrc_d), .branch(branch_d),
        .jump(jump_d), .aluop(aluop_d), .immsrc(immsrc_d), .alucontrol(alucontrol_d)
    );

    // ---- 冒险检测（Load-Use）----
    assign memread_e = resultsrc_e[0] & valid_e;   // EX 段为 load
    hazard_unit hu (
        .memread_e(memread_e),
        .rde(rd_e),
        .rs1_d(rs1_d), .rs2_d(rs2_d),
        .stallf(stallf), .stalld(stalld), .flushe(flushe)
    );

    // ================= ID/EX 寄存器 =================
    reg_idex idex_reg (
        .clk(clk), .reset(reset),
        .flush(flushe | mispredict | ~valid_d),   // IF/ID 气泡也注入 ID/EX 气泡
        .regwrite_d(regwrite_d), .alusrca_d(alusrca_d), .alusrcb_d(alusrcb_d),
        .memwrite_d(memwrite_d), .branch_d(branch_d), .jump_d(jump_d),
        .resultsrc_d(resultsrc_d), .aluop_d(aluop_d), .jalr_d(jalr_d),
        .pc_d(pc_d), .rd1_d(rd1_d), .rd2_d(rd2_d), .immext_d(immext_d),
        .rs1_d(rs1_d), .rs2_d(rs2_d), .rd_d(rd_d),
        .funct3_d(funct3_d), .funct7_d(funct7_d), .opcode_d(opcode_d), .pred_d(pred_d),
        .regwrite(regwrite_e), .alusrca(alusrca_e), .alusrcb(alusrcb_e),
        .memwrite(memwrite_e), .branch(branch_e), .jump(jump_e),
        .resultsrc(resultsrc_e), .aluop(aluop_e), .jalr(jalr_e),
        .pc(pc_e), .rd1(rd1_e), .rd2(rd2_e), .immext(immext_e),
        .rs1(rs1_e), .rs2(rs2_e), .rd(rd_e),
        .funct3(funct3_e), .funct7(funct7_e), .opcode(opcode_e), .pred(pred_e),
        .valid(valid_e)
    );

    // ================= EX 段 =================
    // ---- 旁路转发 ----
    // 转发源：load 指令的结果是内存读数据（readdata），不是 ALU 结果（地址）
    wire [31:0] mem_result_m, wb_result_w;
    assign mem_result_m = resultsrc_m[0] ? readdata_m : alu_result_m;
    assign wb_result_w  = resultsrc_w[0] ? readdata_w : alu_result_w;
    forward_unit fu (
        .rs1_e(rs1_e), .rs2_e(rs2_e), .rdm(rd_m), .rdw(rd_w),
        .regwrite_m(regwrite_m & valid_m), .regwrite_w(regwrite_w & valid_w),
        .forwardae(forwardae), .forwardbe(forwardbe)
    );
    mux3 #(.W(32)) fwa (.d0(rd1_e), .d1(wb_result_w), .d2(mem_result_m),
                        .s(forwardae), .y(rs1e_data));
    mux3 #(.W(32)) fwb (.d0(rd2_e), .d1(wb_result_w), .d2(mem_result_m),
                        .s(forwardbe), .y(rs2e_data));

    // ---- ALU 控制译码（EX 段）----
    // 注意：addi 等 I 型指令的 funct7 字段是立即数位，不能用来区分 add/sub；
    //       只有 R 型（opcode=0110011）才按 funct7[5] 区分 add/sub
    always @(*) begin
        case (aluop_e)
            2'b00: alucontrol_e = 4'b0000;
            2'b01: begin
                case (funct3_e)
                    3'b000: alucontrol_e = ((opcode_e == 7'b0110011) && funct7_e[5])
                                           ? 4'b0001 : 4'b0000;
                    3'b001: alucontrol_e = 4'b0101;
                    3'b010: alucontrol_e = 4'b1000;
                    3'b011: alucontrol_e = 4'b1001;
                    3'b100: alucontrol_e = 4'b0100;
                    3'b101: alucontrol_e = funct7_e[5] ? 4'b0111 : 4'b0110;
                    3'b110: alucontrol_e = 4'b0011;
                    3'b111: alucontrol_e = 4'b0010;
                    default: alucontrol_e = 4'b0000;
                endcase
            end
            2'b10: alucontrol_e = 4'b1010;
            default: alucontrol_e = 4'b0000;
        endcase
    end

    mux2 #(.W(32)) muxa (.d0(rs1e_data), .d1(pc_e), .s(alusrca_e), .y(alu_srca));
    mux2 #(.W(32)) muxb (.d0(rs2e_data), .d1(immext_e), .s(alusrcb_e), .y(alu_srcb));
    alu alu_i (.a(alu_srca), .b(alu_srcb), .alucontrol(alucontrol_e),
               .result(alu_result_e), .zero());

    // ---- 分支/跳转解析 ----
    branch_unit bu (.rs1(rs1e_data), .rs2(rs2e_data), .funct3(funct3_e), .taken(taken_e));
    assign branch_taken_e = (branch_e & taken_e) | jump_e;
    assign branch_target_e = (jump_e & ~branch_e) ? {alu_result_e[31:1], 1'b0}
                                                   : alu_result_e;   // jalr 目标对齐
    assign mispredict = (branch_e | jump_e) & valid_e & (branch_taken_e != pred_e);
    assign pcplus4_e = pc_e + 32'd4;

    // ---- 分支预测器更新（仅 B 型与 jal 写入 BTB）----
    assign branch_resolved_e = (branch_e | (jump_e & ~jalr_e)) & valid_e;
    branch_predictor bp (
        .clk(clk), .reset(reset),
        .pcf(pcf), .pred_target(pred_target_f), .pred_taken(pred_taken_f),
        .branch_resolved(branch_resolved_e), .branch_taken(branch_taken_e),
        .branch_pc(pc_e), .branch_target(branch_target_e)
    );

    // ---- PC 更新（优先级：分支重定向 > 预测目标 > 停顿 > PC+4）----
    // mispredict 时按"实际执行方向"取目标：分支实际跳则取 target，不跳则取 PC+4
    assign pcf_next = mispredict            ? (branch_taken_e ? branch_target_e : pcplus4_e) :
                      (pred_taken_f & ~stallf) ? pred_target_f :
                      stallf                ? pcf :
                      pcplus4_f;

    // ================= EX/MEM 寄存器 =================
    reg_exmem exmem_reg (
        .clk(clk), .reset(reset),
        .regwrite_e(regwrite_e), .memwrite_e(memwrite_e),
        .resultsrc_e(resultsrc_e), .funct3_e(funct3_e),
        .pcplus4_e(pcplus4_e), .alu_result_e(alu_result_e),
        .writedata_e(rs2e_data), .rd_e(rd_e),
        .valid_e(valid_e),
        .regwrite(regwrite_m), .memwrite(memwrite_m),
        .resultsrc(resultsrc_m), .funct3(funct3_m),
        .pcplus4(pcplus4_m), .alu_result(alu_result_m),
        .writedata(writedata_m), .rd(rd_m),
        .valid(valid_m)
    );

    // ================= MEM 段 =================
    // MMIO：向 0xFxxxxxxx 写数据 -> 输出（不写入 DMEM）
    assign io_write_m = memwrite_m & valid_m & (alu_result_m[31:28] == 4'hF);
    dmem dmem_i (
        .clk(clk),
        .we(memwrite_m & valid_m & ~io_write_m),
        .funct3(funct3_m),
        .a(alu_result_m),
        .wd(writedata_m),
        .rd(readdata_m)
    );

    // MMIO 寄存器输出（同步一拍，供 FPGA 顶层采样）
    reg io_write_r;
    reg [31:0] io_wdata_r;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            io_write_r <= 1'b0;
            io_wdata_r <= 32'b0;
        end
        else begin
            io_write_r <= io_write_m;
            io_wdata_r <= writedata_m;
        end
    end
    assign io_write = io_write_r;
    assign io_wdata = io_wdata_r;

    // ================= MEM/WB 寄存器 =================
    reg_memwb memwb_reg (
        .clk(clk), .reset(reset),
        .regwrite_m(regwrite_m), .resultsrc_m(resultsrc_m),
        .readdata_m(readdata_m), .alu_result_m(alu_result_m),
        .pcplus4_m(pcplus4_m), .rd_m(rd_m),
        .valid_m(valid_m),
        .regwrite(regwrite_w), .resultsrc(resultsrc_w),
        .readdata(readdata_w), .alu_result(alu_result_w),
        .pcplus4(pcplus4_w), .rd(rd_w),
        .valid(valid_w)
    );

    // ================= WB 段 =================
    mux4 #(.W(32)) muxwb (.d0(alu_result_w), .d1(readdata_w), .d2(pcplus4_w),
                          .d3(32'b0), .s(resultsrc_w), .y(writedata_w));
endmodule
