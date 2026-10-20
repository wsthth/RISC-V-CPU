# -*- coding: utf-8 -*-
"""ilp_sweep.py — 精简参数扫描，带逐行文件日志"""
import io, re, sys, time, json

LOG = r'D:\my_project\RISC-V\sim\work\coremark_v15_btb128.log'
HEX = r'D:\my_project\RISC-V\testprog\hex\coremark1.hex'
OUT = r'D:\my_project\RISC-V\ppt_work\ilp_sweep_log.txt'

def log(msg):
    with io.open(OUT, 'a', encoding='utf-8') as f:
        f.write(msg + '\n')
    print(msg, flush=True)

def load_imem(path):
    imem = {}
    addr = 0
    with io.open(path, encoding='ascii') as f:
        for line in f:
            w = line.strip()
            if w:
                imem[addr] = int(w, 16)
                addr += 4
    return imem

def dec(insn):
    op = insn & 0x7f
    rd = (insn >> 7) & 0x1f
    rs1 = (insn >> 15) & 0x1f
    rs2 = (insn >> 20) & 0x1f
    kind = 'other'
    delay = 1
    reads = []
    wreg = 0
    if op == 0x33:
        kind = 'alu'; reads = [rs1, rs2]; wreg = rd
    elif op == 0x13:
        kind = 'alu'; reads = [rs1]; wreg = rd
    elif op == 0x03:
        kind = 'ld'; delay = 2; reads = [rs1]; wreg = rd
    elif op == 0x23:
        kind = 'st'; reads = [rs1, rs2]
    elif op == 0x63:
        kind = 'br'; reads = [rs1, rs2]
    elif op == 0x6f:
        kind = 'jal'; wreg = rd
    elif op == 0x67:
        kind = 'jalr'; reads = [rs1]; wreg = rd
    elif op == 0x37 or op == 0x17:
        kind = 'alu'; wreg = rd
    elif op == 0x0f:
        kind = 'fence'
    elif op == 0x73:
        kind = 'sys'
    return {'kind': kind, 'rd': wreg, 'reads': reads, 'delay': delay}

def parse_trace(log_path, imem):
    instrs = []
    pat = re.compile(r'^MEM (\d+) pc=([0-9a-f]+)')
    with io.open(log_path, encoding='utf-8', errors='replace') as f:
        for line in f:
            m = pat.match(line)
            if not m:
                continue
            pc = int(m.group(2), 16)
            insn = imem.get(pc)
            if insn is None:
                continue
            d = dec(insn)
            d['pc'] = pc
            instrs.append(d)
    return instrs

def build_deps(instrs):
    """RAW 依赖图：每条指令只依赖'最近的前序写者'；writers[w] = 依赖写者 w 的指令列表"""
    N = len(instrs)
    reg_last = [-1] * 32
    deps = []
    for j, ins in enumerate(instrs):
        ws = set()
        for r in ins['reads']:
            if r and reg_last[r] >= 0:
                ws.add(reg_last[r])
        deps.append(sorted(ws))
        if ins['rd']:
            reg_last[ins['rd']] = j
    writers = [[] for _ in range(N)]
    for j, ws in enumerate(deps):
        for w in ws:
            writers[w].append(j)
    pcnt0 = [len(d) for d in deps]
    return writers, pcnt0

def model_inorder(instrs, W):
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

def model_oos_unbounded(instrs, W, writers, pcnt0):
    """乱序无界（无限 ROB）：事件驱动调度（ready 队列 + future 桶），O(N)"""
    from collections import deque
    N = len(instrs)
    pcnt = list(pcnt0)  # 每调用独立副本
    rd_finish = [-10**9] * 32
    emitted = [False] * N
    ready_now = deque()
    future = {}  # rt -> [j]
    for j in range(N):
        if pcnt[j] == 0:
            ready_now.append(j)
    i = 0
    emitted_cnt = 0
    cyc = 0

    def emit(j):
        nonlocal emitted_cnt
        emitted[j] = True
        emitted_cnt += 1
        ins = instrs[j]
        if ins['rd']:
            fin = cyc + ins['delay']
            rd_finish[ins['rd']] = fin
            for wj in writers[j]:
                pcnt[wj] -= 1
                if pcnt[wj] == 0:
                    rt = max([rd_finish[r] for r in instrs[wj]['reads']] or [0])
                    if rt <= cyc:
                        ready_now.append(wj)
                    else:
                        future.setdefault(rt, []).append(wj)

    while emitted_cnt < N:
        while i < N and emitted[i]:
            i += 1
        n = 0
        if i < N and not emitted[i] and all(rd_finish[r] <= cyc for r in instrs[i]['reads']):
            emit(i)
            n += 1
        if cyc in future:
            ready_now.extend(future.pop(cyc))
        while ready_now and n < W:
            j = ready_now[0]
            if j < i or emitted[j]:
                ready_now.popleft()
                continue
            ins = instrs[j]
            if not all(rd_finish[r] <= cyc for r in ins['reads']):
                rt_new = max([rd_finish[r] for r in ins['reads']] or [0])
                ready_now.popleft()
                if rt_new <= cyc:
                    ready_now.append(j)
                else:
                    future.setdefault(rt_new, []).append(j)
                continue
            ready_now.popleft()
            emit(j)
            n += 1
        cyc += 1
    return cyc

