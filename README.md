# RISC-V CPU —— 五级流水线处理器设计与 FPGA 验证

> 集创赛七星微杯「基于 RISC-V 的高性能 CPU 设计及 FPGA 验证」项目
> 教材：《数字设计和计算机体系结构 RISC-V 版》（第 6、7 章）

## 项目简介

本项目从零设计并实现一个 **RV32I 五级流水线 RISC-V 处理器**，采用 Verilog 编写，
逐步完成：

- 底层模块库（ALU / 寄存器堆 / 立即数扩展 / 多路选择器 / 指令与数据内存 / 分支判定单元）
- **单周期 RV32I CPU**（先行验证指令集理解，已仿真通过）
- **五级流水线**（IF / ID / EX / MEM / WB）
- **冒险处理**：数据旁路转发（Forwarding）、加载-使用停顿（Load-Use Stall）、分支冲刷（Flush）
- **高性能优化**：2-bit 饱和计数器分支预测器 + BTB（分支目标缓冲）
- 系统级验证：全 RV32I 指令集测试程序
- FPGA 验证：NetFPGA SUME（XC7VX690T）与 Zynq-7020（ZedBoard）双板上板支持

开发环境：**Vivado 2019.1**（仿真：xsim；综合实现：Vivado），Verilog-2001。

## 目录结构

```
RISC-V/
├── rtl/
│   ├── common/           # 底层通用模块（两版 CPU 共用）
│   │   ├── alu.v         #   算术逻辑单元
│   │   ├── regfile.v     #   32x32 寄存器堆（x0 硬连 0）
│   │   ├── extend.v      #   立即数扩展（I/S/B/U/J 五型）
│   │   ├── muxes.v       #   参数化 2/3/4 选 1 多路选择器
│   │   ├── flopr.v       #   带复位触发器（PC）
│   │   ├── imem.v        #   指令内存（$readmemh 加载 hex）
│   │   ├── dmem.v        #   数据内存（支持 lb/lh/lw/lbu/lhu/sb/sh/sw）
│   │   └── branch_unit.v #   分支条件判定（beq/bne/blt/bge/bltu/bgeu）
│   ├── single_cycle/     # 单周期 RV32I CPU（第 7 章教材结构）
│   │   ├── control_unit.v
│   │   └── riscv_single.v
│   └── pipeline/         # 五级流水线 CPU（已仿真通过）
│       ├── riscv_pipeline.v  # 顶层：IF/ID/EX/MEM/WB + 冒险/预测/MMIO
│       ├── pipe_regs.v       # 4 组流水线寄存器（带 valid/flush）
│       ├── hazard_unit.v     # Load-Use 检测（停顿/冒泡）
│       ├── forward_unit.v    # 两级旁路转发
│       └── branch_predictor.v# 2-bit 饱和计数器 + BTB
├── sim/
│   ├── tb/               # 各级 Testbench
│   ├── scripts/          # 仿真脚本 run_sim.ps1
│   └── work/             # 仿真工作目录（gitignore）
├── tools/
│   ├── riscv_asm.py      # 自研 RV32I 汇编器（六种格式 + 伪指令）
│   └── asm_verify.py     # 汇编器编码自动校验（29 用例）
├── testprog/             # 测试汇编程序 + 生成的 hex/lst
│   ├── basic.s           # 基础功能测试（单周期/流水线通用）
│   ├── hazard.s          # 数据冒险测试（转发链 + Load-Use）
│   ├── branch.s          # 分支/预测器测试（循环 + call/ret）
│   ├── full.s            # RV32I 全指令集系统级测试
│   └── hex/              # 汇编产物
├── fpga/                 # FPGA 工程脚本与约束（开发中）
└── docs/                 # 设计文档
```

## 已实现内容（进度）

### ✅ 已完成
1. **RV32I 汇编器**（tools/riscv_asm.py）
   - 支持全部 RV32I 基础指令（R/I/S/B/U/J 六种格式）
   - 支持标签、注释、`.word` 数据指令
   - 伪指令：`nop li mv not neg seqz snez sltz sgtz beqz bnez j ret call la`
   - 输出 `.hex`（内存加载）与 `.lst`（带地址清单）
   - 编码自动校验 29 用例全部通过（与 RISC-V 规范逐位核对）

