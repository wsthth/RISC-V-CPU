# -*- coding: utf-8 -*-
"""diag2: 事件驱动 oos 逐周期状态诊断（写文件）"""
import io, re, time
from collections import deque

LOG = r'D:\my_project\RISC-V\sim\work\coremark_v15_btb128.log'
HEX = r'D:\my_project\RISC-V\testprog\hex\coremark1.hex'
OUT = r'D:\my_project\RISC-V\ppt_work\diag2_log.txt'

def load_imem(path):
    imem = {}; addr = 0
    with io.open(path, encoding='ascii') as f:
        for line in f:
            w = line.strip()
            if w: imem[addr] = int(w, 16); addr += 4
    return imem

def dec(insn):
    op = insn & 0x7f; rd = (insn >> 7) & 0x1f
    rs1 = (insn >> 15) & 0x1f; rs2 = (insn >> 20) & 0x1f
    if op == 0x33: return dict(kind='alu', rd=rd, reads=[rs1, rs2], delay=1)
    if op == 0x13: return dict(kind='alu', rd=rd, reads=[rs1], delay=1)
    if op == 0x03: return dict(kind='ld', rd=rd, reads=[rs1], delay=2)
    if op == 0x23: return dict(kind='st', rd=0, reads=[rs1, rs2], delay=1)
    if op == 0x63: return dict(kind='br', rd=0, reads=[rs1, rs2], delay=1)
    if op == 0x6f: return dict(kind='jal', rd=rd, reads=[], delay=1)
    if op == 0x67: return dict(kind='jalr', rd=rd, reads=[rs1], delay=1)
    if op in (0x37, 0x17): return dict(kind='alu', rd=rd, reads=[], delay=1)
    if op == 0x0f: return dict(kind='fence', rd=0, reads=[], delay=1)
    if op == 0x73: return dict(kind='sys', rd=0, reads=[], delay=1)
    return dict(kind='other', rd=0, reads=[], delay=1)

def parse_trace(log_path, imem):
    instrs = []
    pat = re.compile(r'^MEM (\d+) pc=([0-9a-f]+)')
    with io.open(log_path, encoding='utf-8', errors='replace') as f:
        for line in f:
            m = pat.match(line)
            if m:
                pc = int(m.group(2), 16)
                insn = imem.get(pc)
                if insn is not None:
                    instrs.append(dec(insn))
    return instrs

def build_deps(instrs):
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

def main():
    io.open(OUT, 'w', encoding='utf-8').close()
    def log(msg):
        with io.open(OUT, 'a', encoding='utf-8') as f:
            f.write(msg + '\n')
    imem = load_imem(HEX)
    instrs = parse_trace(LOG, imem)
    N = len(instrs)
    log('N=%d' % N)
    writers, pcnt0 = build_deps(instrs)
    W, WIN = 2, 32
    pcnt = list(pcnt0)
    rd_finish = [-10**9] * 32
    emitted = [False] * N
    ready_now = deque()
    future = {}
    for j in range(N):
        if pcnt[j] == 0:
            ready_now.append(j)
    log('init ready_now=%d' % len(ready_now))
    i = 0; emitted_cnt = 0; cyc = 0; ahead = 0
    ahead_marked = [False] * N
    t0 = time.time()
    stall = 0
    ahead_total = 0
    oldest_total = 0
    while emitted_cnt < N:
        while i < N and emitted[i]:
            if ahead_marked[i]:
                ahead -= 1
                ahead_marked[i] = False
            i += 1
        n = 0
        if i < N and not emitted[i] and all(rd_finish[r] <= cyc for r in instrs[i]['reads']):
            emitted[i] = True; emitted_cnt += 1; n += 1; oldest_total += 1
            ins = instrs[i]
            if ins['rd']:
                fin = cyc + ins['delay']; rd_finish[ins['rd']] = fin
                for wj in writers[i]:
                    pcnt[wj] -= 1
                    if pcnt[wj] == 0:
                        rt = max([rd_finish[r] for r in instrs[wj]['reads']] or [0])
                        if rt <= cyc: ready_now.append(wj)
                        else: future.setdefault(rt, []).append(wj)
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
                if rt_new <= cyc: ready_now.append(j)
                else: future.setdefault(rt_new, []).append(j)
                continue
            if WIN is not None and ahead >= WIN:
                break
            ready_now.popleft()
            emitted[j] = True; emitted_cnt += 1; n += 1; ahead += 1
            ahead_marked[j] = True; ahead_total += 1
            if ins['rd']:
                fin = cyc + ins['delay']; rd_finish[ins['rd']] = fin
                for wj in writers[j]:
                    pcnt[wj] -= 1
                    if pcnt[wj] == 0:
                        rt = max([rd_finish[r] for r in instrs[wj]['reads']] or [0])
                        if rt <= cyc: ready_now.append(wj)
                        else: future.setdefault(rt, []).append(wj)
        if n == 0:
            stall += 1
        cyc += 1
        if cyc % 100000 == 0:
            log('cyc=%d emitted=%d i=%d ahead=%d oldest=%d ahead_issued=%d stall=%d t=%.1fs' % (cyc, emitted_cnt, i, ahead, oldest_total, ahead_total, stall, time.time() - t0))
    log('DONE issue_cyc=%d ipc=%.3f t=%.1fs stall=%d' % (cyc, N / cyc, time.time() - t0, stall))

if __name__ == '__main__':
    main()
