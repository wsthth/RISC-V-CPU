# =============================================================================
# basic.s - 单周期/流水线基础功能测试
# 结果写入 DMEM[0x100..0x124]，TB 对照检查
# 期望值：
#   0x100=13 0x104=8  0x108=5  0x10C=7
#   0x110=1  0x114=1  0x118=1  0x11C=0
#   0x120=10 0x124=42
# =============================================================================
start:
    li   t0, 0x100
    li   t1, 5
    li   t2, 7
    add  t3, t1, t2        # 12
    sub  t4, t2, t1        # 2
    and  t5, t1, t2        # 5
    or   t6, t1, t2        # 7
    xor  s0, t1, t2        # 2
    slt  s1, t1, t2        # 1
    sltu s2, t1, t2        # 1
    addi t3, t3, 1         # 13
    slli t4, t4, 2         # 8
    srli s0, s0, 1         # 1
    srai s1, s1, 0         # 1
    # ---- 存储结果 ----
    sw   t3, 0(t0)
    sw   t4, 4(t0)
    sw   t5, 8(t0)
    sw   t6, 12(t0)
    sw   s0, 16(t0)
    sw   s1, 20(t0)
    sw   s2, 24(t0)
    sw   x0, 28(t0)
    # ---- 分支循环 ----
    li   a0, 0
    li   a1, 10
loop:
    addi a0, a0, 1
    blt  a0, a1, loop
    sw   a0, 32(t0)        # 10
    # ---- jalr 函数调用 ----
    la   t1, func
    jalr ra, t1, 0
    j    done
func:
    addi a2, a2, 42
    sw   a2, 36(t0)        # 42
    ret
done:
    beq  x0, x0, done      # 停机自环