2. **底层模块库**（rtl/common/）
   - 每个模块独立 Testbench，xsim 仿真全部通过：
     `tb_alu` / `tb_regfile` / `tb_extend` / `tb_imem` / `tb_dmem`

3. **单周期 RV32I CPU**（rtl/single_cycle/）
   - 完整数据通路 + 主译码器 + ALU 译码器
   - 支持 RV32I 整数指令全集（含 jalr 目标对齐、字节/半字访存）
   - 整机测试 `tb_single` 运行 basic.s：**56 周期跑通，10 项检查全部通过**

4. **五级流水线 CPU**（rtl/pipeline/）
   - IF/ID/EX/MEM/WB + 4 组流水线寄存器（带 valid 位、flush 清控制）
   - 数据冒险：EX/MEM 与 MEM/WB 两级旁路转发（load 转发内存读数据）+ Load-Use 停顿
   - 控制冒险：2-bit 饱和计数器分支预测 + BTB；分支/跳转在 EX 解析，预测错误冲刷两级
   - jal/jalr 在 EX 解析，jalr 目标低 1 位清零（RISC-V 规范）；MMIO 观察端口（0xFxxxxxxx 写输出）
   - 整机测试全部通过：
     - `tb_pipe_basic`（74 周期）/ `tb_pipe_hazard`（34 周期）/ `tb_pipe_branch`（352 周期）
     - `tb_pipe_full`（全 RV32I 指令集 + 陷阱检查，156 周期）

### 🔨 开发中
5. 系统级更严格验证（访存未对齐、立即数边界等）
6. FPGA 双板工程与上板（NetFPGA SUME + ZedBoard）

## 如何仿真（Vivado 2019.1）

```powershell
# 1) 汇编测试程序 -> hex
python tools\riscv_asm.py testprog\basic.s testprog\hex

# 2) 跑模块级 TB
powershell -File sim\scripts\run_sim.ps1 -TB tb_alu
powershell -File sim\scripts\run_sim.ps1 -TB tb_regfile

# 3) 跑单周期整机（需加载 hex）
powershell -File sim\scripts\run_sim.ps1 -TB tb_single -HEX testprog\hex\basic.hex

# 4) 跑流水线整机（basic / hazard / branch / full 四套测试）
powershell -File sim\scripts\run_sim.ps1 -TB tb_pipe_basic  -HEX testprog\hex\basic.hex
powershell -File sim\scripts\run_sim.ps1 -TB tb_pipe_hazard -HEX testprog\hex\hazard.hex
powershell -File sim\scripts\run_sim.ps1 -TB tb_pipe_branch -HEX testprog\hex\branch.hex
powershell -File sim\scripts\run_sim.ps1 -TB tb_pipe_full   -HEX testprog\hex\full.hex

# 5) 输出波形（生成 waves.vcd，可用 xsim/GTKWave 查看）
powershell -File sim\scripts\run_sim.ps1 -TB tb_single -HEX testprog\hex\basic.hex -Wave
```

所有 TB 结束时打印 `TEST PASSED` / `TEST FAILED`，脚本退出码 0/1 对应结果。

## 环境依赖

| 组件 | 版本 | 路径（本机） |
|---|---|---|
| Vivado | 2019.1 | D:\Xilinx\Vivado\2019.1 |
| Python | 3.13+ | 汇编器/校验脚本 |
| Git | 2.x | 版本管理 |

## 版本记录

- **v0.1（2026-10-16）**：汇编器 + 底层模块 + 单周期 CPU，全部仿真通过
- **v0.2（2026-10-16）**：五级流水线（转发/停顿/2-bit 分支预测 + BTB/jalr 对齐/MMIO）+ 冒险与全指令集测试，全部仿真通过；修复 7 个 bug（详见 risc-v.md）
