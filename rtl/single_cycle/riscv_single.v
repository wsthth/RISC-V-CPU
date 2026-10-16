`timescale 1ns/1ps
// ============================================================================
// riscv_single.v - RV32I �����ڴ��������̲ĵ� 7 �½ṹ��
// ����ͨ·��PC -> IMEM -> ���� -> �Ĵ����� -> ALU -> DMEM -> д��
// ֧�� RV32I ȫ��������ָ�����֧������߼����ж�
// ============================================================================
module riscv_single (
    input        clk,
    input        reset,
    output wire [31:0] pc,
    output wire [31:0] instr,
    output wire [31:0] alu_result,
    output wire        memwrite,
    output wire [31:0] writedata,
    output wire [31:0] readdata
);
    // ---- ָ���ֶ� ----
    wire [6:0]  opcode = instr[6:0];
    wire [4:0]  rs1    = instr[19:15];
    wire [4:0]  rs2    = instr[24:20];
    wire [4:0]  rd     = instr[11:7];
    wire [2:0]  funct3 = instr[14:12];
    wire [6:0]  funct7 = instr[31:25];

    // ---- �ڲ����� ----
    wire [31:0] pcnext, pcplus4;
    wire [31:0] rd1, rd2;
    wire [31:0] immext, srca, srcb;
    wire [31:0] result;
    wire        regwrite, alusrca, alusrcb, memwrite_i, branch, jump, pcsrc, taken;
    wire [1:0]  resultsrc;
    wire [1:0]  aluop;
    wire [2:0]  immsrc;
    wire [3:0]  alucontrol;
    wire [31:0] write_data;
    wire [31:0] jump_target;

    // ---- ȡָ ----
    flopr #(.W(32)) pcreg (.clk(clk), .reset(reset), .d(pcnext), .q(pc));
    imem #(.SYNC_READ(0)) imem_i (.clk(clk), .reset(reset), .a(pc), .rd(instr));
    assign pcplus4 = pc + 32'd4;

    // ---- �Ĵ����� ----
    regfile rf (.clk(clk), .we3(regwrite), .a1(rs1), .a2(rs2), .a3(rd),
                .wd3(write_data), .rd1(rd1), .rd2(rd2));
    assign writedata = rd2;

    // ---- ��������չ ----
    extend ext (.instr(instr[31:7]), .immsrc(immsrc), .immext(immext));

    // ---- ALU ----
    mux2 #(.W(32)) muxa (.d0(rd1), .d1(pc), .s(alusrca), .y(srca));
    mux2 #(.W(32)) muxb (.d0(rd2), .d1(immext), .s(alusrcb), .y(srcb));
    alu alu_i (.a(srca), .b(srcb), .alucontrol(alucontrol), .result(result), .zero());
    assign alu_result = result;

    // ---- �����ڴ棨��϶�ȡ��SYNC_READ=0��----
    dmem #(.SYNC_READ(0)) dmem_i (.clk(clk), .we(memwrite_i),
                                  .funct3_r(funct3), .funct3_w(funct3),
                                  .rd_addr(result), .wr_addr(result),
                                  .wd(rd2), .rd(readdata));
    assign memwrite = memwrite_i;

    // ---- д�� ----
    mux4 #(.W(32)) muxwb (.d0(result), .d1(readdata), .d2(pcplus4), .d3(32'b0),
                          .s(resultsrc), .y(write_data));

    // ---- �������֧ ----
    control_unit cu (.opcode(opcode), .funct3(funct3), .funct7(funct7),
                     .regwrite(regwrite), .alusrca(alusrca), .alusrcb(alusrcb),
                     .memwrite(memwrite_i), .resultsrc(resultsrc), .branch(branch),
                     .jump(jump), .aluop(aluop), .immsrc(immsrc), .alucontrol(alucontrol));
    branch_unit bu (.rs1(rd1), .rs2(rd2), .funct3(funct3), .taken(taken));

    // ---- PC ���� ----
    assign pcsrc = (branch & taken) | jump;
    assign jump_target = (opcode == 7'b1100111) ? {result[31:1], 1'b0} : result; // jalr Ŀ�����
    mux2 #(.W(32)) muxpc (.d0(pcplus4), .d1(jump_target), .s(pcsrc), .y(pcnext));
endmodule