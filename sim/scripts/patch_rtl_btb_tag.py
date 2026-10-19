# -*- coding: utf-8 -*-
# patch_rtl_btb_tag.py - v0.10 BTB tag 修复（治本：消除别名污染）
# 根因：BTB 用 PC[8:2] 做 128 项索引，无 tag。coremark .text 3.3KB，
#   0x554(core_bench_list 的 lw a5,0(a5)) 与 0x1d54(core_init_state 的 bne)
#   共享 index 0x55 -> 0x554 被预测 taken 且目标=0x1d44 ->
#   (a) 0x554 在 EX 段 valid=1 时触发 pred_taken_nonbranch 刷新(性能损失)；
#   (b) 0x554 被 flush 误杀成 bubble(valid=0) 时 mispredict 不触发(要求 valid_e)，
#       IF 段仍按污染预测预取 0x1d44 -> core_init_state 指令被执行 ->
#       addi a5,a5,1 把 a5 改成 0xFC000069 -> 链表指针越界 -> X -> PC=X@40383。
# 修复：BTB 每项增加 23-bit tag(PC[31:9])，查询时 tag 必须匹配才预测 taken。
#   0x554 tag=0x00，0x1d54 tag=0x0E -> 不再冲突。
# 安全：文件为 GBK，bytes 级匹配纯 ASCII 片段(不触碰中文注释)，断言命中+原子写回。
import io, os, tempfile

p = r'D:\my_project\RISC-V\rtl\pipeline\branch_predictor.v'
b = io.open(p, 'rb').read()
orig = b
EOL = b'\r\n' if b'\r\n' in b else b'\n'

def repl(old, new, tag):
    global b
    n = b.count(old)
    assert n == 1, '[%s] match %d != 1: %r' % (tag, n, old[:100])
    b = b.replace(old, new)
    print('[%s] OK' % tag)

# A. 声明 tag 数组
repl(b'    reg [1:0]   counter [0:N-1];' + EOL +
     b'    reg         valid   [0:N-1];' + EOL +
     b'    reg [31:0]  btb     [0:N-1];',
     b'    reg [1:0]   counter [0:N-1];' + EOL +
     b'    reg         valid   [0:N-1];' + EOL +
     b'    reg [31:0]  btb     [0:N-1];' + EOL +
     b'    reg [22:0]  tag     [0:N-1];   // v0.10: PC[31:9] tag, fix alias pollution',
     'A-decl')

# B. 查询时 tag 匹配
repl(b'    assign pred_taken  = valid[idx_f] & counter[idx_f][1];',
     b'    assign pred_taken  = valid[idx_f] & (tag[idx_f] == pcf[31:9]) & counter[idx_f][1];',
     'B-query')

# C. reset 清 tag
repl(b'                btb[i]     <= 32\'b0;',
     b'                btb[i]     <= 32\'b0;' + EOL +
     b'                tag[i]     <= 23\'b0;',
     'C-reset')

# D. 更新写 tag
repl(b'                btb[idx_e]     <= branch_target;',
     b'                btb[idx_e]     <= branch_target;' + EOL +
     b'                tag[idx_e]     <= branch_pc[31:9];',
     'D-update')

assert b != orig, 'no change'
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p), suffix='.tmp')
try:
    with os.fdopen(fd, 'wb') as f:
        f.write(b)
    os.replace(tmp, p)
finally:
    if os.path.exists(tmp):
        try: os.remove(tmp)
        except OSError: pass
print('patched OK, size %d -> %d bytes' % (len(orig), len(b)))
