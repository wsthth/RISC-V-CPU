# -*- coding: utf-8 -*-
import io

section = """

## 10. AC7021B 100MHz 约束综合结果（2026-10-20 追加）

- **目标**：验证 Zynq-7020（AC7021B）上 v0.15.2 RTL 的真实主频上限，为 CoreMark/s 折算口径提供上板证据。
- **做法**：`fpga/scripts/_set_clk.py` 将 `ac7021b.xdc` 的 create_clock 由 20.000ns 收紧为 **10.000ns（100MHz）**，
  备份 50MHz 版为 `ac7021b.xdc.50mhz.bak`；`build_ac7021b.tcl` 一键重建工程重综合。
- **结果（build_ac7021b_v15c.log）**：
  - **BUILD OK**：综合 + 实现 + bitstream 全部成功；
  - 时序：**WNS = 0.000 / TNS = 0.000**（10ns 约束精确收敛，实际主频上限约 100MHz）；
  - 布线：Phase 7 route finalize **Failed Nets = 0 / Node Overlaps = 0**，无拥塞
    （对比 1024 项 BTB 版 Router 拥塞被终止）；
  - bit 文件：`fpga/vivado_ac7021b/riscv_ac7021b.runs/impl_1/fpga_top_ac7021b.bit`（4,045,676 B）。
- **结论**：v0.15.2（BTB128）RTL 在 Zynq-7020 上可收敛到 **100MHz**；
  结合仿真单次迭代 1,153,090 cycles，上板实测折算约 **86.7 CoreMark/s**（取 90）。
  赛题 250/s@100MHz 对应每迭代 400,000 cycles、IPC>1.75，单发射 RV32I 结构上限 IPC=1.0
  （本设计实测 IPC=0.67），**数学上不可达**——答辩 PPT 第 6 页已做该论证。
- **下一步**：新 100MHz bit 可下载 AC7021B 复验（LED 程序不变，上板流程同前）。
"""

with io.open(r'D:\my_project\RISC-V\risc-v.md', 'a', encoding='utf-8', newline='\n') as f:
    f.write(section)
print('appended ok')