def model_oos(instrs, W, WIN, writers, pcnt0):
    """乱序发射 + 提交按序 + ROB 窗口 WIN：每周期扫描窗口 [i, i+WIN) 取至多 W 条就绪指令
       就绪 = 依赖写者已发射(pcnt==0) 且 rd_finish<=cyc；发射即完成"""
    N = len(instrs)
    pcnt = list(pcnt0)  # 每调用独立副本
    rd_finish = [-10**9] * 32
    emitted = [False] * N
    i = 0
    emitted_cnt = 0
    cyc = 0
    while emitted_cnt < N:
        # 提交推进：连续已发射的指令按序提交
        while i < N and emitted[i]:
            i += 1
        n = 0
        for j in range(i, min(i + WIN, N)):
            if emitted[j] or n >= W:
                continue
            ins = instrs[j]
            if pcnt[j] == 0 and all(rd_finish[r] <= cyc for r in ins['reads']):
                emitted[j] = True
                emitted_cnt += 1
                n += 1
                if ins['rd']:
                    rd_finish[ins['rd']] = cyc + ins['delay']
                    for wj in writers[j]:
                        pcnt[wj] -= 1
        cyc += 1
    return cyc

def main():
    io.open(OUT, 'w', encoding='utf-8').close()
    imem = load_imem(HEX)
    instrs = parse_trace(LOG, imem)
    N = len(instrs)
    kinds = {}
    for ins in instrs:
        kinds[ins['kind']] = kinds.get(ins['kind'], 0) + 1
    log('dynamic instrs=%d kinds=%s' % (N, kinds))
    writers, pcnt0 = build_deps(instrs)
    log('deps built')

    MISP = 59859
    results = []
    combos = [('inorder', 1, 0), ('inorder', 2, 0), ('inorder', 4, 0),
              ('oos', 2, 32), ('oos', 4, 32),
              ('oos', 2, 64), ('oos', 4, 64),
              ('oos', 2, 128), ('oos', 4, 128),
              ('oos-u', 2, 0), ('oos-u', 4, 0)]
    for mode, W, WIN in combos:
        t0 = time.time()
        if mode == 'inorder':
            cyc = model_inorder(instrs, W)
            label = 'inorder W=%d' % W
        elif mode == 'oos-u':
            cyc = model_oos_unbounded(instrs, W, writers, pcnt0)
            label = 'oos W=%d unbounded' % W
        else:
            cyc = model_oos(instrs, W, WIN, writers, pcnt0)
            label = 'oos W=%d WIN=%d' % (W, WIN)
        ipc = N / cyc
        flush = 2 + (W - 1) * 2
        cyc_total = cyc + MISP * flush
        per_sec = 100e6 / cyc_total
        results.append({'label': label, 'W': W, 'WIN': WIN if WIN < 10**8 else None,
                        'issue_cyc': cyc, 'ipc': round(ipc, 3), 'total_cyc': cyc_total,
                        'per_sec': round(per_sec, 1)})
        log('%s issue_cyc=%d ipc=%.3f total=%d %.1f/s (%.1fs)' % (label, cyc, ipc, cyc_total, per_sec, time.time() - t0))
    with io.open(r'D:\my_project\RISC-V\ppt_work\ilp_results.json', 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=1)
    log('saved ilp_results.json')

if __name__ == '__main__':
    main()
