# -*- coding: utf-8 -*-
import io, shutil
p = r'D:\my_project\RISC-V\fpga\constraints\ac7021b.xdc'
shutil.copy(p, p + '.50mhz.bak')
d = io.open(p, encoding='utf-8', errors='replace').read()
assert 'create_clock -period 20.000' in d
d = d.replace('create_clock -period 20.000 -name clk [get_ports clk]',
              'create_clock -period 10.000 -name clk [get_ports clk]   # v0.15.3: 100MHz 收紧验证上板主频上限')
io.open(p, 'w', encoding='utf-8', newline='\n').write(d)
print('xdc updated to 100MHz, backup saved')
