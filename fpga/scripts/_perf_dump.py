# -*- coding: utf-8 -*-
import io
p = r'D:\my_project\RISC-V\sim\work\coremark_v15_btb128.log'
d = io.open(p, encoding='utf-8', errors='replace').read()
for x in d.split(chr(10)):
    if 'PERF:' in x or 'MISP:' in x or 'PASS:' in x:
        print(x)
