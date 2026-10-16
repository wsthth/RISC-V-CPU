import re

txt = open(r'D:\my_project\RISC-V\sim\work\tb_pipe_debug\waves.vcd', 'r', encoding='utf-8', errors='ignore').read()
pat = re.compile(r'\$var (?:wire|reg|integer) (\d+) ([!-~]+) (\\[^ ]+|[!-~]+)(?: \[[0-9:]+\])? \$end')
ids = {m.group(2): m.group(3).replace('\\', '') for m in pat.finditer(txt)}
targets = {c: n for c, n in ids.items() if n.endswith('pc_id') or n.endswith('instr_id') or n.endswith('valid_id') or n.endswith('pc_f2') or n.endswith('valid_f2')}

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
        if c in targets:
            ev.append((t, c, b2i(p[0])))
    elif len(line) > 1 and line[0] in '01':
        c = line[1:]
        if c in targets:
            ev.append((t, c, line[0]))

prev = {}
for t, c, v in ev:
    if 0 <= t <= 360000:
        n = targets[c]
        if prev.get(n) != v:
            prev[n] = v
            s = v if not isinstance(v, int) else format(v, '08X')
            print(f'{t/1000:6.1f}ns {n:10s}={s}')
