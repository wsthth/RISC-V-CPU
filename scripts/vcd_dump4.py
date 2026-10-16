import re

txt = open(r'D:\my_project\RISC-V\sim\work\tb_pipe_debug\waves.vcd', 'r', encoding='utf-8', errors='ignore').read()

ids = {}
pat = re.compile(r'\$var (?:wire|reg|integer) (\d+) ([!-~]+) (\\[^ ]+|[!-~]+)(?: \[[0-9:]+\])? \$end')
for m in pat.finditer(txt):
    ids[m.group(2)] = m.group(3).replace('\\', '')

names = ['instr_id', 'pc_id', 'instr_e', 'pc_e', 'pc_f2', 'instr_f', 'pcf']
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

prev = {}
for t, c, v in ev:
    if 300000 <= t <= 400000:
        n = code2n[c]
        if prev.get(n) != v:
            prev[n] = v
            if n in ('instr_id', 'pc_id', 'instr_e', 'pc_e', 'pc_f2', 'instr_f', 'pcf'):
                s = v if not isinstance(v, int) else format(v, '08X')
                print(f'{t/1000:7.1f}ns {n:10s} = {s}')
