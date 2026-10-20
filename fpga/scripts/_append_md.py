# -*- coding: utf-8 -*-
import io
p = r'D:\my_project\RISC-V\risc-v.md'
add = '''
## 8. AC7021B 综合拥塞与 BTB 回退（2026-10-20 追加）

- **问题：v0.15 RTL 综合 AC7021B 布线拥塞**
  - 现象：综合 0 errors，但实现阶段 Router 拥塞（Phase 4.2 Global Iteration 1 单次迭代耗时 31 分钟，
    overlaps 46835 -> 25336 -> 9809 -> 5464，WNS=-1.475），Router 报告
    "Congestion is preventing the router from routing all nets"，被迫终止。
  - 根因排查：对比 v0.6 可综合基线（led.hex，3154 LUT/4 BRAM）与 v0.15 的差异，
    发现 `rtl/pipeline/branch_predictor.v` 仍是 v0.11 试验用的 **1024 项版本**：
    counter(2Kbit) + btb(32Kbit) + tag(20Kbit) ≈ 55Kbit 阵列，会被综合成海量 LUTRAM/FF，
    直接撑爆 Slice 布线。v0.11 当时只做了仿真（结论"无收益"），从未做过综合验证，
    于是把不可综合的配置带进了仓库。
  - 教训：**仿真通过 ≠ 可综合**。任何 RTL 参数改动必须过一遍综合验证再提交。

- **解决：BTB 回退 128 项（v0.15.2）**
  - `branch_predictor.v`：N=128，idx=PC[8:2]（7bit），tag=PC[31:9]（23bit），
    counter/valid/btb 阵列约 7Kbit，回到 v0.6 可综合基线。
  - 重新仿真验证：CoreMark 预测开 **PASS**，cycles=1,153,090（1024 项为 1,152,213，差 0.08%），
    misp=59,859（1024 项 59,431，差 0.7%）——再次确认 v0.11 结论：**128 项与 1024 项性能几乎相同**，
    扩容纯属浪费资源。
  - 恢复 `integer i;` 声明（回退时误删，xvlog 报 "i is not declared"，已补回）。

- **结论**：BTB 128 项是正确配置（性能不损失、资源最小、可综合）。
  AC7021B 以 BTB128 版本重新综合实现，生成新 bit 用于上板。

- **下一步**：
  1. 验证 v0.15.2 综合通过（0 errors）+ 资源统计（<5K LUT）；
  2. 新 bit 下载 AC7021B 复验 LED 闪烁；
  3. CoreMark 上板输出方案（UART TX）与 SUME V7 高主频折算 250/s；
  4. 答辩 PPT。

'''
with io.open(p, 'a', encoding='utf-8', newline='\n') as f:
    f.write(add)
print('appended ok')
