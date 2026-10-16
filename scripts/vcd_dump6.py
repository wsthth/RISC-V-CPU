import re

txt = open(r'D:\my_project\RISC-V\sim\work\tb_pipe_debug\waves.vcd', 'r', encoding='utf-8', errors='ignore').read()

ids = {}
pat = re.compile(r'\$var (?:wire|reg|integer) (\d+) ([!-~]+) (\\[^ ]+|[!-~]+)(?: \[[0-9:]+\])? \$end')
for m in pat.finditer(txt):
    ids[m.group(2)] = m.group(3).replace('\\', '')

names = ['mispredict', 'valid_id', 'valid_f2', 'valid_e', 'pc_id', 'pc_f2', 'pcf',
         'stallf', 'stalld', 'flushe', 'instr_id', 'instr_f', 'pc_e', 'pred_e',
         'branch_taken_e', 'branch_e', 'jump_e', 'pred_taken_f', 'pred_target_f']
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
    if n in ('pc_id', 'pc_f2', 'pcf', 'instr_id', 'instr_f', 'pc_e', 'pred_target_f'):
        return format(v, '08X') if isinstance(v, int) else str(v)
    return str(v)

prev = {}
rows = {}
for t, c, v in ev:
    if 120000 <= t <= 360000:
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
