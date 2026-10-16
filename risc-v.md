# RISC-V CPU 项目工作记录（risc-v.md）

> 记录每次工作：时间、工作目标、遇到的问题、解决方法、实验结果、结论与下一步。
> 与 README 的区别：本文是过程日志，README 是项目现状说明。

---

## 2026-10-16（第 1 次工作）

### 工作目标
1. 为「集创赛七星微杯：基于 RISC-V 的高性能 CPU 设计及 FPGA 验证」搭建完整工程。
2. 完成 RV32I 汇编工具链与底层模块，跑通单周期 CPU 仿真（第一步里程碑）。
3. 配置 Git 仓库（github.com/wsthth/RISC-V-CPU），按阶段提交规范代码。

### 环境情况
- Vivado 2019.1 位于 `D:\Xilinx\Vivado\2019.1`（xvlog/xelab/xsim 齐全）。
- Python 3.13 可用；**无 riscv-gcc** → 决定自研 Python 汇编器。
- 本机**未安装 Git** → 用 winget 安装 Git 2.55.0.5。
- Windows 凭据管理器已有 github.com 凭据，HTTPS 推送可用。
- 目标板卡：NetFPGA SUME（XC7VX690TFFG1761-3）、Zynq-7020（ZedBoard，Vivado 自带 zed 板卡文件）。

### 遇到的问题与解决方法
| # | 问题 | 解决方法 |
|---|---|---|
| 1 | 无 riscv-gcc 交叉编译器 | 编写 `tools/riscv_asm.py` 自研 RV32I 汇编器（六种编码格式 + 伪指令 + 标签），输出 hex/lst |
| 2 | 汇编器第一遍布局未计入伪指令展开条数，导致后续标签地址错位 | 增加 `instr_expand_count()`，按 `li`(1/2条)、`call`/`la`(2条) 正确推进 PC |
| 3 | `lui`/`auipc` 立即数被错误右移 12 位 | 修正：RISC-V 语法中立即数直接是 20 位字段值（如 `lui x1,0x12345` → imm=0x12345） |
| 4 | 移位指令（slli/srli/srai）错编成 R 型 | 修正为 I 型编码：funct7 占 imm 高 6 位 |
| 5 | 访存负立即数 `-1(x2)` 无法解析 | 正则允许符号位 |
| 6 | 寄存器别名表误存字符串（`'t0':'x5'` 应为 `5`） | 修正 aliases 为数字（此前 asm_verify 只测 x 名故未暴露） |
| 7 | xelab 不识别 `-work` 选项 | Vivado xelab 用 `-L work` 指定库，修正 run_sim.ps1 |
| 8 | RTL 无 timescale 导致 xelab 报错 | 给全部 RTL 文件添加 `` `timescale 1ns/1ps ``（注意 PowerShell 反引号转义坑） |
| 9 | regfile 未初始化，读未写寄存器为 X | initial 块清零 mem |
| 10 | 若干 TB 期望值手算错误（OR 位序、S/U/J 型构造位宽、lw 合并字节） | 逐项按规范重算修正；dmem/ALU 逻辑本身正确 |

### 实验结果
- **汇编器编码校验**：29/29 用例通过（add/sub/移位/访存/分支/lui/jal/jalr/伪指令全部与 RISC-V 规范机器码一致）。
- **模块级仿真（xsim）全部 PASS**：
  - `tb_alu`（11 种 ALU 操作 + zero 标志）
  - `tb_regfile`（同步写/组合读/x0 硬连 0）
  - `tb_extend`（I/S/B/U/J 五型立即数，含正负边界）
  - `tb_imem`（hex 加载正确）
  - `tb_dmem`（字/半字/字节读写 + 符号扩展 + 未对齐）
- **单周期整机仿真 PASS**：`tb_single` 运行 basic.s（算术/访存/分支循环/jalr 函数调用），56 周期停机，DMEM 10 项结果全部正确。

### 结论
单周期 RV32I 处理器已在仿真层面完全跑通，验证了指令集理解、工具链与仿真流程，
可以作为五级流水线开发的正确性基准（reference model）。

### 下一步
1. 五级流水线主体：IF/ID/EX/MEM/WB + 4 组流水线寄存器，先跑通无冒险指令序列。
2. 冒险处理：旁路转发（EX→EX、MEM→EX）+ Load-Use 停顿 + 分支冲刷。
3. 2-bit 饱和计数器分支预测器 + BTB。
4. 系统级全指令集验证（补充访存边界、立即数边界等测试程序）。
5. FPGA：Vivado 2019.1 TCL 工程脚本 + ZedBoard/SUME 约束 + 上板指南。
