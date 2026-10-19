/* coremark.ld - RV32I bare-metal linker script
   IMEM:  instruction only (read-only, loaded from program.hex)
   DMEM:  .rodata + .data + .bss + stack (loaded from data.hex, zero-filled by crt0)
   DMEM VMA at 0x6000 stays inside dmem addr bits [31:2] < DEPTH=8192 (0x2000).
   NOTE: .rodata must live in DMEM because the CPU (Harvard) loads only from
   dmem; read-only tables (switch jump tables, errpat) are read via lw. */
ENTRY(_start)
MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 0x8000  /* 32KB */
    DMEM (rw)  : ORIGIN = 0x00006000, LENGTH = 0x2000  /* 8KB */
}
SECTIONS
{
    .text : {
        KEEP(*(.text.start))
        *(.text*)
        . = ALIGN(4);
    } > IMEM

    .rodata : {
        *(.rodata*)
        *(.srodata*)
        *(.srodata.cst*)
        . = ALIGN(4);
    } > DMEM

    .data : {
        __data_start = .;
        *(.sdata*)
        *(.data*)
        __data_end = .;
        . = ALIGN(4);
    } > DMEM

    .bss : {
        __bss_start = .;
        *(.sbss*)
        *(.bss*)
        *(COMMON)
        __bss_end = .;
        . = ALIGN(4);
    } > DMEM

    .stack : {
        . = ALIGN(4);
        __stack_top = ORIGIN(DMEM) + LENGTH(DMEM) - 4;
    } > DMEM

    /DISCARD/ : {
        *(.eh_frame)
        *(.comment)
        *(.note*)
    }
}
