# =============================================================================
# qsort.s - 快速排序应用（RV32I，Lomuto 划分 + 递归，自校验）
#   数组 arr[8] = {5, 2, 9, 1, 7, 6, 3, 8}
#   排序后期望   = {1, 2, 3, 5, 6, 7, 8, 9}
# 校验 8 个元素全部通过 -> gp(x3)=1（tb_rvtest 判定 PASS）
# 栈：sp 初始 0x7F00（向下生长），递归帧 7 字（ra/s0-s5）
# =============================================================================
start:
    j    prog
# ---- 数据区 ----
arr:
    .word 5
    .word 2
    .word 9
    .word 1
    .word 7
    .word 6
    .word 3
    .word 8
exp:
    .word 1
    .word 2
    .word 3
    .word 5
    .word 6
    .word 7
    .word 8
    .word 9
# ---- 主程序 ----
prog:
    li   sp, 0x7F00
    la   a0, arr
    li   a1, 0
    li   a2, 7
    call qsort
    # ---- 校验 ----
    la   t0, arr
    la   t1, exp
    li   t2, 0
chk:
    lw   t3, 0(t0)
    lw   t4, 0(t1)
    bne  t3, t4, fail
    addi t0, t0, 4
    addi t1, t1, 4
    addi t2, t2, 1
    li   t5, 8
    blt  t2, t5, chk
    li   x3, 1              # PASS
    j    test_end
fail:
    li   x3, 2              # FAIL
test_end:
    j    test_end
# ---- 快速排序 qsort(a0=arr, a1=lo, a2=hi) ----
qsort:
    addi sp, sp, -28
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    sw   s2, 12(sp)
    sw   s3, 16(sp)
    sw   s4, 20(sp)
    sw   s5, 24(sp)
    mv   s0, a0             # arr
    mv   s1, a1             # lo
    mv   s2, a2             # hi
    bge  s1, s2, q_done     # lo >= hi -> 返回
    slli t0, s2, 2
    add  t0, s0, t0
    lw   s5, 0(t0)          # pivot = arr[hi]
    addi s3, s1, -1         # i = lo - 1
    mv   s4, s1             # j = lo
q_loop:
    bge  s4, s2, q_swap_pivot   # j >= hi
    slli t0, s4, 2
    add  t0, s0, t0
    lw   t1, 0(t0)          # arr[j]
    blt  s5, t1, q_jnext    # arr[j] > pivot: skip
    addi s3, s3, 1          # i++
    slli t2, s3, 2
    add  t2, s0, t2
    lw   t3, 0(t2)          # arr[i]
    sw   t1, 0(t2)          # arr[i] = arr[j]
    sw   t3, 0(t0)          # arr[j] = 旧 arr[i]
q_jnext:
    addi s4, s4, 1
    j    q_loop
q_swap_pivot:
    addi t0, s3, 1          # i+1
    slli t1, t0, 2
    add  t1, s0, t1
    lw   t2, 0(t1)          # arr[i+1]
    sw   s5, 0(t1)          # arr[i+1] = pivot
    slli t3, s2, 2
    add  t3, s0, t3
    sw   t2, 0(t3)          # arr[hi] = 旧 arr[i+1]
    # 递归左：qsort(arr, lo, i)
    mv   a0, s0
    mv   a1, s1
    mv   a2, s3
    call qsort
    # 递归右：qsort(arr, i+2, hi)
    mv   a0, s0
    addi a1, s3, 2
    mv   a2, s2
    call qsort
q_done:
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    lw   s2, 12(sp)
    lw   s3, 16(sp)
    lw   s4, 20(sp)
    lw   s5, 24(sp)
    addi sp, sp, 28
    jalr x0, ra, 0
