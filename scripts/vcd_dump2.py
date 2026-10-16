import re

txt = open(r'D:\my_project\RISC-V\sim\work\tb_pipe_debug\waves.vcd', 'r', encoding='utf-8', errors='ignore').read()

ids = {}
pat = re.compile(r'\$var (?:wire|reg|integer) (\d+) ([!-~]+) (\\[^ ]+|[!-~]+)(?: \[[0-9:]+\])? \$end')
for m in pat.finditer(txt):
    size, code, name = m.group(1), m.group(2), m.group(3)
    ids[code] = name

names = ['pcf', 'pcf_next', 'pc_f2', 'valid_f2', 'stallf', 'flushe', 'memread_e', 'valid_e',
         'rd_e', 'rs1_d', 'rs2_d', 'resultsrc_e', 'resultsrc_m', 'alu_result_m',
         'readdata_m', 'pcplus4_f', 'mispredict', 'rd_word0', 'pc_e', 'instr_e',
         'imem_i.a', 'imem_i.rd', 'pcplus4_e', 'branch_taken_e']
code2n = {}
for code, name in ids.items():
    for n in names:
        nm = name.replace('\\', '')
        if nm.endswith(n) or n.startswith('imem') and n in nm:
            code2n[code] = n
            break

def b2i(b):
    b = b.strip()
    if not b or any(ch in 'xXzZ' for ch in b): return b
    return int(b, 2)

# 值变化事件
events = []
vals = {c: None for c in code2n}
for line in txt.splitlines():
    line = line.strip()
    if line.startswith('#'):
        t = int(line[1:])
    elif line.startswith('b') or line.startswith('B'):
        parts = line[1:].split()
        c = parts[-1]
        if c in code2n:
            events.append((t, c, parts[0]))
    elif (line.startswith('0') or line.startswith('1')) and len(line) > 1:
        c = line[1:]
        if c in code2n:
            events.append((t, c, line[0]))
    elif line.startswith('x') or line.startswith('z'):
        c = line[1:]
        if c in code2n:
            events.append((t, c, line[0]))

def fmt(k, v):
    if v is None: return '?'
    if k in ('pcf','pcf_next','pc_f2','alu_result_m','readdata_m','pcplus4_f','pc_e','pcplus4_e','imem_i.a','imem_i.rd'):
        return f'{v:08X}' if isinstance(v,int) else str(v)
    if k in ('rd_e','rs1_d','rs2_d'):
        return f'{v:02d}' if isinstance(v,int) else str(v)
    return str(v)

prev = {}
for t, c, v in events:
    if 105000 <= t <= 150000:
        n = code2n[c]
        val = b2i(v)
        if prev.get(n) != val:
            prev[n] = val
            print(f'{t/1000:7.1f}ns  {n:16s} = {fmt(n, val)}')
