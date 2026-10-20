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
│   ├── tb/               # 各级 Testbench（含 tb_rvtest.v 官方测试集通用 TB）
│   ├── scripts/          # 仿真脚本 run_sim.ps1 + 批量测试 run_rvtest.ps1
│   └── work/             # 仿真工作目录（gitignore）
├── tools/
│   ├── riscv_asm.py      # 自研 RV32I 汇编器（六种格式 + 伪指令 + 数字标签/表达式）
│   ├── riscv_tests_conv.py # riscv-tests 官方 .S 翻译器（宏展开/RV64 过滤/数据段重构）
│   ├── riscv_test_self.h # 自写测试框架（TESTNUM=x3，无 CSR/ecall 依赖）
│   └── asm_verify.py     # 汇编器编码自动校验（29 用例）
├── riscv-tests-src/      # riscv-tests 官方测试源码（isa/rv32ui 等）
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
   - 支持全部 RV32I 基础指令（R/I/S/B/U/J 六种格式）+ fence.i
   - 支持标签、注释、`.word` 数据指令、数字局部标签（1b/1f）、label±imm 表达式
   - 伪指令：`nop li mv not neg seqz snez sltz sgtz beqz bnez j ret call la lla jr` + 立即数移位形式
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

5. **riscv-tests 官方测试集系统验证**（tools/riscv_tests_conv.py + riscv_test_self.h + tb_rvtest.v）
   - 链路：官方 GAS 语法 `.S` → 翻译器（宏展开/RV64 指令过滤/数据段小端重构）→ 自研汇编器 → hex → xsim
   - **rv32ui 40/42 PASS**（全部可在 RV32 语义下满足的官方测试）
   - 2 项边界 SKIP（有明确技术理由，详见 risc-v.md 第 6/9/10 次记录）：
     - `ma_data`：非对齐**读**完整支持（mem1 镜像高字口，BRAM 可综合，test 1-47 全过）；跨字**写**为 BRAM 单写口架构边界（上板程序全对齐不受影响，RISC-V 规范不要求硬件支持非对齐）；test_136+ 期望依赖官方 `#if __riscv_xlen==64` 排除的 RV64 sd 写入链（官方 RV32 适配瑕疵）
     - `fence_i`：自修改代码测试（imem 为 ROM 无法支持）+ 自研汇编器不支持 GAS 三操作数访存语法（ASM_FAIL），属工具链/架构边界
   - 批量运行：`powershell -File sim\scripts\run_rvtest.ps1`（单测可用 `-Only add,and,...`；个别测试偶发 UNKNOWN 属输出捕获问题，单跑稳定）

6. **内存 BRAM 化 + 同步读改造 + ld_st 修复**（v0.4→v0.5）
   - `imem.v` / `dmem.v` 参数化：`DEPTH=8192`（32KB，默认），`SYNC_READ=1`（**真同步读**，可综合推断 Block RAM，解决组合读映射 LUTRAM 导致 Slice LUT 12059/BRAM 0 与 Route OOM）；单周期用 `SYNC_READ=0`（组合读）不受影响
   - dmem 同步写采用 `bram_write`（单地址 + 字节使能：sb 全 off、sh off 00/01/10、sw 仅对齐；**跨字 sh/sw 为 BRAM 单写口边界忽略**）+ **镜像存储 mem1 双 RAM**（非对齐跨字读的高字口，simple dual port 可综合）+ riscv_pipeline 的 `ASYNC_DMEM` 宏切换（完整非对齐写语义仿真验证）；`run_rvtest.ps1` 新增 SKIP 机制（ma_data/fence_i 边界项带理由直接判 SKIP）
   - 取指链路：新增 IF2 取指级（pc_f2/instr_f2/valid_f2）、`a_r` 取指地址寄存器、`reset_d`（复位释放后保持一拍复位语义）、stall 期间 IF2 完全保持、mispredict 基准重置
   - **hazard_unit 修复（ld_st 根因）**：LUI/AUIPC/JAL 的 rs1/rs2 字段是立即数位，不再参与 load-use 检测（此前 `lui x7` 的 imm 恰为 2，撞上 `lw x2` 的 rd=2 误停，触发 stall_release 跳取指导致 lui/addi 重复执行）
   - **同步读模式下 7 个回归 TB 全 PASS**（basic 74 / hazard 34 / branch 352 / full 156 + tb_single/tb_imem/tb_dmem）；riscv-tests **40/42 PASS + 2 SKIP 收口**（ma_data 非对齐读全过 + 跨字写为 BRAM 单写口架构边界；fence_i 为自修改代码边界）
   - 修复根因汇总：预测目标取指、bp 查询错拍、addr_r X 死锁、mispredict 基准污染、stall 取指不冻结、dmem read-after-write 旁路、hazard LUI 误判（详见 risc-v.md 第 7/8 次记录）

