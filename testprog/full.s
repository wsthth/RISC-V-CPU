# =============================================================================
# full.s - RV32I 全指令集系统级测试
# 覆盖：lui/auipc、R型算术/移位/比较/逻辑、I型立即数/移位、
#       load/store 全部宽度、全部 6 种分支、jal/jalr
# 结果写 DMEM[0x300..0x3C0]，TB 对照检查（陷阱 sw 用于捕获错误执行）
# =============================================================================
start:
    li   t0, 0x300          # 结果基址
    # ---- 1. lui / auipc ----
    lui  t1, 0x12345
    sw   t1, 0(t0)          # 0x12345000
    auipc t2, 0
    sw   t2, 4(t0)          # auipc 自身地址（高 20 位应为 0）
    # ---- 2. R 型算术 ----
    li   t3, 100
    li   t4, 37
    add  t5, t3, t4
    sw   t5, 8(t0)          # 137
    sub  t5, t3, t4
    sw   t5, 12(t0)         # 63
    # ---- 3. R 型移位 ----
    li   t3, 0x80000001
    li   t4, 4
    sll  t5, t3, t4
    sw   t5, 16(t0)         # 0x00000010
    srl  t5, t3, t4
    sw   t5, 20(t0)         # 0x08000000
    sra  t5, t3, t4
    sw   t5, 24(t0)         # 0xF8000000
    # ---- 4. slt / sltu ----
    li   t3, -1
    li   t4, 1
    slt  t5, t3, t4
    sw   t5, 28(t0)         # 1（有符号 -1 < 1）
    sltu t5, t3, t4
    sw   t5, 32(t0)         # 0（无符号 0xFFFFFFFF > 1）
    # ---- 5. 逻辑 ----
    li   t3, 0xF0F0F0F0
    li   t4, 0x0F0F0F0F
    and  t5, t3, t4
    sw   t5, 36(t0)         # 0x00000000
    or   t5, t3, t4
    sw   t5, 40(t0)         # 0xFFFFFFFF
    xor  t5, t3, t4
    sw   t5, 44(t0)         # 0xFFFFFFFF
    # ---- 6. I 型立即数 ----
    li   t3, 10
    addi t5, t3, -5
    sw   t5, 48(t0)         # 5
    slti t5, t3, 15
    sw   t5, 52(t0)         # 1
    sltiu t5, t3, -1
    sw   t5, 56(t0)         # 1（无符号 10 < 0xFFFFFFFF）
    xori t5, t3, 0xFF
    sw   t5, 60(t0)         # 0xF5
    ori  t5, t3, 0xF0
    sw   t5, 64(t0)         # 0xFA
    andi t5, t3, 0x0F
    sw   t5, 68(t0)         # 0x0A
    # ---- 7. 移位立即数 ----
    li   t3, 0x80000001
    slli t5, t3, 3
    sw   t5, 72(t0)         # 0x00000008
    srli t5, t3, 3
    sw   t5, 76(t0)         # 0x10000000
    srai t5, t3, 3
    sw   t5, 80(t0)         # 0xF0000000
    # ---- 8. load/store 全宽度 ----
    li   t1, 0x200
    li   t3, 0x88776655
    sw   t3, 0(t1)          # 构造数据 0x88776655
    lb   t4, 0(t1)          # 0x55 -> 0x00000055
    sw   t4, 84(t0)
    lb   t4, 3(t1)          # 0x88 -> 0xFFFFFF88
    sw   t4, 88(t0)
    lbu  t4, 3(t1)          # 0x88 -> 0x00000088
    sw   t4, 92(t0)
    lh   t4, 0(t1)          # 0x6655 -> 0x00006655
    sw   t4, 96(t0)
    lhu  t4, 2(t1)          # 0x8877 -> 0x00008877
    sw   t4, 100(t0)
    lw   t4, 0(t1)          # 0x88776655
    sw   t4, 104(t0)
    # 写回验证：sb / sh / sw
    li   t3, 0xAABBCCDD
    sb   t3, 4(t1)          # 写字节 0xDD
    lbu  t4, 4(t1)
    sw   t4, 108(t0)        # 0xDD
    li   t3, 0x11223344
    sh   t3, 8(t1)          # 写半字 0x3344
    lhu  t4, 8(t1)
    sw   t4, 112(t0)        # 0x3344
    li   t3, 0xDEADBEEF
    sw   t3, 12(t1)
    lw   t4, 12(t1)
    sw   t4, 116(t0)        # 0xDEADBEEF
    # ---- 9. 分支（陷阱 sw 检查错误执行）----
    li   t3, 5
    li   t4, 5
    beq  t3, t4, b1
    li   t5, 100            # 陷阱：不应执行
    sw   t5, 120(t0)
b1:
    sw   t3, 124(t0)        # 5
    li   t4, 7              # bne：5 != 7 应跳转
    bne  t3, t4, b2
    li   t5, 200            # 陷阱
    sw   t5, 128(t0)
b2:
    sw   t3, 132(t0)        # 5
    li   t3, -1
    li   t4, 1
    blt  t3, t4, b3
    li   t5, 300            # 陷阱
    sw   t5, 136(t0)
b3:
    sw   t3, 140(t0)        # -1
    bge  t3, t4, b4         # -1 >= 1 假，继续
    li   t5, 400            # 应执行
    sw   t5, 144(t0)
b4:
    sw   t4, 148(t0)        # 1
    bltu t3, t4, b5         # 无符号 0xFFFFFFFF > 1 假，继续
    li   t5, 500            # 应执行
    sw   t5, 152(t0)
b5:
    sw   t3, 156(t0)        # -1
    bgeu t4, t3, b6         # 无符号 1 < 0xFFFFFFFF 假，继续
    li   t5, 600            # 应执行
    sw   t5, 160(t0)
b6:
    sw   t4, 164(t0)        # 1
    # ---- 10. jal / jalr ----
    li   t1, 0x200
    sw   ra, 20(t1)         # 先清 ra
    jal  ra, j1
    li   t5, 700            # 陷阱：不应执行
    sw   t5, 168(t0)
j1:
    sw   ra, 172(t0)        # jal 返回地址
    lw   ra, 20(t1)         # ra 清 0
    la   t1, target_jalr
    jalr ra, t1, 0          # 跳 target_jalr（链接）
    li   t5, 800            # 陷阱
    sw   t5, 176(t0)
target_jalr:
    sw   ra, 180(t0)        # jalr 返回地址
    la   t1, done2
    jalr x0, t1, 0          # 无条件跳 done2（不链接）
    li   t5, 900            # 陷阱
    sw   t5, 184(t0)
done2:
    li   t5, 1
    sw   t5, 188(t0)
done:
    beq  x0, x0, done
