# -*- coding: utf-8 -*-
import io, os
r = r'D:\my_project\RISC-V\fpga\vivado_ac7021b\riscv_ac7021b.runs\impl_1'
for f in ('runme.log', 'vivado.jou'):
    fp = os.path.join(r, f)
    if os.path.exists(fp):
        sz = os.path.getsize(fp)
        print('===', f, sz)
        if sz > 0:
            dd = io.open(fp, encoding='utf-8', errors='replace').read()
            for x in dd.split(chr(10))[-25:]:
                print(x[:150])