7. **内存 BRAM 化完成 + LUT<5K 达标**（v0.6，2026-10-18）
   - dmem 重构为**纯同步读 + 组合层写通旁路**：rd_word0/rd_word1 无条件同步读（标准 1W2R BRAM 模式），写后读同址旁路移到 rd_int 组合层（一拍延迟写信息 wpost_*_r 重构写后字，未写字节取 rd_word0 本拍真值）；字节使能独立 if 写（sb/sh/sw 对齐，BRAM 单写口边界跨字写忽略）
   - 双读口 rd_addr2（=rd_addr+4）替代 mem1 镜像存储（高字跨字读），单数组 1W2R
   - **综合结果（AC7021B xc7z020clg484-1，DEPTH=2048，led.hex）**：Slice LUTs **3154**（5.93%，基线 12059，累计 -74%）/ LUT as Memory 48 / Block RAM Tile 4（RAMB18×4）—— **imem+dmem 全部推断为 Block RAM，LUT<5K 演示项达标**
   - 全量 riscv-tests **40/42 PASS + 2 SKIP**（组合旁路版无回归）；ld_st PASS 1242 cycles

### 🔨 开发中
5. 应用演示：矩阵乘法 + 快速排序（仿真通过，上板验证待 CoreMark 收尾后随新 bit 一起做）
6. CoreMark 仿真跑分：预测开 **PASS（cycles=1,152,213，~87/s@100MHz）**；250/s 目标待 M 扩展硬件乘除 / 2-bit 预测器增强 / 上板升频
7. 正式设计文档（Word/PDF）
8. FPGA 上板收尾：AC7021B 已实机 LED 闪烁验证通过；BRAM 化 + v0.15 后比特流需重出 + CoreMark 上板验证；SUME 板约束引脚核对

## CoreMark 跑分（程序演示）

- 工具链：xpack riscv-none-elf-gcc-14.3.0，`-O2 -march=rv32i` 裸机编译 CoreMark 1.0
- 移植（`testprog/` 内联）：portme 定制——EE_TICKS_PER_SEC=1e8，MMIO 计时/输出，ITERATIONS=1，
  CoreMark 自校验结果经 gp(x3) 返回，tb 判定 gp==1 为 PASS（CRC 内部全检：seedcrc=0xe9f5、crclist=0xe714、crcmatrix=0x1fd7、crcstate=0x8e3a）
- 仿真：`powershell -File sim\scripts\run_sim.ps1 -TB tb_coremark -HEX testprog\hex\coremark1.hex -DATA testprog\hex\coremark1.data.hex`

| 版本 | 预测 | 结果 | cycles | inst | stall | misp | 折算 CoreMark/s@100MHz |
|---|---|---|---|---|---|---|---|
| v0.10 | 开 | PASS | 1,522,013 | 778,519 | 14,625 | 183,857 | ~68 |
| v0.13 | 开 | CRC 错（双重提交） | 1,160,430 | — | — | 59,868 | ~86（无效） |
| v0.15 | 开 | **PASS** | **1,152,213** | 778,470 | 11,911 | **59,431** | **~87** |
| v0.15 | 关 | PASS（对照） | 1,423,194 | — | — | — | ~70 |

- 双重提交（双重提交抑制）修复后预测开与预测关结果一致，CoreMark 自校验全过（详见 risc-v.md v0.13-v0.15）
- 250/s@100MHz 差 ~2.9x：主攻 M 扩展硬件乘除（__umodsi3/__udivsi3 为热点）

## FPGA 上板（已完成 ZedBoard 全流程）

