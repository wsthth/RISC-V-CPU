# -*- coding: utf-8 -*-
"""诊断 oos 堆版本性能：单组 W=2 WIN=32，带进度打印"""
import io, re, time, heapq

LOG = r'D:\my_project\RISC-V\sim\work\coremark_v15_btb128.log'
HEX = r'D:\my_project\RISC-V\testprog\hex\coremark1.hex'

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
    if op == 0x33: return ('alu', rd, [rs1, rs2], 1)
    if op == 0x13: return ('alu', rd, [rs1], 1)
    if op == 0x03: return ('ld', rd, [rs1], 2)
    if op == 0x23: return ('st', 0, [rs1, rs2], 1)
    if op == 0x63: return ('br', 0, [rs1, rs2], 1)
    if op == 0x6f: return ('jal', rd, [], 1)
    if op == 0x67: return ('jalr', rd, [rs1], 1)
    if op in (0x37, 0x17): return ('alu', rd, [], 1)
    if op == 0x0f: return ('fence', 0, [], 1)
    if op == 0x73: return ('sys', 0, [], 1)
    return ('other', 0, [], 1)

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

def main():
    OUT = r'D:\my_project\RISC-V\ppt_work\diag_log.txt'
    def log(msg):
        with io.open(OUT, 'a', encoding='utf-8') as f:
            f.write(msg + '\n')

    io.open(OUT, 'w', encoding='utf-8').close()
    imem = load_imem(HEX)
    log('imem loaded')
    instrs = parse_trace(LOG, imem)
    N = len(instrs)
    log('N=%d parsed' % N)
    reg_pending = [[] for _ in range(32)]
    pcnt0 = [0] * N
    for j, ins in enumerate(instrs):
        c = 0
        for r in ins[2]:
            if r: c += 1; reg_pending[r].append(j)
        pcnt0[j] = c
    log('deps built')
    W, WIN = 2, 32
    pcnt = list(pcnt0)
    rd_finish = [-10**9] * 32
    emitted = [False] * N
    heap = []
    for j in range(N):
        if pcnt[j] == 0:
            heapq.heappush(heap, (0, j))
    log('heap init done, size=%d' % len(heap))
    i = 0; emitted_cnt = 0; cyc = 0
    t0 = time.time()
    while emitted_cnt < N:
        while i < N and emitted[i]:
            i += 1
        n = 0
        if i < N and not emitted[i]:
            ins = instrs[i]
            if all(rd_finish[r] <= cyc for r in ins[2]):
                emitted[i] = True; emitted_cnt += 1; n += 1
                if ins[1]:
                    fin = cyc + ins[3]; rd_finish[ins[1]] = fin
                    for wj in reg_pending[ins[1]]:
                        pcnt[wj] -= 1
                        if pcnt[wj] == 0:
                            rt = max([rd_finish[r] for r in instrs[wj][2]] or [0])
                            heapq.heappush(heap, (rt, wj))
        while heap and n < W and (emitted_cnt - i) < WIN:
            rt, j = heapq.heappop(heap)
            if rt > cyc:
                heapq.heappush(heap, (rt, j))
                break
            if j < i or emitted[j]:
                continue
            ins = instrs[j]
            if not all(rd_finish[r] <= cyc for r in ins[2]):
                rt_new = max([rd_finish[r] for r in ins[2]] or [0])
                heapq.heappush(heap, (rt_new, j))
                continue
            emitted[j] = True; emitted_cnt += 1; n += 1
            if ins[1]:
                fin = cyc + ins[3]; rd_finish[ins[1]] = fin
                for wj in reg_pending[ins[1]]:
                    pcnt[wj] -= 1
                    if pcnt[wj] == 0:
                        rt2 = max([rd_finish[r] for r in instrs[wj][2]] or [0])
                        heapq.heappush(heap, (rt2, wj))
        cyc += 1
        if cyc % 200000 == 0:
            log('cyc=%d emitted=%d i=%d rob=%d heap=%d t=%.1fs' % (cyc, emitted_cnt, i, emitted_cnt - i, len(heap), time.time() - t0))
    log('DONE issue_cyc=%d ipc=%.3f t=%.1fs' % (cyc, N / cyc, time.time() - t0))

if __name__ == '__main__':
    main()
