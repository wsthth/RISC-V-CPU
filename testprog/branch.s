# =============================================================================
# branch.s - 分支/跳转/预测器测试
# 结果写入 DMEM[0x100..0x110]，TB 对照检查
# 期望值：
#   0x100=100  0x104=50  0x108=10  0x10C=20  0x110=12
# =============================================================================
start:
    li   t0, 0x100
    # ---- 循环1：blt 后向分支（预测器学习 taken）----
    li   a0, 0
    li   a1, 100
loop1:
    addi a0, a0, 1
    blt  a0, a1, loop1
    sw   a0, 0(t0)          # 100
    # ---- 循环2：bne ----
    li   a0, 0
    li   a1, 50
loop2:
    addi a0, a0, 1
    bne  a0, a1, loop2
    sw   a0, 4(t0)          # 50
    # ---- beq 不跳转 ----
    li   a0, 1
    li   a1, 2
    beq  a0, a1, skip1
    li   a2, 10
skip1:
    sw   a2, 8(t0)          # 10
    # ---- bltu/bgeu（无符号比较）----
    li   a0, -1             # 0xFFFFFFFF
    li   a1, 1
    bltu a0, a1, skip2      # 0xFFFFFFFF > 1 -> 不跳
    li   a3, 20
skip2:
    sw   a3, 12(t0)         # 20
    # ---- jal/jalr 函数调用 ----
    li   a4, 5
    call func
    sw   a4, 16(t0)         # 5 + 7 = 12
    j    done
func:
    addi a4, a4, 7
    ret
done:
    beq  x0, x0, done
