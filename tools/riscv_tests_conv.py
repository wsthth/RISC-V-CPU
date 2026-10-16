# -*- coding: utf-8 -*-
# ============================================================================
# riscv_tests_conv.py —— riscv-tests 官方测试集翻译器
# ----------------------------------------------------------------------------
# 把 riscv-tests 的 rv32ui-p-* 测试（C 预处理器 + 宏）翻译成本项目汇编器
# (riscv_asm.py) 能直接汇编的纯汇编文本。
#
# 功能：
#   1. 处理 #include（riscv_test.h -> tools/riscv_test_self.h；test_macros.h ->
#      仓库 isa/macros/scalar/test_macros.h；rv32ui/x.S -> rv64ui/x.S）
#   2. C 预处理器：注释、续行、#undef/#define（对象宏 + 函数宏 + 变参 + ## 拼接）
#   3. 宏调用迭代展开；MASK_XLEN / SEXT_IMM 数值计算（__riscv_xlen=32）
#   4. 输出 .s 文本（无 C 语法残留）
#
# 用法：
#   python riscv_tests_conv.py <rv32ui测试.S路径> [输出目录]
#   （输出 <name>.s 到输出目录，再由 riscv_asm.py 汇编）
# ============================================================================

import os
import re
import sys

TESTS_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'riscv-tests-src', 'riscv-tests-master', 'isa'))
SELF_HEADER = os.path.join(os.path.dirname(__file__), 'riscv_test_self.h')
MACROS_HEADER = os.path.join(TESTS_ROOT, 'macros', 'scalar', 'test_macros.h')
XLEN = 32

# ---------------------------------------------------------------------------
# 预处理：去注释、续行
# ---------------------------------------------------------------------------

def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    out = []
    for line in text.split('\n'):
        line = re.sub(r'//.*', '', line)
        out.append(line)
    return '\n'.join(out)

def join_continuations(text):
    return re.sub(r'\\\r?\n', ' ', text)

# ---------------------------------------------------------------------------
# 宏定义解析与展开
# ---------------------------------------------------------------------------

def parse_defines(text):
    """提取 #define。返回 {name: (params_or_None, body, is_vararg)}"""
    macros = {}
    for m in re.finditer(r'#\s*define\s+(\w+)(?:\((.*?)\))?(.*)', text, re.S):
        name = m.group(1)
        params_s = m.group(2)
        body = (m.group(3) or '').strip()
        if params_s is None:
            macros[name] = (None, body, False)
        else:
            raw = [p.strip() for p in params_s.split(',')]
            vararg = False
            params = []
            for p in raw:
                if p.endswith('...'):
                    vararg = True
                    params.append(p[:-3].strip())
                else:
                    params.append(p)
            macros[name] = (params, body, vararg)
    return macros

def split_args(s):
    """按顶层逗号分割宏调用参数（括号深度感知）"""
    parts = []
    depth = 0
    cur = ''
    for ch in s:
        if ch == '(' or ch == '[':
            depth += 1
        elif ch == ')' or ch == ']':
            depth -= 1
        if ch == ',' and depth == 0:
            parts.append(cur.strip())
            cur = ''
        else:
            cur += ch
    parts.append(cur.strip())
    return parts

def split_args_vararg(s, n_fixed):
    """变参宏参数分割：前 n_fixed-1 个顶层逗号分割，剩余原始文本（含逗号）归变参。"""
    parts = []
    depth = 0
    cur = ''
    count = 0
    for ch in s:
        if ch == '(' or ch == '[':
            depth += 1
        elif ch == ')' or ch == ']':
            depth -= 1
        if ch == ',' and depth == 0 and count < n_fixed - 1:
            parts.append(cur.strip())
            cur = ''
            count += 1
        else:
            cur += ch
    parts.append(cur.strip())
    return parts

