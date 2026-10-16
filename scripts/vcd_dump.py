import re

txt = open(r'D:\my_project\RISC-V\sim\work\tb_pipe_debug\waves.vcd', 'r', encoding='utf-8', errors='ignore').read()

ids = {}
pat = re.compile(r'\$var (?:wire|reg|integer) (\d+) ([!-~]+) (\\[^ ]+|[!-~]+)(?: \[[0-9:]+\])? \$end')
for m in pat.finditer(txt):
    size, code, name = m.group(1), m.group(2), m.group(3)
    ids[code] = name

names = ['pcf', 'pc_f2', 'valid_f2', 'stallf', 'flushe', 'memread_e', 'valid_e',
         'rd_e', 'rs1_d', 'rs2_d', 'resultsrc_e', 'resultsrc_m', 'alu_result_m',
         'readdata_m', 'pcplus4_f', 'mispredict', 'rd_word0']
code2n = {}
for code, name in ids.items():
    for n in names:
        if name.endswith('\\' + n) or name == n or ('dut.' + n) in name:
            code2n[code] = n
            break

# 解析值变化
vals = {c: None for c in code2n}
t = 0
events = []
for line in txt.splitlines():
    line = line.strip()
    if line.startswith('#'):
        t = int(line[1:])
    elif line.startswith('0') or line.startswith('1'):
        c = line[1:]
        if c in code2n:
            vals[c] = line[0]
            events.append((t, c, line[0]))
    elif line.startswith('b') or line.startswith('B'):
        parts = line[1:].split()
        c = parts[-1]
        if c in code2n:
            vals[c] = parts[0]
            events.append((t, c, parts[0]))
    elif line.startswith('x') or line.startswith('X') or line.startswith('z') or line.startswith('Z'):
        c = line[1:]
        if c in code2n:
            vals[c] = line[0]
            events.append((t, c, line[0]))

# 打印 140ns-260ns 区间，按时间分组
def b2i(b):
    if not b: return None
    b = b.strip()
    if any(ch not in '01xXzZ' for ch in b): return b
    if 'x' in b.lower() or 'z' in b.lower(): return b
    return int(b, 2)

prev = {}
rows = {}
for t, c, v in events:
    if 95000 <= t <= 160000:
        rows.setdefault(t, {})[code2n[c]] = b2i(v)

def fmt(k, v):
    if v is None: return '?'
    if k in ('pcf','pc_f2','alu_result_m','readdata_m','pcplus4_f'):
        return f'{v:08X}' if isinstance(v,int) else str(v)
    if k in ('rd_e','rs1_d','rs2_d'):
        return f'{v:02d}' if isinstance(v,int) else str(v)
    return str(v)

ts = sorted(rows)
for i in range(1, len(ts)):
    t0, t1 = ts[i-1], ts[i]
    d = rows[t0]
    line = f'[{t0//1000:6d} ns] '
    for n in names:
        line += f'{n}={fmt(n, d.get(n))} '
    print(line)
