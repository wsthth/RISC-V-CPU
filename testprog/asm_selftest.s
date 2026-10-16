# =============================================================================
# 汇编器自测程序：覆盖六种指令格式 + 伪指令 + 标签
# 关键编码人工核对（见 lst 输出）：
#   add x1,x2,x3        -> 0x003100B3
#   addi x1,x0,-1       -> 0xFFF00093
#   lw  x5,4(x6)        -> 0x00432283
#   sw  x5,8(x6)        -> 0x00532423
#   beq x1,x2,label     -> 偏移 0x10 -> 0x00209463
#   lui x1,0x12345      -> 0x123450B7
#   jal x1,label        -> 0x00C000EF
# =============================================================================
start:
    add  x1, x2, x3          # R型 add
    sub  x4, x5, x6          # R型 sub
    and  x7, x8, x9          # R型 and
    or   x10, x11, x12       # R型 or
    xor  x13, x14, x15       # R型 xor
    sll  x16, x17, x18       # R型 sll
    srl  x19, x20, x21       # R型 srl
    sra  x22, x23, x24       # R型 sra
    slt  x25, x26, x27       # R型 slt
    sltu x28, x29, x30       # R型 sltu
    addi x1, x0, -1          # I型 addi 负数
    addi x2, x0, 2047        # I型 addi 上界
    slti x3, x4, 5
    xori x5, x6, -1
    ori  x7, x8, 0xFF
    andi x9, x10, 0x0F
    slli x11, x12, 3
    srli x13, x14, 4
    srai x15, x16, 2
    lb   x17, 0(x18)
    lh   x19, 2(x20)
    lw   x21, 4(x22)
    lbu  x23, 8(x24)
    lhu  x25, 12(x26)
    sb   x27, 16(x28)
    sh   x29, 20(x30)
    sw   x31, 24(x0)
    beq  x1, x2, target_b
    bne  x3, x4, target_b
    blt  x5, x6, target_b
    bge  x7, x8, target_b
    bltu x9, x10, target_b
    bgeu x11, x12, target_b
    lui  x1, 0x12345
    auipc x2, 0x00001
    jal  x1, target_j
    jalr x3, 8(x4)
    nop
    li   x5, -1
    li   x6, 0x80000
    li   x7, 0x7FFFF
    li   x8, 0x12345
    mv   x9, x10
    not  x11, x12
    neg  x13, x14
    seqz x15, x16
    snez x17, x18
    beqz x19, target_b
    bnez x20, target_b
    j    target_j
    ret
    call target_j
    la   x21, target_b
    fence
    ecall
    ebreak
target_b:
    addi x0, x0, 0
target_j:
    addi x0, x0, 0
end:
    beq  x0, x0, end
