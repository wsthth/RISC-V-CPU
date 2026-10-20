`timescale 1ns/1ps
// ============================================================================
// pipe_regs.v - �弶��ˮ�߼Ĵ����飨IF/ID��ID/EX��EX/MEM��MEM/WB��
// ÿ���Ĵ����� 1-bit valid��
//   - flush ʱ valid ���㣨IF/ID��ID/EX ���ڷ�֧��ˢ / load-use bubble��
//   - enable ʱװ�أ�IF/ID ���� stall ���ᣩ
//   - ������ flush ʱ�ճ�װ�ص� valid=0���� valid �ſ�����ִ��
// ============================================================================

// ---------------- IF/ID ----------------
module reg_ifid (
    input             clk,
    input             reset,
    input             enable,   // 0=���ᣨload-use stall��
    input             flush,    // 1=��ˢ����֧ mispredict��
    input  [31:0]     pc_in,
    input  [31:0]     instr_in,
    input             pred_in,  // ����ָ��ȡָʱ�ķ�֧Ԥ��
    input             valid_in,
    input  [31:0]     pred_target_in,  // v0.12 pred_target pipeline reg (aligned with pred) // IF2 �Ŀ���λ��mispredict ��� IF2 ��Ч��
    output reg [31:0] pc,
    output reg [31:0] instr,
    output reg        pred,
    output reg        valid,
    output reg [31:0] pred_target
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc <= 32'b0; instr <= 32'b0; pred <= 1'b0; valid <= 1'b0; pred_target <= 32'b0;
        end
        else if (flush) begin
            pc <= pc_in; instr <= instr_in; pred <= pred_in; valid <= 1'b0; pred_target <= pred_target_in;
        end
        else if (enable) begin
            pc <= pc_in; instr <= instr_in; pred <= pred_in; valid <= valid_in; pred_target <= pred_target_in;
        end
    end
endmodule

// ---------------- ID/EX ----------------
module reg_idex (
    input             clk,
    input             reset,
    input             flush,    // 1=��ˢ/bubble��load-use ���֧ mispredict��
    // �����źţ���������������
    input             regwrite_d, alusrca_d, alusrcb_d, memwrite_d, branch_d, jump_d,
    input  [1:0]      resultsrc_d,
    input  [1:0]      aluop_d,
    input             jalr_d,
    // ����
    input  [31:0]     pc_d,
    input  [31:0]     rd1_d, rd2_d, immext_d,
    input  [4:0]      rs1_d, rs2_d, rd_d,
    input  [2:0]      funct3_d,
    input  [6:0]      funct7_d,
    input  [6:0]      opcode_d,
    input             pred_d,
    input  [31:0]     pred_target_d,  // v0.12 pred_target pipeline reg (aligned with pred)
    // ���
    output reg        regwrite, alusrca, alusrcb, memwrite, branch, jump,
    output reg [1:0]  resultsrc,
    output reg [1:0]  aluop,
    output reg        jalr,
    output reg [31:0] pc,
    output reg [31:0] rd1, rd2, immext,
    output reg [4:0]  rs1, rs2, rd,
    output reg [2:0]  funct3,
    output reg [6:0]  funct7,
    output reg [6:0]  opcode,
    output reg        pred,
    output reg [31:0] pred_target,
    output reg        valid
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            valid <= 1'b0;
            regwrite <= 1'b0; alusrca <= 1'b0; alusrcb <= 1'b0;
            memwrite <= 1'b0; branch <= 1'b0;   jump <= 1'b0;
            resultsrc <= 2'b00; aluop <= 2'b00; jalr <= 1'b0;
            pc <= 32'b0; rd1 <= 32'b0; rd2 <= 32'b0; immext <= 32'b0;
            rs1 <= 5'b0; rs2 <= 5'b0; rd <= 5'b0;
            funct3 <= 3'b0; funct7 <= 7'b0; opcode <= 7'b0; pred <= 1'b0; pred_target <= 32'b0;
        end
        else if (flush) begin
            // ��ˢ��valid=0 �����ȫ�������źţ��������ָ���� EX/MEM/WB ���д�أ�
            valid <= 1'b0;
            regwrite <= 1'b0; alusrca <= 1'b0; alusrcb <= 1'b0;
            memwrite <= 1'b0; branch <= 1'b0;   jump <= 1'b0;
            resultsrc <= 2'b00; aluop <= 2'b00; jalr <= 1'b0;
            pc <= pc_d; rd1 <= rd1_d; rd2 <= rd2_d; immext <= immext_d;
            rs1 <= rs1_d; rs2 <= rs2_d; rd <= rd_d;
            funct3 <= funct3_d; funct7 <= funct7_d; opcode <= opcode_d; pred <= pred_d; pred_target <= pred_target_d;
        end
        else begin
            valid <= 1'b1;
            regwrite <= regwrite_d; alusrca <= alusrca_d; alusrcb <= alusrcb_d;
            memwrite <= memwrite_d; branch <= branch_d;   jump <= jump_d;
            resultsrc <= resultsrc_d; aluop <= aluop_d;   jalr <= jalr_d;
            pc <= pc_d; rd1 <= rd1_d; rd2 <= rd2_d; immext <= immext_d;
            rs1 <= rs1_d; rs2 <= rs2_d; rd <= rd_d;
            funct3 <= funct3_d; funct7 <= funct7_d; opcode <= opcode_d; pred <= pred_d; pred_target <= pred_target_d;
        end
    end
endmodule

// ---------------- EX/MEM ----------------
module reg_exmem (
    input             clk,
    input             reset,
    // ����
    input             regwrite_e, memwrite_e,
    input  [1:0]      resultsrc_e,
    input  [2:0]      funct3_e,
    input             valid_e,
    // ����
    input  [31:0]     pcplus4_e, alu_result_e, writedata_e,
    input  [4:0]      rd_e,
    // ���
    output reg        regwrite, memwrite,
    output reg [1:0]  resultsrc,
    output reg [2:0]  funct3,
    output reg [31:0] pcplus4, alu_result, writedata,
    output reg [4:0]  rd,
    output reg        valid
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            valid <= 1'b0;
            regwrite <= 1'b0; memwrite <= 1'b0;
            resultsrc <= 2'b00; funct3 <= 3'b0;
            pcplus4 <= 32'b0; alu_result <= 32'b0;
            writedata <= 32'b0; rd <= 5'b0;
        end
        else begin
            valid <= valid_e;
            regwrite <= regwrite_e; memwrite <= memwrite_e;
            resultsrc <= resultsrc_e; funct3 <= funct3_e;
            pcplus4 <= pcplus4_e; alu_result <= alu_result_e;
            writedata <= writedata_e; rd <= rd_e;
        end
    end
endmodule

// ---------------- MEM/WB ----------------
// LOCK_READDATA=0（BRAM 版流水线）：readdata 不锁存，直通 dmem 输出
// （dmem 同步读在 MEM/WB 边沿更新，WB 周期内稳定，regfile 在 WB 边沿写回）
module reg_memwb #(parameter LOCK_READDATA = 1) (
    input             clk,
    input             reset,
    input             regwrite_m,
    input  [1:0]      resultsrc_m,
    input  [31:0]     readdata_m, alu_result_m, pcplus4_m,
    input  [4:0]      rd_m,
    input             valid_m,
    output reg        regwrite,
    output reg [1:0]  resultsrc,
    output wire [31:0] readdata,
    output reg [31:0] alu_result, pcplus4,
    output reg [4:0]  rd,
    output reg        valid
);
    reg [31:0] readdata_r;
    generate
        if (LOCK_READDATA) begin : lock_rd
            always @(posedge clk or posedge reset) begin
                if (reset) readdata_r <= 32'b0;
                else       readdata_r <= readdata_m;
            end
        end
    endgenerate
    assign readdata = LOCK_READDATA ? readdata_r : readdata_m;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            valid <= 1'b0;
            regwrite <= 1'b0; resultsrc <= 2'b00;
            alu_result <= 32'b0;
            pcplus4 <= 32'b0; rd <= 5'b0;
        end
        else begin
            valid <= valid_m;
            regwrite <= regwrite_m; resultsrc <= resultsrc_m;
            alu_result <= alu_result_m;
            pcplus4 <= pcplus4_m; rd <= rd_m;
        end
    end
endmodule
