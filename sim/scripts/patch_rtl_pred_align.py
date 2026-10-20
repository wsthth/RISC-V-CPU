# -*- coding: utf-8 -*-
# v0.12: pred_target 对齐修复
# 根因：riscv_pipeline.v 原 pred_target_e 影子链在每个时钟沿拷贝「当前 IF2 段指令」的预测目标，
#       而 EX 段指令是两拍前的 IF2 指令 -> pred_target_e 恒为「下一条指令」的目标（错位一拍）。
#       后果：所有「预测 taken 且实际 taken」的分支都因目标比对错位被误判 mismatch -> 每次刷流水
#       （93% mispredict 的来源，预测开反而比 PREDICT_OFF 慢）。
# 修复：pred_target 改为真正的流水寄存器：
#   - reg_ifid  增加 pred_target_in/pred_target（与 pred 同 enable/flush）
#   - reg_idex  增加 pred_target_d/pred_target（与 pred 同 flush）
#   - riscv_pipeline.v 删除影子链 pred_target_e，改接 reg_idex 输出 pred_target_e
# 全部为 ASCII 字节级补丁，兼容 UTF-8/GBK 混合注释，LF/CRLF 自动适配。
import io, sys

def patch_file(path, edits, allow_multi=False):
    data = io.open(path, 'rb').read()
    eol = b'\r\n' if b'\r\n' in data else b'\n'
    for edit in edits:
        old, new = edit[0], edit[1]
        need = 2 if (len(edit) > 2 and edit[2]) else 1
        ob = old.replace('\n', eol.decode('utf-8')).encode('ascii')
        nb = new.replace('\n', eol.decode('utf-8')).encode('ascii')
        cnt = data.count(ob)
        if cnt < need:
            print('FAIL no match(%d<%d) in %s:' % (cnt, need, path)); print('---'); print(old); print('---')
            sys.exit(1)
        data = data.replace(ob, nb, need)
    io.open(path, 'wb').write(data)
    print('OK patched', path, '(%d edits)' % len(edits))

# ================= pipe_regs.v =================
pipe = r'D:\my_project\RISC-V\rtl\pipeline\pipe_regs.v'
p_edits = [
    # ---- reg_ifid 端口 ----
    ("    input             valid_in,",
     "    input             valid_in,\n"
     "    input  [31:0]     pred_target_in,  // v0.12 pred_target pipeline reg (aligned with pred)"),
    # reg_ifid 输出：valid 原为最后一个端口，追加 pred_target
    ("    output reg        valid\n);",
     "    output reg        valid,\n"
     "    output reg [31:0] pred_target\n);"),
    # ---- reg_ifid 逻辑 ----
    ("            pc <= 32'b0; instr <= 32'b0; pred <= 1'b0; valid <= 1'b0;",
     "            pc <= 32'b0; instr <= 32'b0; pred <= 1'b0; valid <= 1'b0; pred_target <= 32'b0;"),
    ("            pc <= pc_in; instr <= instr_in; pred <= pred_in; valid <= 1'b0;",
     "            pc <= pc_in; instr <= instr_in; pred <= pred_in; valid <= 1'b0; pred_target <= pred_target_in;"),
    ("            pc <= pc_in; instr <= instr_in; pred <= pred_in; valid <= valid_in;",
     "            pc <= pc_in; instr <= instr_in; pred <= pred_in; valid <= valid_in; pred_target <= pred_target_in;"),
    # ---- reg_idex 端口 ----
    ("    input             pred_d,",
     "    input             pred_d,\n"
     "    input  [31:0]     pred_target_d,  // v0.12 pred_target pipeline reg (aligned with pred)"),
    # reg_idex 输出：pred 后追加 pred_target（第一次出现是 reg_ifid 的 pred，需用带上下文的替换）
    ("    output reg        pred,\n    output reg        valid",
     "    output reg        pred,\n    output reg [31:0] pred_target,\n    output reg        valid"),
    # ---- reg_idex 逻辑 ----
    ("opcode <= 7'b0; pred <= 1'b0;",
     "opcode <= 7'b0; pred <= 1'b0; pred_target <= 32'b0;"),
    ("funct3 <= funct3_d; funct7 <= funct7_d; opcode <= opcode_d; pred <= pred_d;",
     "funct3 <= funct3_d; funct7 <= funct7_d; opcode <= opcode_d; pred <= pred_d; pred_target <= pred_target_d;", True),
]
patch_file(pipe, p_edits)

# ================= riscv_pipeline.v =================
rtl = r'D:\my_project\RISC-V\rtl\pipeline\riscv_pipeline.v'
r_edits = [
    # 1) 声明：reg pred_target_e -> wire pred_target_id + wire pred_target_e
    ("    reg [31:0] pred_target_e;",
     "    wire [31:0] pred_target_id;   // v0.12 pred_target pipeline regs\n"
     "    wire [31:0] pred_target_e;"),
    # 2) 影子链 always 块：只保留 pred_target_f2（随 IF2 对齐），删除 pred_target_e 影子
    ("""    always @(posedge clk or posedge reset) begin
        if (reset || reset_d) begin
            pred_target_f2 <= 32'b0;
            pred_target_e  <= 32'b0;
        end
        else if (mispredict) begin
            pred_target_f2 <= pred_target_eff;
            pred_target_e  <= 32'b0;
        end
        else if (stallf) begin
            pred_target_f2 <= pred_target_f2;
            pred_target_e  <= (flushe | ~valid_id) ? 32'b0 : pred_target_f2;
        end
        else begin
            pred_target_f2 <= pred_target_eff;
            pred_target_e  <= (flushe | ~valid_id) ? 32'b0 : pred_target_f2;
        end
    end""",
     """    always @(posedge clk or posedge reset) begin
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
    end"""),
    # 3) reg_ifid 例化：输入/输出各加 pred_target
    ("        .pc_in(pc_f2), .instr_in(instr_f), .pred_in(pred_f2), .valid_in(valid_f2),",
     "        .pc_in(pc_f2), .instr_in(instr_f), .pred_in(pred_f2), .valid_in(valid_f2),\n"
     "        .pred_target_in(pred_target_f2),"),
    ("        .pc(pc_id), .instr(instr_id), .pred(pred_id), .valid(valid_id)",
     "        .pc(pc_id), .instr(instr_id), .pred(pred_id), .valid(valid_id),\n"
     "        .pred_target(pred_target_id)"),
    # 4) reg_idex 例化：输入/输出各加 pred_target
    ("        .funct3_d(funct3_d), .funct7_d(funct7_d), .opcode_d(opcode_d), .pred_d(pred_id),",
     "        .funct3_d(funct3_d), .funct7_d(funct7_d), .opcode_d(opcode_d), .pred_d(pred_id),\n"
     "        .pred_target_d(pred_target_id),"),
    ("        .funct3(funct3_e), .funct7(funct7_e), .opcode(opcode_e), .pred(pred_e),",
     "        .funct3(funct3_e), .funct7(funct7_e), .opcode(opcode_e), .pred(pred_e),\n"
     "        .pred_target(pred_target_e),"),
]
patch_file(rtl, r_edits)
print('ALL PATCHED')
