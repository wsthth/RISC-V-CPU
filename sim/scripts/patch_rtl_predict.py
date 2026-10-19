# -*- coding: utf-8 -*-
# patch_rtl_predict.py - 重建 PREDICT 参数（v0.8）
# 背景：riscv_pipeline.v 曾被 0 字节截断，git 恢复后丢失了工作区未提交的 PREDICT 参数
#       （git 全历史无此参数）。tb_coremark 在 PREDICT_OFF 下用 #(.PREDICT(0)) 例化。
# 语义：PREDICT=0 时 pred_taken_eff=0/pred_target_eff=0 -> pred_f2/pred_e 链路全 0
#       -> mispredict 仅在真实 taken 分支时触发，等价顺序执行（历史 PREDICT_OFF 行为）。
# 实现：参数三目掩蔽（常数折叠），不条件例化 branch_predictor，最小侵入、可综合。
import io
import os
import tempfile

p = r'D:\my_project\RISC-V\rtl\pipeline\riscv_pipeline.v'
s = io.open(p, 'rb').read().decode('utf-8')
n = s.count(b'\r\n'.decode()) if False else 0

# 1) 模块头加 PREDICT 参数
old1 = 'module riscv_pipeline #(parameter DEPTH = 8192) ('
new1 = 'module riscv_pipeline #(parameter DEPTH = 8192, parameter PREDICT = 1) ('
assert s.count(old1) == 1, 'module head: %d' % s.count(old1)
s = s.replace(old1, new1, 1)

# 2) pred_taken_f/pred_target_f 声明后插入 eff 掩蔽信号
old2 = '    wire        pred_taken_f;\r\n    wire [31:0] pred_target_f;'
new2 = ('    wire        pred_taken_f;\r\n'
        '    wire [31:0] pred_target_f;\r\n'
        '    // PREDICT 参数开关（v0.8 重建）：=0 时强制关预测，供 CoreMark 仿真调试\r\n'
        '    wire        pred_taken_eff  = PREDICT ? pred_taken_f  : 1\'b0;\r\n'
        '    wire [31:0] pred_target_eff = PREDICT ? pred_target_f : 32\'b0;')
assert s.count(old2) == 1, 'decl block: %d' % s.count(old2)
s = s.replace(old2, new2, 1)

# 3) a_comb 预测目标用 eff
old3 = '                         (pred_taken_f ? pred_target_f : pcf);'
new3 = '                         (pred_taken_eff ? pred_target_eff : pcf);'
assert s.count(old3) == 1, 'a_comb: %d' % s.count(old3)
s = s.replace(old3, new3, 1)

# 4) reg_ifid pred_f2 两处（mispredict 分支 / 正常分支）用 eff
old4 = '            pred_f2   <= pred_taken_f;'
new4 = '            pred_f2   <= pred_taken_eff;'
assert s.count(old4) == 2, 'pred_f2 expect 2: %d' % s.count(old4)
s = s.replace(old4, new4)

# 5) pcf_next 预测路径用 eff
old5 = '                      (pred_taken_f & ~stallf) ? pred_target_f :'
new5 = '                      (pred_taken_eff & ~stallf) ? pred_target_eff :'
assert s.count(old5) == 1, 'pcf_next: %d' % s.count(old5)
s = s.replace(old5, new5, 1)

# 安全写入
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p), suffix='.tmp')
try:
    with os.fdopen(fd, 'wb') as f:
        f.write(s.encode('utf-8'))
    os.replace(tmp, p)
except Exception:
    if os.path.exists(tmp):
        os.remove(tmp)
    raise
print('patched OK, bytes=', len(s.encode('utf-8')))
