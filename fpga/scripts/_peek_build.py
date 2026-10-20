# -*- coding: utf-8 -*-
import io, os
p = r'D:\my_project\RISC-V\fpga\scripts\build_ac7021b_v15c.log'
if os.path.exists(p):
    d = io.open(p, encoding='utf-8', errors='replace').read()
    print('log size:', len(d))
    for x in d.split(chr(10)):
        t = x.strip()
        if ('BUILD OK' in t or 'Bitstream' in t or 'Slice LUT' in t or 'ERROR' in t
                or 'WNS' in t or 'Congestion' in t or 'Phase 4' in t):
            print('>>', t[:160])
    b = r'D:\my_project\RISC-V\fpga\vivado_ac7021b\riscv_ac7021b.runs\impl_1\fpga_top_ac7021b.bit'
    print('bit:', os.path.exists(b), os.path.getsize(b) if os.path.exists(b) else 0)
else:
    print('log not ready')
