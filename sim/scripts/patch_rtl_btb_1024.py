# -*- coding: utf-8 -*-
# patch_rtl_btb_1024.py - v0.11 BTB 扩容 1024 项 + 索引/标签位宽调整
# 性能剖析(pred6 PERF): inst=778519 cycles=1522013 IPC=0.511, misp=183857/br=236368(78%!)
#   根因: BTB 128 项(PC[8:2] 索引)装不下 coremark 200+ 个分支 -> 互相驱逐 ->
#   循环分支反复冷 miss -> 每次 taken 分支都 mispredict(2 拍惩罚) -> IPC 0.511。
#   且 0x554(core_bench_list) 与 0x1d54(core_init_state) 低 11 位相同(0x554),
#   512 项(PC[10:2])仍冲突, 必须 1024 项(PC[11:2] 10-bit 索引)才分开。
# 修改: N=128->1024, idx=pcf[11:2](10b), tag=pcf[31:12](20b); 其余逻辑不变。
# 安全: GBK 文件 bytes/ASCII 原子写, 断言命中。
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

# A. N 参数
repl(b'    localparam N = 128;',
     b'    localparam N = 1024;   // v0.11: 128->1024, PC[11:2] idx eliminate alias eviction',
     'A-N')

# B. tag 位宽 23->20 (PC[31:12])
repl(b'    reg [22:0]  tag     [0:N-1];   // v0.10: PC[31:9] tag, fix alias pollution',
     b'    reg [19:0]  tag     [0:N-1];   // v0.11: PC[31:12] tag (1024-entry, PC[11:2] idx)',
     'B-tagw')

# C. 索引位宽与取值
repl(b'    wire [6:0] idx_f = pcf[8:2];' + EOL +
     b'    wire [6:0] idx_e = branch_pc[8:2];',
     b'    wire [9:0] idx_f = pcf[11:2];' + EOL +
     b'    wire [9:0] idx_e = branch_pc[11:2];',
     'C-idx')

# D. 查询 tag 比较位宽
repl(b'    assign pred_taken  = valid[idx_f] & (tag[idx_f] == pcf[31:9]) & counter[idx_f][1];',
     b'    assign pred_taken  = valid[idx_f] & (tag[idx_f] == pcf[31:12]) & counter[idx_f][1];',
     'D-query')

# E. reset tag 位宽
repl(b'                tag[i]     <= 23\'b0;',
     b'                tag[i]     <= 20\'b0;',
     'E-reset')

# F. 更新 tag 位宽
repl(b'                tag[idx_e]     <= branch_pc[31:9];',
     b'                tag[idx_e]     <= branch_pc[31:12];',
     'F-update')

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
