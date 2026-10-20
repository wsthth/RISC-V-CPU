# -*- coding: utf-8 -*-
"""
ilp_analysis.py — CoreMark 动态指令流 ILP / 多发射理论 IPC 分析
输入：sim/work/coremark_v15_btb128.log（动态 trace）+ testprog/hex/coremark1.hex（指令内存）
模型：in-order 发射(W) / 乱序窗口(WIN) / 乱序无界，仅受数据依赖(RAW)+延迟限制
输出：W x WIN 的 IPC / cycles / CoreMark@100MHz 折算表
"""
import io, re, sys, json, time

LOG = r'D:\my_project\RISC-V\sim\work\coremark_v15_btb128.log'
HEX = r'D:\my_project\RISC-V\testprog\hex\coremark1.hex'

# ---------- 1. 指令内存 ----------
def load_imem(path):
    imem = {}
    addr = 0
    with io.open(path, encoding='ascii') as f:
        for line in f:
            w = line.strip()
            if not w:
                continue
            imem[addr] = int(w, 16)
            addr += 4
    return imem

# ---------- 2. RV32I 解码 ----------
OP_MASK = 0x7f
F3_MASK = 0x7000
F7_MASK = 0xfe000000
def dec(insn):
    op = insn & OP_MASK
    f3 = (insn >> 12) & 0x7
    rd = (insn >> 7) & 0x1f
    rs1 = (insn >> 15) & 0x1f
    rs2 = (insn >> 20) & 0x1f
    f7 = (insn >> 25) & 0x7f
    kind = 'other'
    delay = 1
    reads = []
    wreg = 0
    if op == 0x33:  # R-type
        kind = 'alu'
        reads = [rs1, rs2]
        wreg = rd
    elif op == 0x13:  # I-type alu
        kind = 'alu'
        reads = [rs1]
        wreg = rd
    elif op == 0x03:  # load
        kind = 'ld'
        delay = 2
        reads = [rs1]
        wreg = rd
    elif op == 0x23:  # store
        kind = 'st'
        reads = [rs1, rs2]
    elif op == 0x63:  # branch
        kind = 'br'
        reads = [rs1, rs2]
    elif op == 0x6f:  # jal
        kind = 'jal'
        wreg = rd
    elif op == 0x67:  # jalr
        kind = 'jalr'
        reads = [rs1]
        wreg = rd
    elif op == 0x37 or op == 0x17:  # lui / auipc
        kind = 'alu'
        wreg = rd
    elif op == 0x0f:  # fence
        kind = 'fence'
    elif op == 0x73:  # ecall/ebreak
        kind = 'sys'
    return {'kind': kind, 'rd': wreg, 'reads': reads, 'delay': delay}

# ---------- 3. 解析动态 trace ----------
def parse_trace(log_path, imem):
    instrs = []  # 每条: dict(pc, kind, rd, reads, delay)
    pat = re.compile(r'^MEM (\d+) pc=([0-9a-f]+)')
    with io.open(log_path, encoding='utf-8', errors='replace') as f:
        for line in f:
            m = pat.match(line)
            if not m:
                continue
            pc = int(m.group(2), 16)
            insn = imem.get(pc)
            if insn is None:
                # 越界或数据区取指：按 0 处理（不应发生）
                continue
            d = dec(insn)
            d['pc'] = pc
            instrs.append(d)
    return instrs

# ---------- 4. 模型 ----------
def model_inorder(instrs, W):
    """顺序发射：每周期从 i 起按序取至多 W 条可发射指令；遇阻塞停止扫描"""
    N = len(instrs)
    rd_finish = [-10**9] * 32
    i = 0
    cyc = 0
    while i < N:
        issued = 0
        j = i
        while j < N and issued < W:
            ins = instrs[j]
            ok = True
            for r in ins['reads']:
                if rd_finish[r] > cyc:
                    ok = False
                    break
            if ok:
                if ins['rd']:
                    rd_finish[ins['rd']] = cyc + ins['delay']
                issued += 1
                j += 1
            else:
                break
        i += issued
        cyc += 1
    return cyc

