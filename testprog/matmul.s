# =============================================================================
# matmul.s - 3x3 整数矩阵乘法应用（RV32I，自校验）
#   C = A * B（行优先存储，3x3）
#   A = [1 2 3; 4 5 6; 7 8 9]
#   B = [9 8 7; 6 5 4; 3 2 1]
#   C 期望 = [30 24 18; 84 69 54; 138 114 90]
# 校验全部 9 个元素通过 -> gp(x3)=1（tb_rvtest 判定 PASS）
# RV32I 无乘法指令，用移位-加法软件乘法（32 轮）
# =============================================================================
start:
    j    prog
# ---- 数据区（代码段内） ----
A:
    .word 1
    .word 2
    .word 3
    .word 4
    .word 5
    .word 6
    .word 7
    .word 8
    .word 9
B:
    .word 9
    .word 8
    .word 7
    .word 6
    .word 5
    .word 4
    .word 3
    .word 2
    .word 1
C:
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
EXP:
    .word 30
    .word 24
    .word 18
    .word 84
    .word 69
    .word 54
    .word 138
    .word 114
    .word 90
# ---- 主程序 ----
prog:
    li   s0, 0              # i
i_loop:
    li   s1, 0              # j
j_loop:
    li   s2, 0              # k
    li   t6, 0              # 累加器 C[i][j]
k_loop:
    la   t0, A
    la   t1, B
    slli t2, s0, 3          # i*8
    slli t3, s0, 2          # i*4
    add  t2, t2, t3         # i*12
    slli t3, s2, 2          # k*4
    add  t2, t2, t3         # i*12 + k*4
    add  t0, t0, t2         # &A[i][k]
    lw   a0, 0(t0)
    slli t2, s2, 3          # k*8
    slli t3, s2, 2          # k*4
    add  t2, t2, t3         # k*12
    slli t3, s1, 2          # j*4
    add  t2, t2, t3         # k*12 + j*4
    add  t1, t1, t2         # &B[k][j]
    lw   a1, 0(t1)
    call mul                # a2 = a0 * a1
    add  t6, t6, a2         # 累加
    addi s2, s2, 1
    li   t4, 3
    blt  s2, t4, k_loop
    la   t0, C
    slli t2, s0, 3          # i*8
    slli t3, s0, 2          # i*4
    add  t2, t2, t3         # i*12
    slli t3, s1, 2          # j*4
    add  t2, t2, t3         # i*12 + j*4
    add  t0, t0, t2
    sw   t6, 0(t0)          # C[i][j] = t6
    addi s1, s1, 1
    li   t4, 3
    blt  s1, t4, j_loop
    addi s0, s0, 1
    li   t4, 3
    blt  s0, t4, i_loop
# ---- 校验 9 个元素 ----
    la   t0, C
    la   t1, EXP
    li   s3, 0
chk_loop:
    lw   t2, 0(t0)
    lw   t3, 0(t1)
    bne  t2, t3, fail
    addi t0, t0, 4
    addi t1, t1, 4
    addi s3, s3, 1
    li   t4, 9
    blt  s3, t4, chk_loop
    li   x3, 1              # PASS
    j    test_end
fail:
    li   x3, 2              # FAIL
test_end:
    j    test_end
# ---- 软件乘法 a0*a1 -> a2（无符号，32 轮移位加） ----
mul:
    li   a2, 0
    li   t5, 32
mul_loop:
    andi t4, a1, 1
    beq  t4, x0, mul_skip
    add  a2, a2, a0
mul_skip:
    slli a0, a0, 1
    srli a1, a1, 1
    addi t5, t5, -1
    bnez t5, mul_loop
    jalr x0, ra, 0
