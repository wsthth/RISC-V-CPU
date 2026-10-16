import re

txt = open(r'D:\my_project\RISC-V\sim\work\tb_pipe_debug\waves.vcd', 'r', encoding='utf-8', errors='ignore').read()

ids = {}
pat = re.compile(r'\$var (?:wire|reg|integer) (\d+) ([!-~]+) (\\[^ ]+|[!-~]+)(?: \[[0-9:]+\])? \$end')
for m in pat.finditer(txt):
    ids[m.group(2)] = m.group(3).replace('\\', '')

names = ['pc_e', 'instr_id', 'pc_id', 'rd_m', 'rd_w', 'regwrite_m', 'regwrite_w',
         'alu_result_m', 'mem_result_m', 'wb_result_w', 'alu_result_w',
         'resultsrc_m', 'resultsrc_w', 'forwardae', 'forwardbe', 'rs1_e', 'rs2_e',
         'srca', 'alu_srca', 'readdata_m', 'readdata_w', 'valid_e', 'valid_m']
code2n = {}
for c, n in ids.items():
    for t in names:
        if n.endswith(t):
            code2n[c] = t
            break

def b2i(b):
    b = b.strip()
    if not b or any(ch in 'xXzZ' for ch in b):
        return b
    return int(b, 2)

ev = []
for line in txt.splitlines():
    line = line.strip()
    if line.startswith('#'):
        t = int(line[1:])
    elif line.startswith('b') or line.startswith('B'):
        p = line[1:].split()
        c = p[-1]
        if c in code2n:
            ev.append((t, c, b2i(p[0])))
    elif len(line) > 1 and line[0] in '01':
        c = line[1:]
        if c in code2n:
            ev.append((t, c, line[0]))

def fmt(n, v):
    if v is None:
        return '?'
    if n in ('pc_e', 'instr_id', 'pc_id', 'alu_result_m', 'mem_result_m',
             'wb_result_w', 'alu_result_w', 'readdata_m', 'readdata_w'):
        return format(v, '08X') if isinstance(v, int) else str(v)
    if n in ('rd_m', 'rd_w', 'rs1_e', 'rs2_e'):
        return format(v, '02X') if isinstance(v, int) else str(v)
    return str(v)

prev = {}
rows = {}
for t, c, v in ev:
    if 340000 <= t <= 400000:
        n = code2n[c]
        rows.setdefault(t, {})[n] = v
        prev[n] = v

ts = sorted(rows)
for i in range(1, len(ts)):
    t0, t1 = ts[i-1], ts[i]
    d = rows[t0]
    line = f'[{t0/1000:7.1f}ns] '
    for n in names:
        if n in d:
            line += f' {n}={fmt(n, d[n])}'
    print(line)
