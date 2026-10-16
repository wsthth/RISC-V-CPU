import re

txt = open(r'D:\my_project\RISC-V\sim\work\tb_pipe_debug\waves.vcd', 'r', encoding='utf-8', errors='ignore').read()
pat = re.compile(r'\$var (?:wire|reg|integer) (\d+) ([!-~]+) (\\[^ ]+|[!-~]+)(?: \[[0-9:]+\])? \$end')
ids = {m.group(2): m.group(3).replace('\\', '') for m in pat.finditer(txt)}
targets = {c: n for c, n in ids.items() if n in ('pc_id', 'instr_id')}
print('targets:', targets)

cnt = 0
for line in txt.splitlines():
    line = line.strip()
    if line.startswith('b') or line.startswith('B'):
        p = line[1:].split()
        c = p[-1]
        if c in targets and cnt < 40:
            print(f'{targets[c]}: {p[0][:64]}')
            cnt += 1