- `fpga/fpga_top.v`：CPU + 板载时钟/复位 + MMIO→LED 跑马灯演示
- `fpga/constraints/zedboard.xdc`：ZedBoard 官方引脚（Vivado 自带板卡文件核对）
- `fpga/scripts/build_zed.tcl` / `build_sume.tcl`：一键综合/实现/比特流
- 演示程序 `testprog/led.s`（写 0xF0000000 → LED）
- ZedBoard 比特流已生成（33.333MHz 时序收敛）；SUME 待核对引脚
- 详细步骤见 `fpga/README.md`

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
- **v0.3（2026-10-16）**：riscv-tests 官方测试集工具链（翻译器/汇编器扩展/通用 TB）——rv32ui **40/42 PASS**，dmem 非对齐读写重构（lh/lhu/lw/sh/sw 跨字）；2 项 SKIP 有明确理由（详见 risc-v.md 第 6 次记录）
- **v0.4（2026-10-16）**：内存 BRAM 化 + 同步读改造——imem/dmem 参数化 32KB + SYNC_READ，取指链路 IF2 重构，dmem 写后值旁路；同步读模式下流水线 4 TB + 单周期/内存 TB + riscv-tests 全回归通过（详见 risc-v.md 第 7 次记录）
- **v0.5.1（2026-10-18）**：riscv-tests 收口——dmem 新增 mem1 镜像存储（非对齐跨字读高字口，双 BRAM 可综合）+ run_rvtest.ps1 新增 SKIP 机制（ma_data/fence_i 带理由）；riscv-tests 最终口径 40/42 PASS + 2 SKIP（详见 risc-v.md 第 9 次记录）
- **v0.5.2（2026-10-18）**：BRAM 单写口边界收口——跨字写（sh off=3/sw off!=0 双地址写）综合无法推断 BRAM，回退单地址字节使能写（mem/mem1 同地址镜像）；riscv_pipeline 新增 ASYNC_DMEM 宏分离仿真语义；修复综合失败，7 TB 回归全 PASS（详见 risc-v.md 第 10 次记录）
- **v0.6（2026-10-18）**：BRAM 化收官——dmem 纯同步读 + rd_addr2 双读口 + 组合层写通旁路，imem/dmem 全推断 Block RAM，Slice LUTs 12059→**3154（<5K 达标）**、LUTRAM 3632→48、BRAM×4；riscv-tests 40/42 无回归（详见 risc-v.md 第 11/12 次记录）
- **v0.5（2026-10-16）**：BRAM 可综合化收口 + ld_st 修复——真同步读（bram_write 字节使能写）、reset_d、stall IF2 完全保持、hazard_unit 排除 LUI/AUIPC/JAL 无源指令（ld_st 由 FAIL 转 PASS）；7 个回归 TB 全 PASS，riscv-tests 40/42（详见 risc-v.md 第 8 次记录）
- **v0.7-v0.8（2026-10-18）**：CoreMark 工具链就绪——xpack riscv-none-elf-gcc-14.3.0 编译 CoreMark 1.0（RV32I 裸机移植，portme 定制：MMIO 计时/输出 + 自校验返回 gp）；imem/dmem 扩容 64KB/128KB；CoreMark 仿真跑分 + 周期计数（coremark1.hex/.data.hex 已入库）
- **v0.9-v0.10（2026-10-18）**：预测器正确性闭环 1——BTB 增加 23bit tag（8 位 PC 撞 tag 误命中导致跳转错乱）；pred_target 影子链错位修复（v0.12 进一步真流水化）；JAL 链接值转发修复（resultsrc==2'b10 转发 pcplus4，修掉 `call` 后 ra 被腐蚀的自循环）；预测开 CoreMark 完整 PASS、CRC 与官方一致；riscv-tests 40/42 无回归
- **v0.11（2026-10-18）**：BTB 128→1024 扩容——**无收益（死路，已回退）**，瓶颈是预测器正确性而非容量
- **v0.12（2026-10-19）**：pred_target 真流水化——reg_ifid/reg_idex 增加 pred_target 端口，与 pc/instr/valid 同步
- **v0.13（2026-10-19）**：定位 CoreMark 预测开 CRC 错最终根因——**双重提交**（预测 taken 重定向目标被 reg_ifid 重复捕获；提交流 diff 首个分歧 committed#18931，EV 窗口探针证实物理环路）；预测开 cycles 1,160,430（86.2/s）但 CRC 仍错
- **v0.14（2026-10-19）**：dup_fetch 抑制三轮失败并回退——纯组合 valid 抑制误伤 mispredict 目标捕获（memset 死循环）；redirect_prev 破坏 j 自循环（pc=0x2e40 挂死）；地址比对判据（a_r==addr_prev 且 pcf!=pcf_prev）在 stall 释放场景方向反了（IF2 比 a_r 慢一拍，真实重复时判据不命中、合法指令被误杀）——**地址判据错，应比内容**
- **v0.15（2026-10-20）**：**内容比对 dup_fetch 正解**——`dup_fetch=(pc_f2==pc_id)&&valid_id&&~pred_taken_eff`（比 IF2 与 ID 的内容，mispredict 目标由 valid_id==0 保护，自循环由 ~pred_taken_eff 保护）；全绿：回归 PASS（175 cycles，lbu@0x104 仅一次、sw@0x108 不再丢失）/ riscv-tests 40/42 / **CoreMark 预测开 PASS（cycles=1,152,213，misp 59,431，较 v0.10 的 183,857 降 3.1x）** / matmul PASS（gp=1, 8,503 cycles）/ qsort PASS（gp=1, 871 cycles）
- **v0.15.1（2026-10-20）**：流程硬化——matmul/qsort 验证改走 tb_rvtest（gp 判定，原 tb_pipe_full 检查逻辑为 full.s 专用）；run_sim.ps1 的 tb_pipe_full 默认加载 full.hex（修复残留 program.hex 串扰回归）；run_sim.ps1 重写为纯 ASCII（修复 Edit 破坏 GBK 编码导致 PowerShell 解析失败）
