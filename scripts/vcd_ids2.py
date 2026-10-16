import re

txt = open(r'D:\my_project\RISC-V\sim\work\tb_pipe_debug\waves.vcd', 'r', encoding='utf-8', errors='ignore').read()
pat = re.compile(r'\$var (?:wire|reg|integer) (\d+) ([!-~]+) (\\[^ ]+|[!-~]+)(?: \[[0-9:]+\])? \$end')
for m in pat.finditer(txt):
    n = m.group(3).replace('\\', '')
    if any(k in n for k in ['pc_id', 'instr_id', 'pc_f2', 'valid_id', 'stallf', 'stalld', 'valid_f2']):
        print(m.group(2), n)
