import re

txt = open(r'D:\my_project\RISC-V\sim\work\tb_pipe_debug\waves.vcd', 'r', encoding='utf-8', errors='ignore').read()

ids = {}
pat = re.compile(r'\$var (?:wire|reg|integer) (\d+) ([!-~]+) (\\[^ ]+|[!-~]+)(?: \[[0-9:]+\])? \$end')
for m in pat.finditer(txt):
    size, code, name = m.group(1), m.group(2), m.group(3)
    ids[code] = name

names = ['pcf', 'pc_f2', 'valid_f2', 'stallf', 'flushe', 'memread_e', 'pc_e', 'valid_e',
         'instr_f', 'rd_e', 'rs1_d', 'rs2_d', 'resultsrc_e', 'alu_result_e', 'funct3_m',
         'readdata_m', 'pcplus4_f', 'pred_taken_f', 'branch_taken_e', 'mispredict',
         'rd_f3_r', 'rd_off_r', 'rd_word0', 'alu_result_m', 'resultsrc_m']
want = {}
for code, name in ids.items():
    for n in names:
        if name.endswith('\\' + n) or name == n or ('dut.' + n) in name:
            want[code] = (n, name)
            break
print(len(want), 'matched')
for k, v in sorted(want.items(), key=lambda x: x[1][0]):
    print(k, v[0], '|', v[1])
