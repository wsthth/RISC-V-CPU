# -*- coding: utf-8 -*-
import io, re
p = r'D:\my_project\RISC-V\sim\work\coremark_v15_btb128.log'
d = io.open(p, encoding='utf-8', errors='replace').read()
# collect UART lines in order
lines = [x for x in d.split(chr(10)) if 'UART:' in x]
print('total UART lines:', len(lines))
# strip the "UART:" prefix and time prefix
out = ''
for x in lines:
    m = re.search(r'UART:(.)', x)
    if m:
        out += m.group(1)
print('---- decoded UART stream (first 2000 chars) ----')
print(out[:2000])
print('---- tail ----')
print(out[-600:])