def const_eval(s):
    """安全求值常量表达式（字面量 + 位运算/移位/三目），返回 Python 整数。"""
    s = s.strip()
    if not s:
        raise ValueError('空表达式')
    # __riscv_xlen 由 -m32 定义；本项目固定 32
    s = s.replace('__riscv_xlen', '32')
    # 只允许白名单字符，防止任意代码
    if not re.fullmatch(r'[0-9a-fA-FxXbBoO_+\-*/%&|^~<>()?: \t]+', s):
        raise ValueError('非法常量表达式: %r' % s)
    ns = {'__builtins__': {}}
    try:
        v = eval(s, ns, {})
        if isinstance(v, bool):
            v = int(v)
        if not isinstance(v, int):
            raise ValueError('非整数: %r' % s)
        return v
    except Exception as e:
        raise ValueError('常量求值失败 %r: %s' % (s, e))

def macro_expand_body(name, params, body, args, vararg, macros):
    """展开一个函数宏的 body。返回展开后的文本（未二次展开）。"""
    # 特殊数值宏：直接计算（__riscv_xlen = 32）
    if name == 'MASK_XLEN':
        return str(const_eval(args[0]) & 0xFFFFFFFF)
    if name == 'SEXT_IMM':
        v = const_eval(args[0]) & 0xFFF
        if v & 0x800:
            v |= 0xFFFFF000
        return str(v & 0xFFFFFFFF)

    mapping = {}
    n = len(params)
    if vararg:
        for i, p in enumerate(params):
            mapping[p] = args[i] if i < len(args) else ''
        if len(args) > n:
            mapping['__VA_ARGS__'] = ','.join(args[n:])
    else:
        for i, p in enumerate(params):
            mapping[p] = args[i] if i < len(args) else ''

    body = body.strip()
    # 参数替换（## 两侧的延迟拼接）；必须 token 级匹配（\b），
    # 否则单字符参数（如 MASK_XLEN 的 x）会污染 __riscv_xlen 等标识符
    body = re.sub(r'\s*##\s*', '\x01', body)
    for p, v in mapping.items():
        body = re.sub(r'\b' + re.escape(p) + r'\b', lambda m: v, body)
    # 拼接 token
    body = body.replace('\x01', '')
    return body

def expand_once(text, macros):
    """一轮展开：替换所有宏调用与对象宏引用。返回新文本。"""
    # 1) 对象宏（简单替换，非调用）
    def obj_repl(m):
        name = m.group(1)
        if name in macros and macros[name][0] is None:
            return macros[name][1]
        return m.group(0)

    # 先处理函数宏调用：NAME(args)
    out = []
    i = 0
    n = len(text)
    while i < n:
        m = re.match(r'\b([A-Za-z_]\w*)\s*\(', text[i:])
        if m and m.group(1) in macros and macros[m.group(1)][0] is not None:
            name = m.group(1)
            start = i
            depth = 0
            j = i + m.end() - 1  # 指向 '('
            # 找匹配的 ')'
            while j < n:
                if text[j] == '(':
                    depth += 1
                elif text[j] == ')':
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            if j < n:
                arg_s = text[i + m.end():j]
                params, body, vararg = macros[name]
                if vararg:
                    args = split_args_vararg(arg_s, len(params))
                else:
                    args = split_args(arg_s)
                expanded = macro_expand_body(name, params, body, args, vararg, macros)
                out.append(expanded)
                i = j + 1
                continue
        # 对象宏
        m2 = re.match(r'\b([A-Za-z_]\w*)\b', text[i:])
        if m2:
            name = m2.group(1)
            if name in macros and macros[name][0] is None:
                out.append(macros[name][1])
                i += m2.end()
                continue
        out.append(text[i])
        i += 1
    return ''.join(out)

def expand_macros(text, macros):
    """迭代展开直至稳定。"""
    for _ in range(200):
        new = expand_once(text, macros)
        if new == text:
            return text
        text = new
    raise RuntimeError('宏展开未收敛（可能有递归宏）')

