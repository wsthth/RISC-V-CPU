# crt0.s - RV32I bare-metal startup
#   * .data/.rodata live in DMEM (LMA==VMA, loaded from data.hex) -> no copy
#   * zero .bss
#   * set stack pointer (DMEM top)
#   * call main; on return write a0 -> gp(x3) then spin (tb_rvtest PASS)
    .section .text.start,"ax",@progbits
    .globl _start
_start:
    # ---- zero .bss ----
    la      t0, __bss_start
    la      t1, __bss_end
    li      t3, 0
1:
    bgeu    t0, t1, 2f
    sw      t3, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    # ---- stack pointer ----
    la      sp, __stack_top
    # ---- call main ----
    call    main
    # ---- main returned: a0 = validation result, pass = 0 ----
    # coremark returns 0 on pass -> gp=1 for tb_rvtest PASS
    li      t3, 1
    beq     a0, x0, 3f
    li      t3, 2
3:
    mv      x3, t3
4:
    j       4b
    .end