def model_oos_unbounded(instrs, W):
    """乱序无界窗口（无限 ROB）：就绪双端队列，每周期发至多 W 条"""
    from collections import deque
    N = len(instrs)
    rd_finish = [-10**9] * 32
    reg_pending = [[] for _ in range(32)]
    pending_cnt = [0] * N
    for j, ins in enumerate(instrs):
        c = 0
        for r in ins['reads']:
            if r != 0:
                c += 1
                reg_pending[r].append(j)
        pending_cnt[j] = c
    ready = deque(j for j in range(N) if pending_cnt[j] == 0)
    emitted_cnt = 0
    cyc = 0
    while emitted_cnt < N:
        n = 0
        while ready and n < W:
            j = ready.popleft()
            ins = instrs[j]
            emitted_cnt += 1
            n += 1
            if ins['rd']:
                fin = cyc + ins['delay']
                rd_finish[ins['rd']] = fin
                for wj in reg_pending[ins['rd']]:
                    pending_cnt[wj] -= 1
                    if pending_cnt[wj] == 0:
                        ready.append(wj)
        cyc += 1
    return cyc

def model_oos_window(instrs, W, WIN):
    """乱序 + ROB 窗口限制 WIN：就绪队列 + 窗口边界（O(1)/周期）"""
    from collections import deque
    N = len(instrs)
    rd_finish = [-10**9] * 32
    reg_pending = [[] for _ in range(32)]
    pending_cnt = [0] * N
    for j, ins in enumerate(instrs):
        c = 0
        for r in ins['reads']:
            if r != 0:
                c += 1
                reg_pending[r].append(j)
        pending_cnt[j] = c
    emitted = [False] * N
    ready = deque(j for j in range(N) if pending_cnt[j] == 0)
    i = 0           # 下一条待提交指令
    emitted_cnt = 0
    cyc = 0
    while emitted_cnt < N:
        # 提交推进：i 处已发射则推进
        while i < N and emitted[i]:
            i += 1
        n = 0
        hold = []   # 窗口外的就绪指令（暂缓）
        while ready and n < W:
            j = ready.popleft()
            if j < i:
                continue
            if j >= i + WIN:
                hold.append(j)
                continue
            emitted[j] = True
            emitted_cnt += 1
            n += 1
            ins = instrs[j]
            if ins['rd']:
                fin = cyc + ins['delay']
                rd_finish[ins['rd']] = fin
                for wj in reg_pending[ins['rd']]:
                    pending_cnt[wj] -= 1
                    if pending_cnt[wj] == 0:
                        ready.append(wj)
        # 放回窗口外的指令（保持原序）
        for j in reversed(hold):
            ready.appendleft(j)
        cyc += 1
    return cyc

# ---------- 5. 主流程 ----------
def main():
    imem = load_imem(HEX)
    instrs = parse_trace(LOG, imem)
    N = len(instrs)
    # 统计
    kinds = {}
    for ins in instrs:
        kinds[ins['kind']] = kinds.get(ins['kind'], 0) + 1
    print('dynamic instrs:', N, 'kinds:', kinds)
    print('imem words:', len(imem))

    MISP = 59859
    results = []
    combos = []
    # inorder 顺序发射（现实多发射基线）
    for W in (1, 2, 4):
        combos.append(('inorder', W, 0))
    # 乱序无界（理想 ROB）
    for W in (1, 2, 4):
        combos.append(('oos-u', W, 0))
    # 乱序窗口受限
    for W in (2, 4):
        for WIN in (8, 16, 32, 64):
            combos.append(('oos-w', W, WIN))
    t0 = time.time()
    for mode, W, WIN in combos:
        if mode == 'inorder':
            cyc = model_inorder(instrs, W)
            label = f'inorder W={W}'
        elif mode == 'oos-u':
            cyc = model_oos_unbounded(instrs, W)
            label = f'oos W={W} unbounded'
        else:
            cyc = model_oos_window(instrs, W, WIN)
            label = f'oos W={W} WIN={WIN}'
        ipc = N / cyc
        # 分支惩罚（宽发射下错误路径冲刷更多指令）
        flush = 2 + (W - 1) * 2
        cyc_total = cyc + MISP * flush
        per_sec_100m = 100e6 / cyc_total
        results.append((label, W, WIN, cyc, ipc, cyc_total, per_sec_100m))
        print(label, 'issue_cyc=%d ipc=%.3f total=%d %.1f/s' % (cyc, ipc, cyc_total, per_sec_100m), flush=True)
    print('elapsed %.1fs' % (time.time() - t0))

    # 输出 JSON 供后续可视化/PPT
    with io.open(r'D:\my_project\RISC-V\ppt_work\ilp_results.json', 'w', encoding='utf-8') as f:
        json.dump([{'label': r[0], 'W': r[1], 'WIN': r[2], 'issue_cyc': r[3],
                    'ipc': round(r[4], 3), 'total_cyc': r[5], 'per_sec': round(r[6], 1)}
                   for r in results], f, ensure_ascii=False, indent=1)
    print('saved ilp_results.json')

if __name__ == '__main__':
    main()
