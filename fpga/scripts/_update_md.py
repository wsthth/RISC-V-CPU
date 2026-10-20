# -*- coding: utf-8 -*-
import io
p = r'D:\my_project\RISC-V\risc-v.md'
old = '''- **结论**：BTB 128 项是正确配置（性能不损失、资源最小、可综合）。
  AC7021B 以 BTB128 版本重新综合实现，生成新 bit 用于上板。

- **下一步**：
  1. 验证 v0.15.2 综合通过（0 errors）+ 资源统计（<5K LUT）；
  2. 新 bit 下载 AC7021B 复验 LED 闪烁；
  3. CoreMark 上板输出方案（UART TX）与 SUME V7 高主频折算 250/s；
  4. 答辩 PPT。
'''
new = '''- **结论**：BTB 128 项是正确配置（性能不损失、资源最小、可综合）。
  AC7021B 以 BTB128 版本重新综合实现，生成新 bit 用于上板。

- **v0.15.2 综合验证结果（2026-10-20 重跑）**：
  - `build_ac7021b.tcl` 一键重建工程 + 综合 + 实现 + bitstream：**BUILD OK**；
  - 布线成功（不再拥塞），实现 **WNS=0.886** 时序收敛（clk 约束照旧）；
  - 资源统计：**Slice LUT 4141（7.78%）< 5K ✓，Slice Reg 8256，Block RAM Tile 4（2.86%）**；
  - bit 文件：`fpga/vivado_ac7021b/riscv_ac7021b.runs/impl_1/fpga_top_ac7021b.bit`（约 4MB）。

- **下一步**：
  1. 新 bit 下载 AC7021B 复验 LED 闪烁；
  2. CoreMark 上板输出方案（UART TX）与 SUME V7 高主频折算 250/s；
  3. 答辩 PPT。
'''
with io.open(p, 'r', encoding='utf-8') as f:
    c = f.read()
assert old in c, 'anchor not found'
c = c.replace(old, new)
with io.open(p, 'w', encoding='utf-8', newline='\n') as f:
    f.write(c)
print('updated ok')