# ---------------------------------------------------------------------------
# include 解析（递归）
# ---------------------------------------------------------------------------

def resolve_include(name, cur_file):
    if name == 'riscv_test.h':
        return open(SELF_HEADER, encoding='utf-8').read(), '<riscv_test_self.h>'
    if name == 'test_macros.h':
        return open(MACROS_HEADER, encoding='utf-8').read(), MACROS_HEADER
    # 相对路径（如 ../rv64ui/add.S）
    p = os.path.normpath(os.path.join(os.path.dirname(cur_file), name))
    if os.path.exists(p):
        return open(p, encoding='utf-8').read(), p
    raise FileNotFoundError('无法解析 include: %s (from %s)' % (name, cur_file))

def process(text, cur_file, depth=0):
    """处理 #undef/#define/#include，返回 (text, macros)。"""
    if depth > 15:
        raise RuntimeError('include 嵌套过深')
    macros = {}
    lines = text.split('\n')
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        # 多行 define：以 \ 结尾续行
        while line.rstrip().endswith('\\') and i + 1 < len(lines):
            i += 1
            line = line.rstrip()[:-1] + ' ' + lines[i]
        st = line.strip()
        if st.startswith('#include'):
            inc = re.match(r'#\s*include\s+"([^"]+)"', line)
            if inc:
                inc_text, inc_file = resolve_include(inc.group(1), cur_file)
                inc_text = strip_comments(inc_text)
                sub_text, sub_macros = process(inc_text, inc_file, depth + 1)
                macros.update(sub_macros)
                out.append('\n; <<< include %s >>>\n' % inc.group(1))
                out.append(sub_text)
                i += 1
                continue
        if st.startswith('#define'):
            # 收集宏定义（可能跨行已由上面合并）
            m = re.match(r'#\s*define\s+(\w+)(?:\((.*?)\))?(.*)', line, re.S)
            if m:
                name = m.group(1)
                params_s = m.group(2)
                body = (m.group(3) or '').strip()
                if params_s is None:
                    macros[name] = (None, body, False)
                else:
                    raw = [p.strip() for p in params_s.split(',')]
                    vararg = False
                    params = []
                    for p in raw:
                        if p.endswith('...'):
                            vararg = True
                            params.append(p[:-3].strip())
                        else:
                            params.append(p)
                    macros[name] = (params, body, vararg)
                i += 1
                continue
        if st.startswith('#undef'):
            m = re.match(r'#\s*undef\s+(\w+)', line)
            if m:
                macros.pop(m.group(1), None)
                i += 1
                continue
        # 其他 # 行（#if 等）忽略
        if st.startswith('#'):
            i += 1
            continue
        out.append(line)
        i += 1
    return '\n'.join(out), macros

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def filter_rv32_shifts(text):
    """RV32 语义过滤：删除移位量 >= 32 的测试用例块（RV64 特有边界用例）。
    RV32 移位立即数字段仅 5 位（0-31），RV64 测试的 shamt 32-63 用例在 RV32
    下语义不成立（硬件取低 5 位，结果与期望不符），整块跳过。"""
    lines = text.split('\n')
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if re.match(r'^\s*test_\d+:', line):
            j = i + 1
            block = [line]
            bad = False
            while j < len(lines):
                lj = lines[j]
                if re.match(r'^\s*test_\d+:', lj):
                    break
                block.append(lj)
                m = re.match(r'^\s*(slli|srli|srai)\s+\S+\s*,\s*\S+\s*,\s*(\d+)', lj)
                if m and int(m.group(2)) >= 32:
                    bad = True
                m2 = re.match(r'^\s*li\s+x12\s*,\s*(\d+)', lj)
                if m2 and int(m2.group(1)) >= 32:
                    bad = True
                m3 = re.match(r'^\s*(sll|srl|sra)\s+\S+\s*,\s*\S+\s*,\s*x12', lj)
                if m3 and m2:
                    bad = True
                j += 1
            if bad:
                i = j
                continue
            out.extend(block)
            i = j
            continue
        out.append(line)
        i += 1
    return '\n'.join(out)

