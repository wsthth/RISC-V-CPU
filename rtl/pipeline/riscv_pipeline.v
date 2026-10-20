`timescale 1ns/1ps
// ============================================================================
// riscv_pipeline.v - RV32I 锟藉级锟斤拷水锟竭达拷锟斤拷锟斤拷锟斤拷IF/ID/EX/MEM/WB锟斤拷
//
// 锟斤拷锟皆ｏ拷
//   * 锟斤拷锟斤拷 RV32I 锟斤拷锟斤拷指锟筋集
//   * 锟斤拷锟斤拷冒锟秸ｏ拷EX/MEM 锟斤拷 MEM/WB 锟斤拷锟斤拷锟斤拷路转锟斤拷 + Load-Use 停锟斤拷
//   * 锟斤拷锟斤拷冒锟秸ｏ拷2-bit 锟斤拷锟酵硷拷锟斤拷锟斤拷锟斤拷支预锟斤拷 + BTB锟斤拷锟斤拷支/锟斤拷转锟斤拷 EX 锟斤拷锟斤拷锟斤拷
//     预锟斤拷锟斤拷锟斤拷刷 IF/ID 锟斤拷 ID/EX 锟斤拷锟斤拷
//   * jal/jalr 锟斤拷 EX 锟轿斤拷锟斤拷锟斤拷jalr 目锟斤拷锟?1 位锟斤拷锟姐（RISC-V 锟芥范锟斤拷
//   * 锟斤拷选 MMIO锟斤拷锟斤拷 0xFxxxxxxx 锟斤拷址写锟斤拷锟斤拷时锟斤拷锟?io_write/io_wdata锟斤拷FPGA 锟斤拷示锟矫ｏ拷
// ============================================================================
module riscv_pipeline #(parameter DEPTH = 8192, parameter PREDICT = 1) (
    input        clk,
    input        reset,
    // ---- 锟桔诧拷丝冢锟絋B/锟斤拷锟皆ｏ拷----
    output wire [31:0] pc,
    output wire [31:0] instr,
    output wire        io_write,
    output wire [31:0] io_wdata
);
    // ================= 全锟斤拷锟节诧拷锟脚猴拷锟斤拷锟斤拷 =================
    // ---- IF ----
    wire [31:0] pcf, pcf_next, pcplus4_f, instr_f;
    wire        pred_taken_f;
    wire [31:0] pred_target_f;
    // PREDICT 参数开关（v0.8 重建）：=0 时强制关预测，供 CoreMark 仿真调试
    wire        pred_taken_eff  = PREDICT ? pred_taken_f  : 1'b0;
    wire [31:0] pred_target_eff = PREDICT ? pred_target_f : 32'b0;
    // ---- 冒锟秸匡拷锟斤拷 ----
    wire        stallf, stalld, flushe;
    wire        mispredict;
    // ---- IF/ID ----锛圛F2 锟斤拷取指锟斤拷锟缴硷拷锟斤拷锛歩nstr_f + pc_f2 + pred_f2锟斤拷
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
    // ---- ID/EX 锟斤拷锟?----
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
    // ---- EX/MEM 锟斤拷锟?----
    wire        regwrite_m, memwrite_m;
    wire [1:0]  resultsrc_m;
    wire [2:0]  funct3_m;
    wire [31:0] pcplus4_m, alu_result_m, writedata_m;
    wire [4:0]  rd_m;
    wire        valid_m;
    // ---- MEM ----
    wire [31:0] readdata_m;
    wire [31:0] readdata_dmem;
    wire        io_write_m;
    // ---- MEM/WB 锟斤拷锟?----
    wire        regwrite_w;
    wire [1:0]  resultsrc_w;
    wire [31:0] readdata_w, alu_result_w, pcplus4_w;
    wire [4:0]  rd_w;
    wire        valid_w;
    // ---- WB ----
    wire [31:0] writedata_w;

    // ================= IF 锟斤拷 =================
    flopr #(.W(32)) pcreg (.clk(clk), .reset(reset), .d(pcf_next), .q(pcf));
    // BRAM 鍚屾�ヨ�诲彇鎸囷細imem 鍐呴儴 rd_r<=mem[a]锛坉out 杈规部閿佸瓨锛屽彲鎺ㄦ柇 Block RAM锛夛紝
    // imem_rd 鎷?N = mem[a 鎷?N-1]銆俽iscv_pipeline 渚х敤 a_r锛坅 鐨勫欢杩熷瘎瀛樺櫒锛?
    // 浣滀负涓?imem_rd 鍚屾簮鐨勫彇鎸囧湴鍧�锛?
    //   * a_r 鎷?N = a 鎷?N-1锛汭F2 閿佸瓨 pc_f2<=a_r銆乮nstr_f2<=imem_rd
    //     锛坕mem_rd 鎷?N = mem[a 鎷?N-1]锛夆啋 (pc_f2,instr_f2) 鎭掗厤瀵瑰悓婧?
    //   * stall 鏃?a=a_r锛堝彇鎸囧湴鍧�鍐荤粨锛夛紝IF2 浠嶆洿鏂帮紙閿佸瓨"宸插彇鏈�鍏� ID"鐨?
    //     鎸囦护锛夛紝reg_ifid 淇濇寔锛圛D 鎸囦护涓嶅姩锛夆啋 stall 鎭㈠�嶄笉涓㈡寚浠�
    //   * pcf 鍦?stall 鏃跺洖閫�鍒?a_r锛坧cf_next=stallf?a_r:...锛夛紝鎭㈠�嶅悗浠�
    //     "鏈�鍚庡彇鎸囧湴鍧�+4"缁х画锛屼笌 IF2 杩涘害瀵归綈
    //   * stall 閲婃斁鎷?a 鐩存帴鐢?pcf_next锛堣烦杩?pcf 鐨勬棫鍊硷級锛岄伩鍏嶉噸澶嶅彇鎸?
    wire [31:0] imem_rd;
    wire [31:0] imem_addr;
    // reset_d锛歳eset 閲婃斁鍚庡啀淇濇寔涓�鎷嶅�嶄綅璇�涔夈�傚師鍥狅細BRAM 鍚屾�ヨ�?imem 鐨?rd_r
    // 鍦?reset 鏈熼棿琚�娓� 0锛宺eset 閲婃斁鍚庨�栨�?(a_r=0, rd_r=0) 鏄?浼�鍙栨�?锛圛F2 搴?
    // 浠?v0 涓㈠純锛夛紝涓嬩竴鎷?(0, mem[0]) 鎵嶆槸鐪熸寚浠ゃ�傝嫢 IF2 鍦ㄩ噴鏀鹃�栨媿灏辨�ｅ父
    // 鏇存柊锛屼吉鎸囦护 valid=1 鎶㈠崰涓旀薄鏌?addr_prev锛屽�艰嚧鐪熸寚浠よ��閲嶅�嶆��娴嬭��鎶戝埗銆?
    // reset_d 鏈熼棿 IF2/a_r 璧板�嶄綅鍒嗘敮锛氶噴鏀鹃�栨媿 v0锛宎ddr_prev 淇濇寔 FFFFFFFF锛?
    // 閲婃斁娆℃媿 (0, mem[0]) 閰嶅�逛�?valid=1 鈥斺�?reset 鍚庨�栨潯鎸囦护涓嶄涪銆?
    reg         reset_d;
    reg  [31:0] a_r;         // 鍙栨寚鍦板潃寤惰繜鎷嶏紙涓?imem_rd 鍚屾簮锛?
    reg         stallf_prev;
    always @(posedge clk or posedge reset) begin
        if (reset) reset_d <= 1'b1;
        else       reset_d <= 1'b0;
    end
    wire        stall_release = stallf_prev && !stallf;
    wire [31:0] a_comb = mispredict   ? pcf_next :
                         stall_release ? pcf_next :
                         (pred_taken_eff ? pred_target_eff : pcf);
    wire [31:0] a = stallf ? a_r : a_comb;
    imem #(.DEPTH(DEPTH)) imem_i (.clk(clk), .reset(reset), .a(a), .rd(imem_rd), .rd_addr(imem_addr));
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
    reg        valid_f2;
    reg [31:0] pred_target_f2;  // IF2 段预测目标（与 pred_f2 同步）
    wire [31:0] pred_target_id;   // v0.12 pred_target pipeline regs
    wire [31:0] pred_target_e;   // ID/EX 段预测目标（与 pred_e 同步，flush 清 0）   // IF2 锟斤拷效位锟斤拷mispredict 时锟斤拷锟藉（锟斤拷止锟斤拷锟斤拷路锟斤拷指锟斤拷锟斤拷锟斤拷 ID/EX锟斤拷
    // addr_prev/pcf_prev锛氾拷锟街凤拷平锟斤拷锟解。BRAM 同锟斤拷锟斤拷 imem 锟斤拷锟斤拷锟?(a_r, instr)
    // 锟斤拷 pcreg 锟斤拷 1 锟侥ｏ拷mispredict/锟斤拷锟斤拷时 pcreg 锟斤拷锟斤拷锟饺讹拷 pcf_next锟斤拷锟斤拷锟?a_r
    // 锟斤拷 pcf 锟斤拷锟杰筹拷锟斤拷 "同一锟斤拷址锟斤拷锟斤拷锟斤拷取"锟斤拷閲嶅�嶅彇指锟斤拷锟斤拷锟斤拷锟斤�?pcf 锟斤拷未锟狡讹拷锟斤拷
    // a_r 未锟斤拷时锟斤拷锟斤拷效锟斤拷
    reg [31:0] addr_prev;
    reg [31:0] pcf_prev;
    always @(posedge clk or posedge reset) begin
        if (reset || reset_d) begin
            pc_f2     <= 32'b0;
            instr_f2  <= 32'b0;
            pred_f2   <= 1'b0;
            valid_f2  <= 1'b0;
            // reset 鍚?BRAM 鍚屾�ヨ�?rd_r 灏氬湪澶嶄綅鎬侊紙=0锛夛紝a_r 涓?imem_rd 瀛樺湪涓�鎷嶉敊浣嶏細
            // reset 閲婃斁棣栨媿 (a_r=0, imem_rd=0) 浼�鎸囦护浠� v0 涓㈠純锛坮eset_d 淇濇寔澶嶄綅璇�涔夛級锛�
            // 娆℃媿 (0, mem[0]) 鎵嶆槸鐪熷彇鎸囥�俛ddr_prev/pcf_prev 缃?FFFFFFFF
            // 锛堜笌 mispredict 鍒嗘敮涓�鑷达級锛屼娇璇ョ湡鎸囦护涓嶈��閲嶅�嶆��娴嬭��鎶戝埗銆?
            addr_prev <= 32'hFFFFFFFF;
            pcf_prev  <= 32'hFFFFFFFF;
        end
        else if (mispredict) begin
            pc_f2     <= a_r;
            instr_f2  <= imem_rd;
            pred_f2   <= pred_taken_eff;
            valid_f2  <= 1'b0;     // 锟斤拷前 IF2 为锟斤拷锟斤拷路锟斤拷指锟?
            // 锟街革拷取指锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟?锟斤拷目锟斤拷锟街凤拷锟斤拷潜锟斤拷锟?F2 锟斤拷预取锟剿ｏ拷
            // 锟斤拷始锟斤拷锟斤拷锟斤拷为锟斤拷锟杰碉拷址锟斤拷使锟街革拷锟酵憋拷 valid=1锟斤拷只锟斤拷锟脚伙拷指锟饺★拷氐锟斤拷馗锟斤拷锟斤拷锟?
            addr_prev <= 32'hFFFFFFFF;
            pcf_prev  <= 32'hFFFFFFFF;
        end
        else if (stallf) begin
            // stall 鏃?IF2 淇濇寔锛堜笉鏇存柊锛夛細a=a_r 鍐荤粨鍙栨寚锛宺eg_ifid 淇濇寔锛圛D 涓嶅姩锛夛紝
            // IF2 淇濇寔锛?宸插彇鏈�鍏� ID"鐨勬寚浠や笉涓�锛夆�斺�旀仮澶嶅悗 reg_ifid 鍙?IF2 淇濇寔鍊硷紝
            // 涓?a 鐩存帴璧?stall_release->pcf_next 浠?鏈�鍚庡彇鎸囧湴鍧�+4"缁х画銆?
            // 锛堣嫢 stall 鏃?IF2 鏇存柊锛屼細鍚告敹 a_r 鐨勯噸澶嶆寚浠ゅ苟瑕嗙洊淇濇寔鍊硷紝
            //   鎭㈠�嶅�?reg_ifid 鍙栧埌鏂板�硷紝stall 鍓嶇殑鎸囦护琚�璺宠繃鈥斺�攈azard 娴嬭瘯
            //   0x28 sw x29 鍗冲洜姝や涪澶便�傦級
            pc_f2     <= pc_f2;
            instr_f2  <= instr_f2;
            pred_f2   <= pred_f2;
            valid_f2  <= valid_f2;
        end
        else begin
            pc_f2     <= a_r;
            instr_f2  <= imem_rd;
            pred_f2   <= pred_taken_eff;
            // a_r 未锟狡讹拷锟斤拷 pcf 锟窖讹拷锟斤拷锟斤拷鈫?锟斤拷锟截革拷取锟斤拷为锟斤拷效锟斤拷锟脚撅拷锟斤拷锟斤拷锟斤拷锟斤拷
            valid_f2  <= ((a_r == addr_prev) && (pcf != pcf_prev)) ? 1'b0 : 1'b1;
            addr_prev <= a_r;
            pcf_prev  <= pcf;
        end
    end
    assign instr_f = instr_f2;
    // v0.15: suppress the spurious DOUBLE CAPTURE at reg_ifid by comparing
    // the IF2 content against the ID content (NOT the fetch address):
    //   dup = (pc_f2 == pc_id) && valid_id && ~pred_taken_eff
    // The IF2 register lags a_r by one cycle. After a load-use stall release
    // the else-branch re-captures the frozen a_r, so the IF2 holds the same
    // instruction for an extra cycle and reg_ifid re-captures it (double
    // commit), while a_r has already advanced - an address-based rule misses
    // this dup and later false-positives on the legitimate next capture.
    // Content equality (same pc still valid in ID) catches all dup sources:
    //  - stall-release lag (lbu re-captured, sw skipped - full.s FAIL)
    //  - pred-taken redirect target re-read (CoreMark double commit)
    //  - mispredict target repeat (flush clears valid_id -> not suppressed,
    //    the intended target capture is protected)
    // ~pred_taken_eff: self-loops / branch chains whose address IS predicted
    // taken (j to itself) are architecturally correct re-executions - never
    // suppress them.
    wire        dup_fetch;
    wire        valid_ifid_in;

    // ---- IF/ID 锟侥达拷锟斤拷锟斤拷reg_ifid锟斤拷锟斤拷stall 时 enable=0 锟斤拷锟街ｏ拷mispredict 时 flush----
    wire [31:0] pc_id, instr_id;
    wire        pred_id, valid_id;
    reg_ifid ifid_reg (
        .clk(clk), .reset(reset),
        .enable(~stalld),      // load-use stall 时锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷 ID 锟斤拷指锟矫碉拷锟斤拷锟斤拷
        .flush(mispredict),    // 锟斤拷锟街э拷锟斤拷锟剿?
        .pc_in(pc_f2), .instr_in(instr_f), .pred_in(pred_f2), .valid_in(valid_ifid_in),
        .pred_target_in(pred_target_f2),
        .pc(pc_id), .instr(instr_id), .pred(pred_id), .valid(valid_id),
        .pred_target(pred_target_id)
    );
    assign dup_fetch = (pc_f2 == pc_id) && valid_id && ~pred_taken_eff;
    assign valid_ifid_in = dup_fetch ? 1'b0 : valid_f2;
    // v0.9: 预测目标沿流水传递（IF2 -> ID/EX），供 mispredict 目标一致性检查
    always @(posedge clk or posedge reset) begin
        if (reset || reset_d) begin
            pred_target_f2 <= 32'b0;
        end
        else if (mispredict) begin
            pred_target_f2 <= pred_target_eff;
        end
        else if (stallf) begin
            pred_target_f2 <= pred_target_f2;
        end
        else begin
            pred_target_f2 <= pred_target_eff;
        end
    end

    assign pcplus4_f = pcf + 32'd4;
    assign pc = pcf;
    assign instr = instr_f;

    // ================= ID 锟斤拷 =================
    // 使锟斤拷 IF/ID 锟侥达拷锟斤拷锟斤拷reg_ifid锟斤拷锟斤拷锟斤拷锟絧c_id/instr_id锟斤拷
    // reg_ifid 锟斤拷 stall 时 enable=0 锟斤拷锟街ｏ拷锟斤拷证 load-use 时 ID 锟斤拷指锟斤拷锟绞?
    assign rs1_d = instr_id[19:15];
    assign rs2_d = instr_id[24:20];
    assign rd_d  = instr_id[11:7];
    assign funct3_d = instr_id[14:12];
    assign funct7_d = instr_id[31:25];
    assign opcode_d = instr_id[6:0];
    assign jalr_d = (opcode_d == 7'b1100111);

    // 锟侥达拷锟斤拷锟窖讹拷锟斤拷锟斤拷隙锟斤拷锟酵�锟斤拷写锟斤拷锟斤拷写锟斤拷锟斤�?ID 锟轿讹拷同锟截凤拷锟斤拷时锟斤拷直锟斤拷锟斤拷路 WB 锟斤拷锟?
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

    // ---- 冒锟秸硷拷猓↙oad-Use锟斤拷----
    // BRAM 锟斤拷 dmem 锟斤拷 EX/MEM 锟竭憋拷锟斤拷郑锟組EM 锟斤拷锟斤拷锟捷匡拷锟矫ｏ拷通锟斤拷 d2 锟斤拷转锟斤拷
    // load 锟斤拷 EX 时锟斤拷 1 锟斤拷 stall锟斤拷锟矫达拷一锟斤拷 EX 时 load 锟斤拷 MEM/WB 锟缴讹拷锟斤拷
    assign memread_e = resultsrc_e[0] & valid_e;   // EX 锟斤拷为 load
    hazard_unit hu (
        .memread_e(memread_e), .rde(rd_e),
        .rs1_d(rs1_d), .rs2_d(rs2_d), .opcode_d(opcode_d),
        .stallf(stallf), .stalld(stalld), .flushe(flushe)
    );

    // ================= ID/EX 锟侥达拷锟斤拷 =================
    // flush锟斤拷flushe(load-use bubble) | mispredict(锟斤拷支锟斤拷锟斤拷) | ~valid_f2
    // 锛坢ispredict 锟斤拷锟斤拷锟斤拷 IF2 锟斤拷锟斤拷锟斤拷路锟斤拷指锟斤拷锟斤拷锟揭伙拷锟斤拷帽锟街撅拷锟阶★級
    reg_idex idex_reg (
        .clk(clk), .reset(reset),
        .flush(flushe | mispredict | ~valid_id),
        .regwrite_d(regwrite_d), .alusrca_d(alusrca_d), .alusrcb_d(alusrcb_d),
        .memwrite_d(memwrite_d), .branch_d(branch_d), .jump_d(jump_d),
        .resultsrc_d(resultsrc_d), .aluop_d(aluop_d), .jalr_d(jalr_d),
        .pc_d(pc_id), .rd1_d(rd1_d), .rd2_d(rd2_d), .immext_d(immext_d),
        .rs1_d(rs1_d), .rs2_d(rs2_d), .rd_d(rd_d),
        .funct3_d(funct3_d), .funct7_d(funct7_d), .opcode_d(opcode_d), .pred_d(pred_id),
        .pred_target_d(pred_target_id),
        .regwrite(regwrite_e), .alusrca(alusrca_e), .alusrcb(alusrcb_e),
        .memwrite(memwrite_e), .branch(branch_e), .jump(jump_e),
        .resultsrc(resultsrc_e), .aluop(aluop_e), .jalr(jalr_e),
        .pc(pc_e), .rd1(rd1_e), .rd2(rd2_e), .immext(immext_e),
        .rs1(rs1_e), .rs2(rs2_e), .rd(rd_e),
        .funct3(funct3_e), .funct7(funct7_e), .opcode(opcode_e), .pred(pred_e),
        .pred_target(pred_target_e),
        .valid(valid_e)
    );

    // ================= EX 锟斤拷 =================
    // ---- 锟斤拷路转锟斤拷 ----
    // 转锟斤拷源锟斤拷load 指锟斤拷慕锟斤拷锟斤拷锟节达拷锟斤拷锟斤拷荩锟絩eaddata锟斤拷锟斤拷锟斤拷锟斤拷 ALU 锟斤拷锟斤拷锟斤拷锟街凤拷锟?
    wire [31:0] mem_result_m, wb_result_w;
    assign mem_result_m = (resultsrc_m == 2'b10) ? pcplus4_m :
                      (resultsrc_m[0] ? readdata_m : alu_result_m);   // v0.13 JAL link forward
    // assign wb_result_w  = resultsrc_w[0] ? readdata_w : alu_result_w;  // (v0.8) 移至 WB 段 readdata_final
    forward_unit fu (
        .rs1_e(rs1_e), .rs2_e(rs2_e), .rdm(rd_m), .rdw(rd_w),
        .regwrite_m(regwrite_m & valid_m), .regwrite_w(regwrite_w & valid_w),
        .forwardae(forwardae), .forwardbe(forwardbe)
    );
    mux3 #(.W(32)) fwa (.d0(rd1_e), .d1(wb_result_w), .d2(mem_result_m),
                        .s(forwardae), .y(rs1e_data));
    mux3 #(.W(32)) fwb (.d0(rd2_e), .d1(wb_result_w), .d2(mem_result_m),
                        .s(forwardbe), .y(rs2e_data));

    // ---- ALU 锟斤拷锟斤拷锟斤拷锟诫（EX 锟轿ｏ拷----
    // 注锟解：addi 锟斤拷 I 锟斤拷指锟斤拷锟?funct7 锟街讹拷锟斤拷锟斤拷锟斤拷锟斤拷位锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷 add/sub锟斤拷
    //       只锟斤拷 R 锟酵ｏ拷opcode=0110011锟斤拷锟脚帮拷 funct7[5] 锟斤拷锟斤拷 add/sub
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

    // ---- 锟斤拷支/锟斤拷转锟斤拷锟斤拷 ----
    branch_unit bu (.rs1(rs1e_data), .rs2(rs2e_data), .funct3(funct3_e), .taken(taken_e));
    assign branch_taken_e = (branch_e & taken_e) | jump_e;
    assign branch_target_e = (jump_e & ~branch_e) ? {alu_result_e[31:1], 1'b0}
                                                   : alu_result_e;   // jalr 目锟斤拷锟斤拷锟?
    // 锟斤拷锟解（BTB 128 锟斤拷 PC[8:2] 锟斤拷锟斤拷锟斤拷闀匡拷锟斤拷锟斤拷诒锟斤拷锟斤拷锟斤拷锟斤拷锟角凤拷支锟街ｏ拷取 PC 锟杰碉拷 BTB
    // 锟斤拷目锟斤拷锛堬拷锟?0x0758 涓?0x158 鍚?index锛夛拷锟斤拷锟饺★拷锟揭�锟斤拷锟斤拷欠锟街э拷锟街革拷锟借��预锟斤�?taken锟斤拷
    // 姝ゆ椂蹇呴』鍐插埛锛氾拷锟街革拷锟斤拷锟?EX 锟斤拷锛堣�ユ寚锟斤拷锟斤拷獠�锟斤拷锟斤拷锟斤拷锟斤拷锟剿ｏ拷锟斤拷锟斤拷然取锟斤拷锛?
    //   * 棰勬祴 taken 浣嗘寚浠ら潪鍒嗘敮锛圔/jal/jalr 涔嬪�栵級鈫� BTB 锟斤拷目锟斤拷鈫?绾犳�ｅ�?pc+4 顺锟斤拷锟斤拷锟?
    //   * jalr 锟斤拷预锟斤拷 taken 鈫?jalr 目锟疥动态锛坮s1锛夛紝BTB 锟芥到锟侥撅拷目锟疥不锟斤拷锟斤拷鈫?锟斤拷鎸夌湡瀹炵洰鏍囧啿鍒?
    //   * 鏉′欢鍒嗘敮/jal/jalr锛氶�勬祴涓庡疄闄呬笉绗� 鈫?鍐插埛锛堟棦鏈夐�昏緫锛?
    wire pred_taken_nonbranch = pred_e & valid_e & ~(branch_e | jump_e);
    wire jalr_pred_taken      = pred_e & valid_e & jalr_e;
    // v0.9: BTB 别名污染（PC[8:2] 共享索引）导致预测目标错误：
    //   方向相同（都 taken）但目标不同 -> 也判 mispredict，按实际目标重定向
    wire branch_target_mismatch = valid_e & pred_e & ~jalr_e & (branch_e | jump_e) &
                                 (pred_target_e != branch_target_e);
    assign mispredict = ((branch_e | jump_e) & valid_e & (branch_taken_e != pred_e))
                      | pred_taken_nonbranch
                      | jalr_pred_taken
                      | branch_target_mismatch;
    assign pcplus4_e = pc_e + 32'd4;

    // ---- 锟斤拷支预锟斤拷锟斤拷锟斤拷锟铰ｏ拷锟斤拷 B 锟斤拷锟斤拷 jal 写锟斤拷 BTB锟斤拷----
    assign branch_resolved_e = (branch_e | (jump_e & ~jalr_e)) & valid_e;
    branch_predictor bp (
        .clk(clk), .reset(reset),
        .pcf(a_r), .pred_target(pred_target_f), .pred_taken(pred_taken_f),
        .branch_resolved(branch_resolved_e), .branch_taken(branch_taken_e),
        .branch_pc(pc_e), .branch_target(branch_target_e)
    );

    // ---- PC 锟斤拷锟铰ｏ拷锟斤拷锟饺硷拷锟斤拷锟斤拷支锟截讹拷锟斤拷 > 预锟斤拷目锟斤拷 > 停锟斤拷 > PC+4锟斤拷----
    // mispredict 时锟斤拷"实锟斤拷执锟叫凤拷锟斤拷"取目锟疥：锟斤拷支实锟斤拷锟斤拷锟斤拷取 target锟斤拷锟斤拷锟斤拷锟斤拷取 PC+4
    // stall 时 pcf 锟截伙拷锟斤拷 a_r锟斤拷使 stall 锟街革拷锟斤拷印锟斤拷锟揭伙拷锟饺≈革拷锟街?4"锟斤拷锟斤拷锟斤拷
    assign pcf_next = mispredict            ? (branch_taken_e ? branch_target_e : pcplus4_e) :
                      (pred_taken_eff & ~stallf) ? pred_target_eff :
                      stallf                ? a_r :
                      pcplus4_f;

    // ================= EX/MEM 锟侥达拷锟斤拷 =================
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

    // ================= MEM 锟斤拷 =================
    // MMIO锟斤拷锟斤拷 0xFxxxxxxx 写锟斤拷锟斤拷 -> 锟斤拷锟斤拷锟斤拷锟叫达拷锟?DMEM锟斤拷
    assign io_write_m = memwrite_m & valid_m & (alu_result_m[31:28] == 4'hF);
    // dmem 锟斤拷同锟斤拷锟斤拷锟斤拷址锟斤拷 EX 锟轿ｏ拷EX/MEM 锟竭憋拷锟斤拷趾锟?MEM 锟斤拷锟斤拷锟捷匡拷锟矫ｏ拷
    // memwb 锟节硷拷 MEM/WB 锟竭憋拷锟斤拷锟?readdata锟斤拷load 锟斤拷锟?1 锟斤拷 stall 锟缴讹拷锟斤拷
    // 注锟斤拷锛欱RAM 同锟斤拷锟斤拷写锟斤拷锟剿筹拷锟?sb/sh/sw 锟斤拷锟饺ｏ拷锟斤拷 MEM 写锛堬拷锟?N 锟斤拷锛夛紝
    //      同鍧� load 锟斤拷 EX 锟斤拷锟窖?1 锟斤拷锛堬拷锟?N+1 锟斤拷锛夛拷弑锟斤拷锟饺♀�斺�攄mem 锟竭憋拷锟斤拷
    //      锟斤拷锟饺碉拷锟角硷拷锟斤拷写锟斤拷值锟斤拷锟劫硷拷锟解部 readdata 锟斤拷转锛堬拷锟?wd_d1 锟斤拷锟斤拷全锟街ｏ拷锟斤拷
    //      锟狡伙拷 lb/lh 锟斤拷锟脚讹拷锟斤拷展锛夛紱写锟斤拷注锟斤拷锟叫ｏ拷锟斤拷 sw 锟斤拷锟斤拷锟斤拷獠伙拷锟斤拷转锟斤拷
    dmem #(.DEPTH(DEPTH)) dmem_i (
        .clk(clk),
        .we(memwrite_m & valid_m & ~io_write_m),
        .funct3_r(funct3_m),
        .funct3_w(funct3_m),
        .rd_addr(alu_result_m),
        .rd_addr2(alu_result_m + 32'd4),
        .wr_addr(alu_result_m),
        .wd(writedata_m),
        .rd(readdata_dmem)
    );


    reg [31:0] cycle_cnt;
    always @(posedge clk or posedge reset) begin
        if (reset) cycle_cnt <= 32'b0;
        else       cycle_cnt <= cycle_cnt + 32'd1;
    end
    wire mmio_read_m = resultsrc_m[0] & valid_m & (alu_result_m == 32'hF0000004);
    assign readdata_m = mmio_read_m ? cycle_cnt : readdata_dmem;
    // MMIO 读数据在 WB 段选择（v0.8 修复）：
    // LOCK_READDATA=0 直通下 readdata_w 随 MEM 段漂移；普通 dmem load 靠 dmem 同步读
    // 滞后 1 拍碰巧正确，MMIO(cycle_cnt) 则在 WB 段失效落到 readdata_dmem(越界 X)。
    // 故按 lw 特征(resultsrc_w[0]&valid_w&alu_result_w==F0000004)在 WB 段重选 cycle_cnt。
    wire mmio_read_w = resultsrc_w[0] & valid_w & (alu_result_w == 32'hF0000004);
    wire [31:0] readdata_final = mmio_read_w ? cycle_cnt : readdata_w;
    assign wb_result_w = (resultsrc_w == 2'b10) ? pcplus4_w :
                      (resultsrc_w[0] ? readdata_final : alu_result_w);   // v0.13 JAL link forward

    // MMIO 锟侥达拷锟斤拷锟斤拷锟斤拷锟酵�锟斤拷一锟侥ｏ拷锟斤�?FPGA 锟斤拷锟斤拷锟斤拷锟斤拷锟?
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

    // ================= MEM/WB 锟侥达拷锟斤拷 =================
    // LOCK_READDATA=0锟斤拷readdata 直通 dmem 锟斤拷锟解�斺�攄mem 同锟斤拷锟斤拷 MEM 锟斤拷锟斤拷锟斤拷锟捷ｏ拷
    // memwb 锟斤拷锟斤拷锟斤拷锟斤拷锟?WB 锟轿憋拷锟斤拷煽煽锟斤拷茫锟斤拷锟轿?lock 锟斤拷锟斤拷前一锟斤拷
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

    // ================= WB 锟斤拷 =================
    mux4 #(.W(32)) muxwb (.d0(alu_result_w), .d1(readdata_final), .d2(pcplus4_w),
                          .d3(32'b0), .s(resultsrc_w), .y(writedata_w));
endmodule
