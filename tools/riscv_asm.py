#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
riscv_asm.py - 自包含 RV32I 汇编器（教学/验证用）

功能：
  * 支持 RV32I 基础指令集全部指令（R/I/S/B/U/J 六种格式）
  * 支持标签（label:）、注释（# 或 //）
  * 支持常用伪指令：nop li mv not neg seqz snez sltz sgtz beqz bnez j ret call la
  * 支持 .word 数据指令（用于数据内存初始化或常量区）
  * 输出：
      - *.hex      ：指令内存加载文件（每行一个 32bit 字，8 位十六进制，小端字序按地址递增）
      - *.lst      ：带地址的反汇编清单（人工核对用）
      - *.data.hex ：.data 段（.word 在 .data 段内）输出，供数据内存初始化（可选）

用法：
  python riscv_asm.py input.s [output_dir]
  默认输出到 input.s 同目录下同名 .hex / .lst

说明：
  这是一个用于验证自研 CPU 的工具链组件；生产环境请使用 riscv-gcc + objcopy。
"""

import sys
import os
import re

# ---------------------------------------------------------------------------
# RV32I 指令编码表
# ---------------------------------------------------------------------------

OPCODE = {
    'R':    0x33,   # 0110011 寄存器-寄存器
    'I_ALU':0x13,   # 0010011 立即数算术/移位
    'LOAD': 0x03,   # 0000011 加载
    'STORE':0x23,   # 0100011 存储
    'BRANCH':0x63,  # 1100011 条件分支
    'LUI':  0x37,   # 0110111
    'AUIPC':0x17,   # 0010111
    'JAL':  0x6F,   # 1101111
    'JALR': 0x67,   # 1100111
    'FENCE':0x0F,   # 0001111
    'SYSTEM':0x73,  # 1110011 ecall/ebreak
}

# 寄存器名 -> 编号
REG = {}
for i in range(32):
    REG['x%d' % i] = i
aliases = {
    'zero':0, 'ra':1, 'sp':2, 'gp':3, 'tp':4,
    't0':5, 't1':6, 't2':7, 's0':8, 'fp':8, 's1':9,
    'a0':10, 'a1':11, 'a2':12, 'a3':13, 'a4':14, 'a5':15,
    'a6':16, 'a7':17, 's2':18, 's3':19, 's4':20, 's5':21,
    's6':22, 's7':23, 's8':24, 's9':25, 's10':26, 's11':27,
    't3':28, 't4':29, 't5':30, 't6':31,
}
for name, num in aliases.items():
    REG[name] = num

def reg_num(r):
    """寄存器名 -> 编号，非法时抛异常"""
    r = r.strip().lower()
    if r not in REG:
        raise ValueError('未知寄存器: %s' % r)
    return REG[r]

def imm_str(s):
    """立即数字符串 -> int（支持 0x、负号、十进制）"""
    s = s.strip()
    return int(s, 0) if s.lower().startswith(('0x', '-0x', '0b')) else int(s, 10)

# ---------------------------------------------------------------------------
# R 型指令：funct7, funct3, 助记符
# ---------------------------------------------------------------------------
R_TYPE = {
    'add':  (0x00, 0x0), 'sub':  (0x20, 0x0),
    'sll':  (0x00, 0x1), 'slt':  (0x00, 0x2), 'sltu': (0x00, 0x3),
    'xor':  (0x00, 0x4), 'srl':  (0x00, 0x5), 'sra':  (0x20, 0x5),
    'or':   (0x00, 0x6), 'and':  (0x00, 0x7),
}

# I 型 ALU 指令：funct3
I_ALU = {
    'addi': 0x0, 'slti': 0x2, 'sltiu': 0x3, 'xori': 0x4,
    'ori':  0x6, 'andi': 0x7,
    'slli': 0x1, 'srli': 0x5, 'srai': 0x5,
}

# 加载指令：funct3
LOADS = {'lb':0x0, 'lh':0x1, 'lw':0x2, 'lbu':0x4, 'lhu':0x5}

# 存储指令：funct3
STORES = {'sb':0x0, 'sh':0x1, 'sw':0x2}

# 分支指令：funct3
BRANCHES = {'beq':0x0, 'bne':0x1, 'blt':0x4, 'bge':0x5, 'bltu':0x6, 'bgeu':0x7}

# ---------------------------------------------------------------------------
# 汇编文本解析
# ---------------------------------------------------------------------------

def parse_lines(text):
    """
    解析汇编源码 -> 指令列表
    每条: dict(type, mnemonic, args, line_no)
    """
    instrs = []
    for lineno, raw in enumerate(text.splitlines(), 1):
        # 去掉注释
        code = re.split(r'[#;]', raw)[0]
        if '//' in code:
            code = code.split('//')[0]
        code = code.strip()
        if not code:
            continue
        # 标签行：xxx:
        m = re.match(r'^([A-Za-z_.$][\w.$]*):\s*(.*)$', code)
        if m:
            label = m.group(1)
            rest = m.group(2).strip()
            if rest:
                instrs.append({'type': 'instr', 'label': None, 'mnemonic': None,
                               'args': None, 'raw': rest, 'line': lineno,
                               'pending_label': label})
            else:
                instrs.append({'type': 'label', 'label': label, 'mnemonic': None,
                               'args': None, 'raw': '', 'line': lineno,
                               'pending_label': None})
            continue
        # 指令行
        parts = code.split(None, 1)
        mnemonic = parts[0].lower()
        args = []
        if len(parts) > 1:
            argstr = parts[1].strip()
            if argstr:
                # 按逗号分隔（注意括号内不含逗号，故直接 split 即可）
                args = [a.strip() for a in argstr.split(',')]
        instrs.append({'type': 'instr', 'label': None, 'mnemonic': mnemonic,
                       'args': args, 'raw': code, 'line': lineno,
                       'pending_label': None})
    return instrs

def parse_regmem(arg):
    """
    解析 [imm](reg) 形式的访存操作数
    返回 (reg, imm)
    """
    arg = arg.strip().lower()
    m = re.match(r'^([-+]?[\w.]+)\((\w+)\)$', arg)
    if m:
        imm = imm_str(m.group(1))
        reg = m.group(2)
        return reg, imm
    # 纯寄存器
    if arg in REG:
        return arg, 0
    raise ValueError('无法解析访存操作数: %s' % arg)

# ---------------------------------------------------------------------------
# 编码
# ---------------------------------------------------------------------------

def enc_r(rd, rs1, rs2, funct7, funct3):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | OPCODE['R']

def enc_i(opcode, rd, rs1, imm, funct3):
    imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def enc_s(rs1, rs2, imm, funct3):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | OPCODE['STORE']

def enc_b(rs1, rs2, off, funct3):
    off &= 0x1FFF  # 13 bit
    imm = ((off >> 12) & 0x1) << 31 | ((off >> 5) & 0x3F) << 25 | \
          ((off >> 1) & 0xF) << 8 | ((off >> 11) & 0x1) << 7
    return imm | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | OPCODE['BRANCH']

def enc_u(opcode, rd, imm):
    imm &= 0xFFFFF
    return (imm << 12) | (rd << 7) | opcode

def enc_j(rd, off):
    off &= 0x1FFFFF  # 21 bit
    imm = ((off >> 20) & 0x1) << 31 | ((off >> 1) & 0x3FF) << 21 | \
          ((off >> 11) & 0x1) << 20 | ((off >> 12) & 0xFF) << 12
    return imm | (rd << 7) | OPCODE['JAL']

def enc_jalr(rd, rs1, imm):
    return enc_i(OPCODE['JALR'], rd, rs1, imm, 0x0)

# ---------------------------------------------------------------------------
# 伪指令展开
# ---------------------------------------------------------------------------

def pseudo_expand(mnemonic, args, labels, pc, out):
    """
    处理伪指令；返回 True 表示已处理。
    out: 收集 (word, 描述) 的列表
    labels: 符号表（已解析完成的）
    pc: 当前指令地址（用于分支/跳转偏移计算）
    """
    def imm(rd, val):
        # li 展开
        v = val
        if -2048 <= v <= 2047:
            out.append((enc_i(OPCODE['I_ALU'], rd, 0, v, 0x0), 'addi %s,x0,%d' % (reg_name(rd), v)))
        else:
            upper = (v + 0x800) >> 12
            lower = v - (upper << 12)
            if lower == 0:
                out.append((enc_u(OPCODE['LUI'], rd, upper & 0xFFFFF), 'lui %s,0x%x' % (reg_name(rd), upper & 0xFFFFF)))
            else:
                out.append((enc_u(OPCODE['LUI'], rd, upper & 0xFFFFF), 'lui %s,0x%x' % (reg_name(rd), upper & 0xFFFFF)))
                out.append((enc_i(OPCODE['I_ALU'], rd, rd, lower, 0x0), 'addi %s,%s,%d' % (reg_name(rd), reg_name(rd), lower)))
        return True

    if mnemonic == 'nop':
        out.append((enc_i(OPCODE['I_ALU'], 0, 0, 0, 0x0), 'nop'))
        return True
    if mnemonic == 'li':
        rd = reg_num(args[0]); imm(rd, imm_str(args[1])); return True
    if mnemonic == 'mv':
        rd = reg_num(args[0]); rs = reg_num(args[1])
        out.append((enc_i(OPCODE['I_ALU'], rd, rs, 0, 0x0), 'mv %s,%s' % (reg_name(rd), reg_name(rs))))
        return True
    if mnemonic == 'not':
        rd = reg_num(args[0]); rs = reg_num(args[1])
        out.append((enc_i(OPCODE['I_ALU'], rd, rs, -1, 0x4), 'not %s,%s' % (reg_name(rd), reg_name(rs))))
        return True
    if mnemonic == 'neg':
        rd = reg_num(args[0]); rs = reg_num(args[1])
        out.append((enc_r(rd, 0, rs, 0x20, 0x0), 'neg %s,%s' % (reg_name(rd), reg_name(rs))))
        return True
    if mnemonic == 'seqz':
        rd = reg_num(args[0]); rs = reg_num(args[1])
        out.append((enc_i(OPCODE['I_ALU'], rd, rs, 1, 0x3), 'seqz %s,%s' % (reg_name(rd), reg_name(rs))))
        return True
    if mnemonic == 'snez':
        rd = reg_num(args[0]); rs = reg_num(args[1])
        out.append((enc_r(rd, rs, 0, 0x20, 0x0), 'snez %s,%s' % (reg_name(rd), reg_name(rs))))
        return True
    if mnemonic == 'sltz':
        rd = reg_num(args[0]); rs = reg_num(args[1])
        out.append((enc_i(OPCODE['I_ALU'], rd, rs, 0, 0x2), 'sltz %s,%s' % (reg_name(rd), reg_name(rs))))
        return True
    if mnemonic == 'sgtz':
        rd = reg_num(args[0]); rs = reg_num(args[1])
        out.append((enc_r(rd, 0, rs, 0x20, 0x2), 'sgtz %s,%s' % (reg_name(rd), reg_name(rs))))
        return True
    if mnemonic in ('beqz', 'bnez'):
        rs = reg_num(args[0]); target = args[1]
        off = labels[target] - pc
        if mnemonic == 'beqz':
            out.append((enc_b(rs, 0, off, 0x0), 'beqz %s,%s' % (reg_name(rs), target)))
        else:
            out.append((enc_b(rs, 0, off, 0x1), 'bnez %s,%s' % (reg_name(rs), target)))
        return True
    if mnemonic == 'j':
        target = args[0]
        off = labels[target] - pc
        out.append((enc_j(0, off), 'j %s' % target))
        return True
    if mnemonic == 'ret':
        out.append((enc_jalr(0, 1, 0), 'ret'))
        return True
    if mnemonic == 'call':
        target = args[0]
        off = labels[target] - pc
        # auipc ra, off[31:12] + jalr ra, ra, off[11:0]
        hi = (off + 0x800) >> 12
        lo = off - (hi << 12)
        out.append((enc_u(OPCODE['AUIPC'], 1, hi & 0xFFFFF), 'call: auipc ra,0x%x' % (hi & 0xFFFFF)))
        out.append((enc_jalr(1, 1, lo), 'call: jalr ra,ra,%d' % lo))
        return True
    if mnemonic == 'la':
        rd = reg_num(args[0]); target = args[1]
        off = labels[target] - pc
        hi = (off + 0x800) >> 12
        lo = off - (hi << 12)
        out.append((enc_u(OPCODE['AUIPC'], rd, hi & 0xFFFFF), 'la %s: auipc %s,0x%x' % (target, reg_name(rd), hi & 0xFFFFF)))
        out.append((enc_i(OPCODE['I_ALU'], rd, rd, lo, 0x0), 'la %s: addi %s,%s,%d' % (target, reg_name(rd), reg_name(rd), lo)))
        return True
    return False

def reg_name(num):
    for n, v in REG.items():
        if v == num:
            return n
    return 'x%d' % num

def instr_expand_count(m, args):
    """
    第一遍布局用：计算一条逻辑指令展开成几条 32bit 指令。
    li   : |imm|<=2047 -> 1，否则 2
    call/la : 2
    其余  : 1
    """
    if m == 'li':
        v = imm_str(args[1])
        return 2 if not (-2048 <= v <= 2047) else 1
    if m in ('call', 'la'):
        return 2
    return 1

# ---------------------------------------------------------------------------
# 两遍汇编
# ---------------------------------------------------------------------------

def assemble(text):
    """
    两遍汇编。
    返回: (instr_words, data_words, lst_lines)
      instr_words: [(addr, word, asm_desc)]
      data_words:  [(addr, word, asm_desc)]  # .data 段（.word）
    """
    instrs = parse_lines(text)

    # ---------- 第一遍：布局 + 收集标签 ----------
    labels = {}
    pc = 0
    data_pc = 0
    layout = []   # (kind, mnemonic, args, pc_or_none, line, label_attach)
    for it in instrs:
        if it['type'] == 'label':
            if it['label'] in labels:
                raise ValueError('重复标签: %s (line %d)' % (it['label'], it['line']))
            labels[it['label']] = pc
            continue
        if it['pending_label']:
            if it['pending_label'] in labels:
                raise ValueError('重复标签: %s (line %d)' % (it['pending_label'], it['line']))
            labels[it['pending_label']] = pc
        m = it['mnemonic']
        if m == '.word':
            layout.append(('data', m, it['args'], None, it['line']))
            data_pc += 4 * len(it['args'])
            continue
        if m in R_TYPE or m in I_ALU or m in LOADS or m in STORES or m in BRANCHES or \
           m in ('lui','auipc','jal','jalr','fence','ecall','ebreak') or \
           m in ('nop','li','mv','not','neg','seqz','snez','sltz','sgtz','beqz','bnez','j','ret','call','la'):
            layout.append(('instr', m, it['args'], pc, it['line']))
            pc += 4 * instr_expand_count(m, it['args'])
        else:
            raise ValueError('未知指令: %s (line %d)' % (m, it['line']))

    # 标签到 .data 的引用：为简单起见，.word 内的标签引用不支持（仅支持字面量）

    # ---------- 第二遍：编码 ----------
    instr_words = []
    data_words = []
    daddr = 0
    for kind, m, args, pc, line in layout:
        try:
            if kind == 'data':
                for a in args:
                    v = imm_str(a)  # .word 中允许负数和十六进制
                    data_words.append((daddr, v & 0xFFFFFFFF, '.word %s' % a))
                    daddr += 4
                continue

            out = []  # (word, desc)
            if m in R_TYPE:
                rd = reg_num(args[0]); rs1 = reg_num(args[1]); rs2 = reg_num(args[2])
                f7, f3 = R_TYPE[m]
                out.append((enc_r(rd, rs1, rs2, f7, f3), '%s %s,%s,%s' % (m, reg_name(rd), reg_name(rs1), reg_name(rs2))))
            elif m in I_ALU:
                rd = reg_num(args[0]); rs1 = reg_num(args[1]); im = imm_str(args[2])
                if m in ('slli','srli','srai'):
                    if not (0 <= im < 32):
                        raise ValueError('移位量必须 0-31: %d' % im)
                    f7 = 0x00 if m != 'srai' else 0x20
                    # 移位是 I 型：imm[11:0] 高 6 位为 funct7，低 5 位为移位量
                    word = (f7 << 25) | (im << 20) | (rs1 << 15) | (I_ALU[m] << 12) | (rd << 7) | OPCODE['I_ALU']
                    out.append((word, '%s %s,%s,%d' % (m, reg_name(rd), reg_name(rs1), im)))
                else:
                    out.append((enc_i(OPCODE['I_ALU'], rd, rs1, im, I_ALU[m]), '%s %s,%s,%d' % (m, reg_name(rd), reg_name(rs1), im)))
            elif m in LOADS:
                rd = reg_num(args[0]); rs1, im = parse_regmem(args[1])
                rs1 = reg_num(rs1)
                out.append((enc_i(OPCODE['LOAD'], rd, rs1, im, LOADS[m]), '%s %s,%d(%s)' % (m, reg_name(rd), im, rs1)))
            elif m in STORES:
                rs2 = reg_num(args[0]); rs1, im = parse_regmem(args[1])
                rs1 = reg_num(rs1)
                out.append((enc_s(rs1, rs2, im, STORES[m]), '%s %s,%d(%s)' % (m, reg_name(rs2), im, rs1)))
            elif m in BRANCHES:
                rs1 = reg_num(args[0]); rs2 = reg_num(args[1]); target = args[2]
                if target not in labels:
                    raise ValueError('未定义标签: %s' % target)
                off = labels[target] - pc
                if not (-4096 <= off < 4096) or off % 2 != 0:
                    raise ValueError('分支偏移越界或未对齐: %d' % off)
                out.append((enc_b(rs1, rs2, off, BRANCHES[m]), '%s %s,%s,%s' % (m, reg_name(rs1), reg_name(rs2), target)))
            elif m == 'lui':
                rd = reg_num(args[0]); im = imm_str(args[1])
                out.append((enc_u(OPCODE['LUI'], rd, im & 0xFFFFF), 'lui %s,0x%x' % (reg_name(rd), im & 0xFFFFF)))
            elif m == 'auipc':
                rd = reg_num(args[0]); im = imm_str(args[1])
                out.append((enc_u(OPCODE['AUIPC'], rd, im & 0xFFFFF), 'auipc %s,0x%x' % (reg_name(rd), im & 0xFFFFF)))
            elif m == 'jal':
                if args[0] in labels:
                    # jal label 等价于 jal ra, label
                    target = args[0]
                    off = labels[target] - pc
                    out.append((enc_j(1, off), 'jal %s' % target))
                else:
                    rd = reg_num(args[0]); target = args[1]
                    off = labels[target] - pc
                    out.append((enc_j(rd, off), 'jal %s,%s' % (reg_name(rd), target)))
            elif m == 'jalr':
                rd = reg_num(args[0]); rs1, im = parse_regmem(args[1])
                out.append((enc_jalr(rd, reg_num(rs1), im), 'jalr %s,%d(%s)' % (reg_name(rd), im, rs1)))
            elif m == 'fence':
                out.append((enc_i(OPCODE['FENCE'], 0, 0, 0, 0x0), 'fence'))
            elif m in ('ecall','ebreak'):
                out.append((enc_i(OPCODE['SYSTEM'], 0, 0, 1 if m == 'ebreak' else 0, 0x0), m))
            else:
                # 伪指令
                if pseudo_expand(m, args, labels, pc, out):
                    pass
                else:
                    raise ValueError('无法处理指令: %s' % m)
        except ValueError as e:
            raise ValueError('%s (line %d)' % (e, line))
        for w, desc in out:
            instr_words.append((pc, w & 0xFFFFFFFF, desc))
            pc += 4

    return instr_words, data_words, labels

# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

def write_outputs(src_path, out_dir=None, mem_base=0x00000000, imem_size=4096):
    with open(src_path, 'r', encoding='utf-8') as f:
        text = f.read()
    instr_words, data_words, labels = assemble(text)

    if out_dir is None:
        out_dir = os.path.dirname(src_path) or '.'
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.splitext(os.path.basename(src_path))[0]

    # hex：指令字（每行一个）
    hex_path = os.path.join(out_dir, base + '.hex')
    with open(hex_path, 'w', encoding='utf-8') as f:
        for addr, w, _ in instr_words:
            f.write('%08X\n' % w)
    # 若没有指令，写一个 nop 占位
    if not instr_words:
        with open(hex_path, 'w', encoding='utf-8') as f:
            f.write('00000013\n')

    # lst：清单
    lst_path = os.path.join(out_dir, base + '.lst')
    with open(lst_path, 'w', encoding='utf-8') as f:
        f.write('ADDR      MACHINE    ASM\n')
        for addr, w, desc in instr_words:
            f.write('%08X  %08X  %s\n' % (addr, w, desc))
        if data_words:
            f.write('\n; ---- data ----\n')
            for addr, w, desc in data_words:
                f.write('%08X  %08X  %s\n' % (addr, w, desc))

    # data hex（若有 .word）
    data_hex_path = os.path.join(out_dir, base + '.data.hex')
    if data_words:
        with open(data_hex_path, 'w', encoding='utf-8') as f:
            for _, w, _ in data_words:
                f.write('%08X\n' % w)
    else:
        if os.path.exists(data_hex_path):
            os.remove(data_hex_path)

    print('ok: %d instructions, %d data words' % (len(instr_words), len(data_words)))
    print('  hex: %s' % hex_path)
    print('  lst: %s' % lst_path)
    if data_words:
        print('  data: %s' % data_hex_path)
    return hex_path, lst_path

# ---------------------------------------------------------------------------

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('usage: python riscv_asm.py <input.s> [output_dir]')
        sys.exit(1)
    src = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else None
    write_outputs(src, out_dir)
