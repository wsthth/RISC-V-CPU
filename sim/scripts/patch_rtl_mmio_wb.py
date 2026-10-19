# -*- coding: utf-8 -*-
# patch_rtl_mmio_wb.py - 修复 MMIO 读在 WB 段的直通缺陷（LOCK_READDATA=0）
# 根因：reg_memwb 的 readdata 直通组合，普通 dmem load 靠 dmem 同步读滞后 1 拍碰巧正确；
#       MMIO(cycle_cnt) 在 lw 的 WB 段时 MEM 段已换指令 -> readdata_w 落到 readdata_dmem(越界 X)。
# 修复：WB 段按 lw 特征(resultsrc_w[0]&valid_w&alu_result_w==0xF0000004)重选 cycle_cnt，
#       转发路径 wb_result_w 与 muxwb.d1 均改用 readdata_final。
# 安全写入：全部 replace 成功后才写临时文件 + os.replace 原子替换。
import io
import os
import tempfile

p = r'D:\my_project\RISC-V\rtl\pipeline\riscv_pipeline.v'
s = io.open(p, 'rb').read().decode('utf-8')

# 1) 258 行原 wb_result_w assign 注释掉（移到 readdata_final 定义后）
old1 = '    assign wb_result_w  = resultsrc_w[0] ? readdata_w : alu_result_w;'
new1 = '    // assign wb_result_w  = resultsrc_w[0] ? readdata_w : alu_result_w;  // (v0.8) 移至 WB 段 readdata_final'
assert old1 in s, 'old1 not found'
s = s.replace(old1, new1, 1)

# 2) readdata_m 定义后插入 MMIO WB 段选择 + wb_result_w 重新定义
old2 = '    assign readdata_m = mmio_read_m ? cycle_cnt : readdata_dmem;'
new2 = '''    assign readdata_m = mmio_read_m ? cycle_cnt : readdata_dmem;
    // MMIO 读数据在 WB 段选择（v0.8 修复）：
    // LOCK_READDATA=0 直通下 readdata_w 随 MEM 段漂移；普通 dmem load 靠 dmem 同步读
    // 滞后 1 拍碰巧正确，MMIO(cycle_cnt) 则在 WB 段失效落到 readdata_dmem(越界 X)。
    // 故按 lw 特征(resultsrc_w[0]&valid_w&alu_result_w==F0000004)在 WB 段重选 cycle_cnt。
    wire mmio_read_w = resultsrc_w[0] & valid_w & (alu_result_w == 32'hF0000004);
    wire [31:0] readdata_final = mmio_read_w ? cycle_cnt : readdata_w;
    assign wb_result_w = resultsrc_w[0] ? readdata_final : alu_result_w;'''
assert old2 in s, 'old2 not found'
s = s.replace(old2, new2, 1)

# 3) muxwb.d1 改用 readdata_final
old3 = 'mux4 #(.W(32)) muxwb (.d0(alu_result_w), .d1(readdata_w), .d2(pcplus4_w),'
new3 = 'mux4 #(.W(32)) muxwb (.d0(alu_result_w), .d1(readdata_final), .d2(pcplus4_w),'
assert old3 in s, 'old3 not found'
s = s.replace(old3, new3, 1)

# 安全写入：temp + os.replace
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
