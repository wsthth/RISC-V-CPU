`timescale 1ns/1ps
// ============================================================================
// riscv_pipeline.v - RV32I �弶��ˮ�ߴ�������IF/ID/EX/MEM/WB��
//
// ���ԣ�
//   * ���� RV32I ����ָ�
//   * ����ð�գ�EX/MEM �� MEM/WB ������·ת�� + Load-Use ͣ��
//   * ����ð�գ�2-bit ���ͼ�������֧Ԥ�� + BTB����֧/��ת�� EX ������
//     Ԥ������ˢ IF/ID �� ID/EX ����
//   * jal/jalr �� EX �ν�����jalr Ŀ��� 1 λ���㣨RISC-V �淶��
//   * ��ѡ MMIO���� 0xFxxxxxxx ��ַд����ʱ��� io_write/io_wdata��FPGA ��ʾ�ã�
// ============================================================================
module riscv_pipeline (
    input        clk,
    input        reset,
    // ---- �۲�˿ڣ�TB/���ԣ�----
    output wire [31:0] pc,
    output wire [31:0] instr,
    output wire        io_write,
    output wire [31:0] io_wdata
);
    // ================= ȫ���ڲ��ź����� =================
    // ---- IF ----
    wire [31:0] pcf, pcf_next, pcplus4_f, instr_f;
    wire        pred_taken_f;
    wire [31:0] pred_target_f;
    // ---- ð�տ��� ----
    wire        stallf, stalld, flushe;
    wire        mispredict;
    // ---- IF/ID ----（IF2 ��ȡָ���ɼ���：instr_f + pc_f2 + pred_f2��
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
    // ---- ID/EX ��� ----
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
    // ---- EX/MEM ��� ----
    wire        regwrite_m, memwrite_m;
    wire [1:0]  resultsrc_m;
    wire [2:0]  funct3_m;
    wire [31:0] pcplus4_m, alu_result_m, writedata_m;
    wire [4:0]  rd_m;
    wire        valid_m;
    // ---- MEM ----
    wire [31:0] readdata_m;
    wire        io_write_m;
    // ---- MEM/WB ��� ----
    wire        regwrite_w;
    wire [1:0]  resultsrc_w;
    wire [31:0] readdata_w, alu_result_w, pcplus4_w;
    wire [4:0]  rd_w;
    wire        valid_w;
    // ---- WB ----
    wire [31:0] writedata_w;

    // ================= IF �� =================
    flopr #(.W(32)) pcreg (.clk(clk), .reset(reset), .d(pcf_next), .q(pcf));
    // BRAM 同步读取指：imem 内部 rd_r<=mem[a]（dout 边沿锁存，可推断 Block RAM），
    // imem_rd 拍 N = mem[a 拍 N-1]。riscv_pipeline 侧用 a_r（a 的延迟寄存器）
    // 作为与 imem_rd 同源的取指地址：
    //   * a_r 拍 N = a 拍 N-1；IF2 锁存 pc_f2<=a_r、instr_f2<=imem_rd
    //     （imem_rd 拍 N = mem[a 拍 N-1]）→ (pc_f2,instr_f2) 恒配对同源
    //   * stall 时 a=a_r（取指地址冻结），IF2 仍更新（锁存"已取未入 ID"的
    //     指令），reg_ifid 保持（ID 指令不动）→ stall 恢复不丢指令
    //   * pcf 在 stall 时回退到 a_r（pcf_next=stallf?a_r:...），恢复后从
    //     "最后取指地址+4"继续，与 IF2 进度对齐
    //   * stall 释放拍 a 直接用 pcf_next（跳过 pcf 的旧值），避免重复取指
    wire [31:0] imem_rd;
    wire [31:0] imem_addr;
    // reset_d：reset 释放后再保持一拍复位语义。原因：BRAM 同步读 imem 的 rd_r
    // 在 reset 期间被清 0，reset 释放后首拍 (a_r=0, rd_r=0) 是"伪取指"（IF2 应
    // 以 v0 丢弃），下一拍 (0, mem[0]) 才是真指令。若 IF2 在释放首拍就正常
    // 更新，伪指令 valid=1 抢占且污染 addr_prev，导致真指令被重复检测误抑制。
    // reset_d 期间 IF2/a_r 走复位分支：释放首拍 v0，addr_prev 保持 FFFFFFFF，
    // 释放次拍 (0, mem[0]) 配对且 valid=1 —— reset 后首条指令不丢。
    reg         reset_d;
    reg  [31:0] a_r;         // 取指地址延迟拍（与 imem_rd 同源）
    reg         stallf_prev;
    always @(posedge clk or posedge reset) begin
        if (reset) reset_d <= 1'b1;
        else       reset_d <= 1'b0;
    end
    wire        stall_release = stallf_prev && !stallf;
    wire [31:0] a_comb = mispredict   ? pcf_next :
                         stall_release ? pcf_next :
                         (pred_taken_f ? pred_target_f : pcf);
    wire [31:0] a = stallf ? a_r : a_comb;
    imem imem_i (.clk(clk), .reset(reset), .a(a), .rd(imem_rd), .rd_addr(imem_addr));
    always @(posedge clk or posedge reset) begin
        if (reset || reset_d) begin
            a_r         <= 32'b0;
            stallf_prev <= 1'b0;
        end
        else begin
            a_r         <= a;
            stallf_prev <= stallf;
        end
    end
    reg [31:0] pc_f2;
    reg [31:0] instr_f2;
    reg        pred_f2;
    reg        valid_f2;   // IF2 ��Чλ��mispredict ʱ���壨��ֹ����·��ָ������ ID/EX��
    // addr_prev/pcf_prev：��ַ�ƽ���⡣BRAM ͬ���� imem ����� (a_r, instr)
    // �� pcreg �� 1 �ģ�mispredict/����ʱ pcreg �����ȶ� pcf_next����� a_r
    // �� pcf ���ܳ��� "ͬһ��ַ������ȡ"��重复取ָ�������� pcf ��δ�ƶ���
    // a_r δ��ʱ����Ч��
    reg [31:0] addr_prev;
    reg [31:0] pcf_prev;
    always @(posedge clk or posedge reset) begin
        if (reset || reset_d) begin
            pc_f2     <= 32'b0;
            instr_f2  <= 32'b0;
            pred_f2   <= 1'b0;
            valid_f2  <= 1'b0;
            // reset 后 BRAM 同步读 rd_r 尚在复位态（=0），a_r 与 imem_rd 存在一拍错位：
            // reset 释放首拍 (a_r=0, imem_rd=0) 伪指令以 v0 丢弃（reset_d 保持复位语义），
            // 次拍 (0, mem[0]) 才是真取指。addr_prev/pcf_prev 置 FFFFFFFF
            // （与 mispredict 分支一致），使该真指令不被重复检测误抑制。
            addr_prev <= 32'hFFFFFFFF;
            pcf_prev  <= 32'hFFFFFFFF;
        end
        else if (mispredict) begin
            pc_f2     <= a_r;
            instr_f2  <= imem_rd;
            pred_f2   <= pred_taken_f;
            valid_f2  <= 1'b0;     // ��ǰ IF2 Ϊ����·��ָ�
            // �ָ�ȡָ����������� ��Ŀ���ַ���Ǳ��� F2 ��Ԥȡ�ˣ�
            // ��ʼ������Ϊ���ܵ�ַ��ʹ�ָ��ͱ� valid=1��ֻ���Ż�ָ�ȡ�ص��ظ�����
            addr_prev <= 32'hFFFFFFFF;
            pcf_prev  <= 32'hFFFFFFFF;
        end
        else if (stallf) begin
            // stall 时 IF2 保持（不更新）：a=a_r 冻结取指，reg_ifid 保持（ID 不动），
            // IF2 保持（"已取未入 ID"的指令不丢）——恢复后 reg_ifid 取 IF2 保持值，
            // 且 a 直接走 stall_release->pcf_next 从"最后取指地址+4"继续。
            // （若 stall 时 IF2 更新，会吸收 a_r 的重复指令并覆盖保持值，
            //   恢复后 reg_ifid 取到新值，stall 前的指令被跳过——hazard 测试
            //   0x28 sw x29 即因此丢失。）
            pc_f2     <= pc_f2;
            instr_f2  <= instr_f2;
            pred_f2   <= pred_f2;
            valid_f2  <= valid_f2;
        end
        else begin
            pc_f2     <= a_r;
            instr_f2  <= imem_rd;
            pred_f2   <= pred_taken_f;
            // a_r δ�ƶ��� pcf �Ѷ�����→ ���ظ�ȡ��Ϊ��Ч���ž���������
            valid_f2  <= ((a_r == addr_prev) && (pcf != pcf_prev)) ? 1'b0 : 1'b1;
            addr_prev <= a_r;
            pcf_prev  <= pcf;
        end
    end
    assign instr_f = instr_f2;

    // ---- IF/ID �Ĵ�����reg_ifid����stall ʱ enable=0 ���֣�mispredict ʱ flush----
    wire [31:0] pc_id, instr_id;
    wire        pred_id, valid_id;
    reg_ifid ifid_reg (
        .clk(clk), .reset(reset),
        .enable(~stalld),      // load-use stall ʱ���������� ID ��ָ�õ�����
        .flush(mispredict),    // ���֧����ˢ
        .pc_in(pc_f2), .instr_in(instr_f), .pred_in(pred_f2), .valid_in(valid_f2),
        .pc(pc_id), .instr(instr_id), .pred(pred_id), .valid(valid_id)
    );
    assign pcplus4_f = pcf + 32'd4;
    assign pc = pcf;
    assign instr = instr_f;

    // ================= ID �� =================
    // ʹ�� IF/ID �Ĵ�����reg_ifid�������pc_id/instr_id��
    // reg_ifid �� stall ʱ enable=0 ���֣���֤ load-use ʱ ID ��ָ���ʧ
    assign rs1_d = instr_id[19:15];
    assign rs2_d = instr_id[24:20];
    assign rd_d  = instr_id[11:7];
    assign funct3_d = instr_id[14:12];
    assign funct7_d = instr_id[31:25];
    assign opcode_d = instr_id[6:0];
    assign jalr_d = (opcode_d == 7'b1100111);

    // �Ĵ����Ѷ�����϶���ͬ��д����д���� ID �ζ�ͬ�ط���ʱ��ֱ����· WB ���
    wire [31:0] rf_rd1, rf_rd2;
    regfile rf (
        .clk(clk), .we3(regwrite_w & valid_w), .a1(rs1_d), .a2(rs2_d), .a3(rd_w),
        .wd3(writedata_w), .rd1(rf_rd1), .rd2(rf_rd2)
    );
    assign rd1_d = ((regwrite_w & valid_w) && (rd_w == rs1_d) && (rd_w != 5'b0))
                   ? writedata_w : rf_rd1;
    assign rd2_d = ((regwrite_w & valid_w) && (rd_w == rs2_d) && (rd_w != 5'b0))
                   ? writedata_w : rf_rd2;
    extend ext (.instr(instr_id[31:7]), .immsrc(immsrc_d), .immext(immext_d));
    control_unit cu (
        .opcode(opcode_d), .funct3(funct3_d), .funct7(funct7_d),
        .regwrite(regwrite_d), .alusrca(alusrca_d), .alusrcb(alusrcb_d),
        .memwrite(memwrite_d), .resultsrc(resultsrc_d), .branch(branch_d),
        .jump(jump_d), .aluop(aluop_d), .immsrc(immsrc_d), .alucontrol(alucontrol_d)
    );

    // ---- ð�ռ�⣨Load-Use��----
    // BRAM �� dmem �� EX/MEM �߱���֣�MEM �����ݿ��ã�ͨ�� d2 ��ת��
    // load �� EX ʱ�� 1 �� stall���ô�һ�� EX ʱ load �� MEM/WB �ɶ���
    assign memread_e = resultsrc_e[0] & valid_e;   // EX ��Ϊ load
    hazard_unit hu (
        .memread_e(memread_e), .rde(rd_e),
        .rs1_d(rs1_d), .rs2_d(rs2_d), .opcode_d(opcode_d),
        .stallf(stallf), .stalld(stalld), .flushe(flushe)
    );

    // ================= ID/EX �Ĵ��� =================
    // flush��flushe(load-use bubble) | mispredict(��֧����) | ~valid_f2
    // （mispredict ������ IF2 ������·��ָ�����һ���ñ�־��ס）
    reg_idex idex_reg (
        .clk(clk), .reset(reset),
        .flush(flushe | mispredict | ~valid_id),
        .regwrite_d(regwrite_d), .alusrca_d(alusrca_d), .alusrcb_d(alusrcb_d),
        .memwrite_d(memwrite_d), .branch_d(branch_d), .jump_d(jump_d),
        .resultsrc_d(resultsrc_d), .aluop_d(aluop_d), .jalr_d(jalr_d),
        .pc_d(pc_id), .rd1_d(rd1_d), .rd2_d(rd2_d), .immext_d(immext_d),
        .rs1_d(rs1_d), .rs2_d(rs2_d), .rd_d(rd_d),
        .funct3_d(funct3_d), .funct7_d(funct7_d), .opcode_d(opcode_d), .pred_d(pred_id),
        .regwrite(regwrite_e), .alusrca(alusrca_e), .alusrcb(alusrcb_e),
        .memwrite(memwrite_e), .branch(branch_e), .jump(jump_e),
        .resultsrc(resultsrc_e), .aluop(aluop_e), .jalr(jalr_e),
        .pc(pc_e), .rd1(rd1_e), .rd2(rd2_e), .immext(immext_e),
        .rs1(rs1_e), .rs2(rs2_e), .rd(rd_e),
        .funct3(funct3_e), .funct7(funct7_e), .opcode(opcode_e), .pred(pred_e),
        .valid(valid_e)
    );

    // ================= EX �� =================
    // ---- ��·ת�� ----
    // ת��Դ��load ָ��Ľ�����ڴ�����ݣ�readdata�������� ALU �������ַ��
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

    // ---- ALU �������루EX �Σ�----
    // ע�⣺addi �� I ��ָ��� funct7 �ֶ���������λ�������������� add/sub��
    //       ֻ�� R �ͣ�opcode=0110011���Ű� funct7[5] ���� add/sub
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

    // ---- ��֧/��ת���� ----
    branch_unit bu (.rs1(rs1e_data), .rs2(rs2e_data), .funct3(funct3_e), .taken(taken_e));
    assign branch_taken_e = (branch_e & taken_e) | jump_e;
    assign branch_target_e = (jump_e & ~branch_e) ? {alu_result_e[31:1], 1'b0}
                                                   : alu_result_e;   // jalr Ŀ�����
    // ���⣨BTB 128 �� PC[8:2] ������长�����ڱ���������Ƿ�֧�֣�ȡ PC �ܵ� BTB
    // ��Ŀ��（�� 0x0758 与 0x158 同 index）����ȡ��Ҫ����Ƿ�֧��ָ��被Ԥ�� taken��
    // 此时必须冲刷：��ָ���� EX ��（该指����Ⲣ���������ˣ�����Ȼȡ��）
    //   * 预测 taken 但指令非分支（B/jal/jalr 之外）→ BTB ��Ŀ��→ 纠正到 pc+4 ˳�����
    //   * jalr ��Ԥ�� taken → jalr Ŀ�궯̬（rs1），BTB �浽�ľ�Ŀ�겻����→ ��按真实目标冲刷
    //   * 条件分支/jal/jalr：预测与实际不符 → 冲刷（既有逻辑）
    wire pred_taken_nonbranch = pred_e & valid_e & ~(branch_e | jump_e);
    wire jalr_pred_taken      = pred_e & valid_e & jalr_e;
    assign mispredict = ((branch_e | jump_e) & valid_e & (branch_taken_e != pred_e))
                      | pred_taken_nonbranch
                      | jalr_pred_taken;
    assign pcplus4_e = pc_e + 32'd4;

    // ---- ��֧Ԥ�������£��� B ���� jal д�� BTB��----
    assign branch_resolved_e = (branch_e | (jump_e & ~jalr_e)) & valid_e;
    branch_predictor bp (
        .clk(clk), .reset(reset),
        .pcf(a_r), .pred_target(pred_target_f), .pred_taken(pred_taken_f),
        .branch_resolved(branch_resolved_e), .branch_taken(branch_taken_e),
        .branch_pc(pc_e), .branch_target(branch_target_e)
    );

    // ---- PC ���£����ȼ�����֧�ض��� > Ԥ��Ŀ�� > ͣ�� > PC+4��----
    // mispredict ʱ��"ʵ��ִ�з���"ȡĿ�꣺��֧ʵ������ȡ target��������ȡ PC+4
    // stall ʱ pcf �ػ��� a_r��ʹ stall �ָ���ӡ���һ��ȡָ��ַ+4"������
    assign pcf_next = mispredict            ? (branch_taken_e ? branch_target_e : pcplus4_e) :
                      (pred_taken_f & ~stallf) ? pred_target_f :
                      stallf                ? a_r :
                      pcplus4_f;

    // ================= EX/MEM �Ĵ��� =================
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

    // ================= MEM �� =================
    // MMIO���� 0xFxxxxxxx д���� -> �������д�� DMEM��
    assign io_write_m = memwrite_m & valid_m & (alu_result_m[31:28] == 4'hF);
    // dmem ��ͬ������ַ�� EX �Σ�EX/MEM �߱���ֺ� MEM �����ݿ��ã�
    // memwb �ڼ� MEM/WB �߱���� readdata��load ��� 1 �� stall �ɶ���
    // ע��：BRAM ͬ����д���˳�� sb/sh/sw ���ȣ��� MEM д（�� N ��），
    //      ͬ址 load �� EX ���ѡ 1 ��（�� N+1 ��）�߱���ȡ——dmem �߱���
    //      ���ȵ��Ǽ���д��ֵ���ټ��ⲿ readdata ��ת（�� wd_d1 ����ȫ�֣���
    //      �ƻ� lb/lh ���Ŷ���չ）；д��ע���У��� sw ������ⲻ���ת��
    dmem dmem_i (
        .clk(clk),
        .we(memwrite_m & valid_m & ~io_write_m),
        .funct3_r(funct3_m),
        .funct3_w(funct3_m),
        .rd_addr(alu_result_m),
        .wr_addr(alu_result_m),
        .wd(writedata_m),
        .rd(readdata_m)
    );

    // MMIO �Ĵ��������ͬ��һ�ģ��� FPGA ���������
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

    // ================= MEM/WB �Ĵ��� =================
    // LOCK_READDATA=0��readdata ֱͨ dmem ���——dmem ͬ���� MEM �������ݣ�
    // memwb ��������� WB �α���ɿɿ��ã���Ϊ lock ����ǰһ��
    reg_memwb #(.LOCK_READDATA(0)) memwb_reg (
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

    // ================= WB �� =================
    mux4 #(.W(32)) muxwb (.d0(alu_result_w), .d1(readdata_w), .d2(pcplus4_w),
                          .d3(32'b0), .s(resultsrc_w), .y(writedata_w));
endmodule