# 文件级框架行（RV64 块删除时保留）：TEST_PASSFAIL 展开、test_end 自旋、数据段
FRAME_RE = re.compile(r'^\s*(bne\s+x0,|fail:|pass:|test_end:|j\s+test_end|'
                      r'tdat\w*:|\.(word|byte|half|rept|endr)\b)')
# 测试块头：test_N: 或数字局部标签（ma_data.S 的 MISALIGNED_LOAD_TEST 用 1: 分组）
BLOCK_HEAD = re.compile(r'^\s*(test_\d+|\d+):')

def filter_rv32_insts(text):
    """RV64-only 指令过滤：删除含 ld/sd/lwu/ldu/addiw/subw 等 RV64 特有
    指令的测试用例块（如 ld_st.S 的 test_50+ 'Test sd and ld' 组、
    ma_data.S 的 lwu/ld/sd 组，数字标签 1: 分组）。
    块被删时保留文件级框架行（TEST_PASSFAIL 展开 / test_end / 数据段），
    否则末块会把 TEST_PASSFAIL 和 tdat 一起删掉。"""
    rv64_insts = re.compile(r'^\s*(ld|sd|lwu|ldu|addiw|addw|subw|sllw|srlw|sraw|'
                            r'mulw|divw|divuw|remw|remuw)\s+\S')
    lines = text.split('\n')
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if BLOCK_HEAD.match(line):
            j = i + 1
            block = [line]
            bad = False
            while j < len(lines):
                lj = lines[j]
                if BLOCK_HEAD.match(lj):
                    break
                block.append(lj)
                if rv64_insts.match(lj):
                    bad = True
                j += 1
            if bad:
                # 只删测试主体，保留框架行
                for bl in block:
                    if FRAME_RE.match(bl.strip()):
                        out.append(bl)
                i = j
                continue
            out.extend(block)
            i = j
            continue
        # 非块行：行级删除 RV64-only 指令
        if rv64_insts.match(line):
            i += 1
            continue
        out.append(line)
        i += 1
    return '\n'.join(out)

def expand_rept(text):
    """展开 .rept N ... .endr 块（行重复 N 次）。"""
    lines_in = text.split('\n')
    out = []
    i = 0
    while i < len(lines_in):
        s = lines_in[i].strip()
        m = re.match(r'^\.rept\s+(\d+)$', s)
        if m:
            n = int(m.group(1))
            body = []
            i += 1
            while i < len(lines_in) and '.endr' not in lines_in[i]:
                body.append(lines_in[i])
                i += 1
            i += 1  # 跳过 .endr
            for _ in range(n):
                out.extend(body)
            continue
        out.append(lines_in[i])
        i += 1
    return '\n'.join(out)

