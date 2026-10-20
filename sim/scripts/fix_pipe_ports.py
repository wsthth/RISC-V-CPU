# -*- coding: utf-8 -*-
# 修复 pipe_regs.v 端口误插：reg_ifid 出现两个 pred_target 输出，reg_idex 缺 pred_target 输出
import io, sys
p = r'D:\my_project\RISC-V\rtl\pipeline\pipe_regs.v'
data = io.open(p, 'rb').read()
eol = b'\r\n' if b'\r\n' in data else b'\n'
def rep(old, new, need=1):
    global data
    ob = old.replace('\n', eol.decode()).encode('ascii')
    nb = new.replace('\n', eol.decode()).encode('ascii')
    c = data.count(ob)
    if c < need:
        print('FAIL', old[:60], c); sys.exit(1)
    data = data.replace(ob, nb, need)

# 1) reg_ifid：去掉误插在 pred 与 valid 之间的 pred_target
rep("    output reg        pred,\n    output reg [31:0] pred_target,\n    output reg        valid,\n    output reg [31:0] pred_target\n);",
    "    output reg        pred,\n    output reg        valid,\n    output reg [31:0] pred_target\n);")
# 2) reg_idex：在 pred 与 valid 之间补 pred_target（此时首次出现即 reg_idex）
rep("    output reg        pred,\n    output reg        valid\n);",
    "    output reg        pred,\n    output reg [31:0] pred_target,\n    output reg        valid\n);")
io.open(p, 'wb').write(data)
print('FIXED pipe_regs.v ports')
