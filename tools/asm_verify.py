#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
asm_verify.py - 汇编器编码自动校验
对关键指令的机器码做断言，防止编码回归。
用法: python asm_verify.py
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import riscv_asm as A

def enc1(text):
    words, _, _ = A.assemble(text)
    return words[0][1]

cases = [
    # (汇编源码行, 期望机器码)
    ('add x1, x2, x3',        0x003100B3),
    ('sub x4, x5, x6',        0x40628233),
    ('sll x1, x2, x3',        0x003110B3),
    ('sra x1, x2, x3',        0x403150B3),
    ('sltu x1, x2, x3',       0x003130B3),
    ('addi x1, x0, -1',       0xFFF00093),
    ('addi x1, x0, 2047',     0x7FF00093),
    ('slli x1, x2, 31',       0x01F11093),
    ('srli x1, x2, 16',       0x01015093),
    ('srai x1, x2, 8',        0x40815093),
    ('lw x21, 4(x22)',        0x004B2A83),
    ('lbu x1, 255(x2)',       0x0FF14083),
    ('sw x31, 24(x0)',        0x01F02C23),
    ('sb x1, -1(x2)',         0xFE110FA3),
    # 注意：紧跟指令后的标签地址 = 下一条指令地址（偏移 = 4 的倍数）
    ('beq x1, x2, L\nL:',     0x00208263),  # 偏移4
    ('beq x1, x2, L\nnop\nL:',0x00208463),  # 偏移8
    ('lui x1, 0x12345',       0x123450B7),
    ('auipc x2, 0x00001',     0x00001117),
    ('jal x1, L\nL:',         0x004000EF),  # 偏移4
    ('jalr x3, 8(x4)',        0x008201E7),
    ('nop',                   0x00000013),
    ('li x1, -1',             0xFFF00093),
    ('li x1, 0x80000',        0x000800B7),  # lui x1,0x80
    ('li x1, 0x12345',        0x000120B7),  # 两字：取第一条
    ('mv x1, x2',             0x00010093),
    ('ret',                   0x00008067),
    ('j L\nL:',               0x0040006F),  # 偏移4
    ('beqz x1, L\nL:',        0x00008263),  # 偏移4
    ('bnez x1, L\nL:',        0x00009263),  # 偏移4
]

fail = 0
for src, expect in cases:
    try:
        got = enc1(src)
    except Exception as e:
        print('ERROR  %-28s -> %s' % (src, e))
        fail += 1
        continue
    ok = (got == expect)
    print('%s  %-28s -> %08X  expect %08X' % ('PASS' if ok else 'FAIL', src, got, expect))
    if not ok:
        fail += 1

print('\n%d cases, %d failed' % (len(cases), fail))
sys.exit(1 if fail else 0)
