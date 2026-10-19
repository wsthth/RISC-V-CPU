/* lib_support.c - RV32I bare-metal 最小 libc 支持
   仅提供 CoreMark 移植需要的 memset/memcpy（ee_printf.c 使用）。
   裸机无 libc，自实现避免引入 newlib（newlib 过大导致 IMEM 溢出）。
   注意：memset/memcpy 使用 volatile 指针，阻止 gcc 14.3 在 -O2 下把
   循环错误转换为"无递减"尾部自递归（会导致死循环）。 */
typedef unsigned int size_t32;

void *
memset(void *s, int c, size_t32 n)
{
    volatile unsigned char *p = (volatile unsigned char *)s;
    size_t32                 i;
    for (i = 0; i < n; i++)
        p[i] = (unsigned char)c;
    return s;
}

void *
memcpy(void *d, const void *s, size_t32 n)
{
    volatile unsigned char *       dst = (volatile unsigned char *)d;
    const volatile unsigned char * src = (const volatile unsigned char *)s;
    size_t32                       i;
    for (i = 0; i < n; i++)
        dst[i] = src[i];
    return d;
}
