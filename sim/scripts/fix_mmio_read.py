# -*- coding: utf-8 -*-
"""修正 mmio_read_m：memread_m -> resultsrc_m[0] & valid_m（MEM 段无 memread 信号）。"""
path = r'D:\my_project\RISC-V\rtl\pipeline\riscv_pipeline.v'
data = open(path, 'rb').read()
old = b"    wire mmio_read_m = memread_m & valid_m & (alu_result_m == 32'hF0000004);"
new = b"    wire mmio_read_m = resultsrc_m[0] & valid_m & (alu_result_m == 32'hF0000004);"
assert data.count(old) == 1, 'mmio_read not found: %d' % data.count(old)
data = data.replace(old, new, 1)
open(path, 'wb').write(data)
print('OK')