def convert(src_s, out_dir):
    with open(src_s, encoding='utf-8') as f:
        text = f.read()
    text = strip_comments(text)
    text, macros = process(text, src_s)
    text = expand_macros(text, macros)
    text = join_continuations(text)
    # 宏体用 ';' 分隔指令：转成换行（riscv-tests 中 ';' 不作注释）
    text = text.replace(';', '\n')
    text = filter_rv32_shifts(text)
    text = filter_rv32_insts(text)
    # 展开 GAS .rept N ... .endr（数据段重复填充，如 ld_st.S 的 tdat）
    text = expand_rept(text)
    # ------------------------------------------------------------------
    # 数据区字节流状态机：.byte/.half 打包成小端 .word（riscv-tests 的
    # tdat 数据是字节/半字粒度，CPU 数据通路按字寻址）；
    # 偏移标签（tdat2 = tdat+2）就地替换成 base+imm 形式。
    # ------------------------------------------------------------------
    offset_map = {}       # label -> (base_label, byte_offset)
    pending = []          # 当前数据块的字节（小端序，[0]=低字节）
    pending_base = None   # 当前块起始标签（tdat）
    last_label = None     # 最近出现的纯标签行
    data_lines = []       # 数据块输出（.word 行）

    def flush_pending():
        nonlocal pending, pending_base, data_lines
        if not pending:
            return
        while len(pending) % 4 != 0:
            pending.append(0)
        for i in range(0, len(pending), 4):
            w = 0
            for j in range(4):
                w |= pending[i + j] << (8 * j)
            data_lines.append('.word 0x%08X' % w)
        pending = []
        pending_base = None

    def emit_data():
        nonlocal data_lines
        if not data_lines:
            return []
        o = list(data_lines)
        data_lines = []
        return o

    lines = []
    for ln in text.split('\n'):
        s = ln.strip()
        if not s or s.startswith('#'):
            continue
        if s.startswith('; <<<') and s.endswith('>>>'):
            continue
        if s.startswith('//') or s.startswith('/*'):
            continue
        if '<<<' in s and '>>>' in s:
            continue
        # 纯标签行：flush 前一数据块，记录 last_label
        m = re.match(r'^([A-Za-z_.$][\w.$]*\d*):\s*$', s)
        if m:
            lines.extend(emit_data())
            last_label = m.group(1)
            lines.append(s)
            continue
        # 标签 + .byte/.half 同行
        m = re.match(r'^([A-Za-z_.$][\w.$]*\d*):\s*\.(byte|half)\s+(.*)$', s)
        if m:
            name, kind, vals = m.groups()
            if pending_base is None:
                pending_base = last_label
            off = len(pending)
            offset_map[name] = (pending_base, off)
            for x in vals.split(','):
                x = x.strip()
                if not x:
                    continue
                if kind == 'byte':
                    pending.append(const_eval(x) & 0xFF)
                else:
                    h = const_eval(x) & 0xFFFF
                    pending.append(h & 0xFF)
                    pending.append((h >> 8) & 0xFF)
            continue
        # 无标签 .byte/.half
        if s.startswith('.byte') or s.startswith('.half'):
            kind = s[1:5]
            vals = s[6:].strip()
            if pending_base is None:
                pending_base = last_label
            for x in vals.split(','):
                x = x.strip()
                if not x:
                    continue
                if kind == 'byte':
                    pending.append(const_eval(x) & 0xFF)
                else:
                    h = const_eval(x) & 0xFFFF
                    pending.append(h & 0xFF)
                    pending.append((h >> 8) & 0xFF)
            continue
        # GAS 伪指令：.pushsection/.popsection/.align/.globl/.section 等删除
        if s.startswith('.'):
            if s.startswith('.word'):
                flush_pending()
                lines.extend(emit_data())
                lines.append(ln)
            continue
        # 普通代码行：flush 数据块（若在数据区后）
        if pending or data_lines:
            flush_pending()
            lines.extend(emit_data())
        lines.append(ln)
    # 文件末尾 flush 残留数据
    flush_pending()
    lines.extend(emit_data())
    # 偏移标签就地替换：tdat2 -> tdat + 2（0 偏移直接映射 base）
    out_text = '\n'.join(lines)
    for name, (base, off) in offset_map.items():
        if off == 0:
            repl = base
        else:
            repl = '%s + %d' % (base, off)
        out_text = re.sub(r'\b%s\b' % re.escape(name), repl, out_text)
    base = os.path.basename(src_s).replace('.S', '').replace('.s', '')
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, base + '.s')
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(out_text)
    print('ok: %s -> %s (%d lines)' % (os.path.basename(src_s), out_path, len(out_text.split('\n'))))
    return out_path

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('usage: python riscv_tests_conv.py <rv32ui/x.S> [out_dir]')
        sys.exit(1)
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(sys.argv[1]), 'converted')
    convert(sys.argv[1], out_dir)
