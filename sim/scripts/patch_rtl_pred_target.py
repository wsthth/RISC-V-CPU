# -*- coding: utf-8 -*-
# patch_rtl_pred_target.py - v0.9 预测目标一致性修复
# 根因：mispredict 只比较方向(branch_taken_e != pred_e)，不比较目标。
#   BTB 别名污染(PC[8:2] 128项索引，coremark 3.3KB 代码必然共享索引)时，
#   "预测 taken 且实际 taken 但目标错误" → mispredict 不触发 → 按错误 BTB 目标执行
#   → 错误指令提交 → udivsi3 算错(0x20c49b) → 链表指针越界 → X 蔓延 → PC=X 崩溃。
# 修复：pred_target 沿流水传递(IF2 -> ID/EX)，EX 段与实际目标比较，
#   branch_target_mismatch 也判 mispredict → pcf_next 重定向到实际目标。
# 安全：文件为 UTF-8，str 级匹配(不触碰乱码注释的语义)，断言命中后 tempfile+os.replace 原子写回。
import io, os, tempfile

p = r'D:\my_project\RISC-V\rtl\pipeline\riscv_pipeline.v'
s = io.open(p, 'r', encoding='utf-8').read()
orig = s
EOL = '\r\n' if '\r\n' in s else '\n'

def repl(old, new, tag):
    global s
    n = s.count(old)
    assert n == 1, '[%s] match %d != 1: %r' % (tag, n, old[:100])
    s = s.replace(old, new)
    print('[%s] OK' % tag)

# A. 声明 pred_target_f2 / pred_target_e（在 valid_f2 声明后）
repl('    reg        valid_f2;',
     '    reg        valid_f2;' + EOL +
     '    reg [31:0] pred_target_f2;  // IF2 段预测目标（与 pred_f2 同步）' + EOL +
     '    reg [31:0] pred_target_e;   // ID/EX 段预测目标（与 pred_e 同步，flush 清 0）',
     'A-decl')

# B. 预测目标传递 always 块（插在 pcplus4_f 之前）
repl('    assign pcplus4_f = pcf + 32\'d4;',
     '    // v0.9: 预测目标沿流水传递（IF2 -> ID/EX），供 mispredict 目标一致性检查' + EOL +
     '    always @(posedge clk or posedge reset) begin' + EOL +
     '        if (reset || reset_d) begin' + EOL +
     '            pred_target_f2 <= 32\'b0;' + EOL +
     '            pred_target_e  <= 32\'b0;' + EOL +
     '        end' + EOL +
     '        else if (mispredict) begin' + EOL +
     '            pred_target_f2 <= pred_target_eff;' + EOL +
     '            pred_target_e  <= 32\'b0;' + EOL +
     '        end' + EOL +
     '        else if (stallf) begin' + EOL +
     '            pred_target_f2 <= pred_target_f2;' + EOL +
     '            pred_target_e  <= (flushe | ~valid_id) ? 32\'b0 : pred_target_f2;' + EOL +
     '        end' + EOL +
     '        else begin' + EOL +
     '            pred_target_f2 <= pred_target_eff;' + EOL +
     '            pred_target_e  <= (flushe | ~valid_id) ? 32\'b0 : pred_target_f2;' + EOL +
     '        end' + EOL +
     '    end' + EOL +
     EOL +
     '    assign pcplus4_f = pcf + 32\'d4;',
     'B-passthru')

# C. mispredict 增加目标一致性检查
repl('    wire pred_taken_nonbranch = pred_e & valid_e & ~(branch_e | jump_e);' + EOL +
     '    wire jalr_pred_taken      = pred_e & valid_e & jalr_e;' + EOL +
     '    assign mispredict = ((branch_e | jump_e) & valid_e & (branch_taken_e != pred_e))' + EOL +
     '                      | pred_taken_nonbranch' + EOL +
     '                      | jalr_pred_taken;',
     '    wire pred_taken_nonbranch = pred_e & valid_e & ~(branch_e | jump_e);' + EOL +
     '    wire jalr_pred_taken      = pred_e & valid_e & jalr_e;' + EOL +
     '    // v0.9: BTB 别名污染（PC[8:2] 共享索引）导致预测目标错误：' + EOL +
     '    //   方向相同（都 taken）但目标不同 -> 也判 mispredict，按实际目标重定向' + EOL +
     '    wire branch_target_mismatch = valid_e & pred_e & ~jalr_e & (branch_e | jump_e) &' + EOL +
     '                                 (pred_target_e != branch_target_e);' + EOL +
     '    assign mispredict = ((branch_e | jump_e) & valid_e & (branch_taken_e != pred_e))' + EOL +
     '                      | pred_taken_nonbranch' + EOL +
     '                      | jalr_pred_taken' + EOL +
     '                      | branch_target_mismatch;',
     'C-mispredict')

assert s != orig, 'no change'
# 原子写回（UTF-8，保留原行尾）
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p), suffix='.tmp')
try:
    with os.fdopen(fd, 'w', encoding='utf-8', newline='') as f:
        f.write(s)
    os.replace(tmp, p)
finally:
    if os.path.exists(tmp):
        try: os.remove(tmp)
        except OSError: pass
print('patched OK, size %d -> %d bytes' % (len(orig), len(s)))
