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

---

## 2026-10-16（第 2 次工作：五级流水线）

### 工作目标
1. 完成五级流水线主体：IF/ID/EX/MEM/WB + 4 组流水线寄存器（带 valid 位）。
2. 冒险处理：EX/MEM、MEM/WB 两级旁路转发 + Load-Use 停顿 + 分支/跳转冲刷。
3. 2-bit 饱和计数器分支预测器 + BTB；jalr 目标对齐；MMIO 观察端口。
4. 三组流水线测试（基础 / 数据冒险 / 分支预测）+ 全指令集系统级测试，全部过仿真后提交 Git。

### 新增/修改文件
- 新增 `rtl/pipeline/`：`riscv_pipeline.v`（顶层）、`pipe_regs.v`（4 组流水线寄存器）、`hazard_unit.v`、`forward_unit.v`、`branch_predictor.v`
- 新增 `sim/tb/`：`tb_pipe_basic.v`、`tb_pipe_hazard.v`、`tb_pipe_branch.v`、`tb_pipe_full.v`；调试用 `tb_pipe_debug.v` / `tb_pipe_mem.v` / `tb_pipe_ex.v`
- 新增 `testprog/`：`hazard.s`、`branch.s`、`full.s`
- 修改 `rtl/common/alu.v`：修复 LUI 双重左移（详见问题 #5）

### 遇到的问题与解决方法（含 debug 方法）
| # | 问题 | 现象/定位方法 | 根因 | 解决方法 |
|---|---|---|---|---|
| 1 | xvlog 编译失败：`already implicitly declared` + `procedural assignment to a non-register alucontrol_e` | 编译报错列出具体信号与行号 | 顶层各段信号声明位置混乱：使用处先隐式声明为 net，后续显式声明冲突；`alucontrol_e` 由 `always` 赋值却是 wire | 全部内部信号集中到模块顶部统一声明；`alucontrol_e` 改 `reg [3:0]`。**方法：先列信号清单再写代码，Verilog 隐式声明规则要遵守** |
| 2 | tb_pipe_basic 4 项数据错：blt 循环计数 14（期望 10）、func 内 addi 执行 3 次 | 写 `tb_pipe_debug` 逐周期打印 EX 段（pc/rs/rd/转发/ALU/分支信号） | ① **mispredict 时 PC 无条件取分支目标**：分支实际不跳（taken=0）而预测跳时，错误跳回循环体，导致重复执行 | ① `pcf_next` 在 mispredict 时按**实际方向**取：`branch_taken ? target : pcplus4` |
| 3 | 同上 | 轨迹显示被冲刷指令仍在 EX 执行（valid=1） | ② **IF/ID 的 valid 未门控 ID/EX**：IF/ID 被 flush 后 valid=0，但 ID 段组合译码照常工作，ID/EX 在下一沿把"气泡指令"完整装入（regwrite=1, valid=1），一路写回污染寄存器 | ② ID/EX 的 flush 加上 `~valid_d`：`flushe \| mispredict \| ~valid_d` |
| 4 | 同上 | 轨迹显示 jalr 后 PC 直接跳过 0x78（j done） | ③ **reg_idex 冲刷只清 valid 不清控制信号** + **EX/MEM、MEM/WB 的 valid 恒为 1**：被冲掉指令的 regwrite 残留，且气泡 valid 一路为 1，造成"幽灵写回" | ③ reg_idex 冲刷时控制信号全部清零；reg_exmem/reg_memwb 增加 valid 输入并逐级传递 |
| 5 | tb_pipe_hazard 4 项错：lw 后 addi 结果 = 257（期望 241） | 数据模式分析：257=256+1，256=t0 的值 | ④ **Load 的转发源错误**：转发的是 `alu_result_m`（=地址 0x100=256），而 load 的结果应是 `readdata_m`（内存数据 240） | ④ 转发 mux 的源改为"段结果"：`resultsrc[0] ? readdata : alu_result`（MEM、WB 两段都改） |
| 6 | tb_pipe_full 31 项错（从 lb/lh 段开始全乱） | 监视 MEM 段 dmem 读写（tb_pipe_mem）发现 `we=1 wd=75FFF9AB`；再看 EX 段（tb_pipe_ex）定位 lui 指令 | ⑤ **alu.v 的 LUI 实现 `b << 12` 双重左移**：U 型 immext 已是 `{imm,12'b0}`，再左移溢出截断（0x88776000<<12 = 0x76000000），addi 后成 0x75FFF9AB。单周期没暴露是因为 basic.s 无大立即数 | ⑤ LUI 直接输出 `b`（注释说明 U 型 immext 已预左移）。**方法：逐层缩小——先定"谁写了错误数据"，再定"哪条指令算错"，再查该指令译码/数据通路** |
| 7 | 修复 LUI 后 tb_pipe_full 又出现 13 项错（slt/and/addi 全错） | 数值分析：addi -5 得到 15 = 10+5（-5 变 +5）；slt(-1,1)=0 说明 -1 变 +1 | ⑥ **I 型指令（addi 等）被 EX 段误用 funct7[5] 判定 add/sub**：I 型的 funct7 字段是立即数位（如 -5=0xFFB 的高 6 位 = 0x3F → funct7[5]=1 → 误判 SUB）。只有 R 型才用 funct7[5] | ⑥ ID/EX 增加 opcode 传递，EX 译码仅 `opcode==0110011 && funct7[5]` 判 SUB |
| 8 | tb_pipe_full 剩 2 项错（jal 链接地址差 4） | got 0x1E0 expect 0x1DC | TB 期望值是 full.s 加 `li t4,7` 之前算的旧地址，程序长度变了 | 用最新 lst 核对 jal/jalr 实际地址，更新 TB。**教训：汇编修改后，所有绝对地址期望值都要重新核对 lst** |
| 9 | 分支测试 TB 期望值偏移整体错位 | beq 结果检查到陷阱位置 | 写 TB 时结果区偏移与 full.s 的 sw 偏移没对齐（差 4/8/12 字节） | 按 full.s 逐行核对 sw 偏移，重写 TB 检查段。**方法：以汇编器 lst 为唯一事实来源核对期望表** |

**debug 方法小结（本阶段最有价值的经验）**
1. **分层打印**：写专用调试 TB，用层次引用（`dut.xxx`）逐周期打印某一段（EX/MEM）的关键信号，比猜快得多。
2. **逐层缩小**：先确认"值错在哪"（内存被谁写坏 → 写数据的指令 → 该指令 ALU 输入 → 译码/转发），每层只问一个问题。
3. **数据模式分析**：如 257 = 256+1 立刻暴露"读到了地址而非内存数据"；0x75FFF9AB+0x655=0x76000000 暴露 LUI 结果错。
4. **验证覆盖要广**：单周期 basic.s 没测 lui/lb/lh，导致两个低级 bug 到全指令集测试才暴露。**每类指令都要有正例**。
5. **期望值先核对**：tb_pipe_hazard 里 `0x1F1 & 0xF0` 曾手算成 0xE0（实际 0xF0），先纠正自己再怀疑硬件。

### 实验结果
- `tb_pipe_basic`（basic.s，含分支循环 + la/jalr 函数调用）：**PASS**，74 周期停机。
- `tb_pipe_hazard`（hazard.s，4 级 RAW 转发链 + Load-Use 停顿 + 双 load 依赖）：**PASS**，34 周期。
- `tb_pipe_branch`（branch.s，双循环分支 + 无符号比较 + call/ret）：**PASS**，352 周期。
- `tb_pipe_full`（full.s，全 RV32I 指令集：lui/auipc/R 型算术移位比较逻辑/I 型立即数与立即数移位/全宽度访存/6 种分支/jal/jalr + 陷阱检查）：**PASS**，156 周期。
- 回归：`tb_single`（单周期整机，LUI 修复后重跑）**PASS**，56 周期；`tb_pipe_basic/hazard/branch/full` 全部 **PASS**。
- 修复清单：riscv_pipeline.v（PC 方向、ID/EX flush、load 转发源、I 型 add/sub 误判）、pipe_regs.v（flush 清控制、valid 传递、opcode 传递）、alu.v（LUI）。

**汇编器行为补充**：`li rd, 大立即数` 且低 12 位为 0 时，汇编器只输出 `lui`（省略 `addi rd,rd,0`）——合法优化，
空出的指令槽读 0x00000000（=`lui x0,0`，无副作用 NOP），程序逻辑不受影响（led.s 验证）。

### 结论
五级流水线（转发 + 停顿 + 2-bit 分支预测 + BTB + jalr 对齐 + MMIO）在仿真层面跑通全部测试；
7 个 bug（4 个流水线机制 + 1 个 ALU + 2 个译码）均已修复并有对应测试覆盖，可以作为上板前的基础。
LUI 修复后单周期整机回归通过，两版 CPU 行为一致。

### 下一步
1. 系统级验证：riscv-tests 类更严格的指令/边界测试（访存未对齐、立即数边界、分支全 6 型）。
2. FPGA 工程（进行中）：Vivado 2019.1 TCL 脚本 + NetFPGA SUME（XC7VX690T）与 ZedBoard（xc7z020）约束 + 上板指南 + LED 演示程序。
3. Git 提交 v0.2（流水线 + 仿真全部通过，本地已提交 d7af402，推送因网络失败待重试）。

---

## 2026-10-16（第 3 次工作：FPGA 双板工程）

### 工作目标
1. FPGA 顶层 `fpga_top.v`：CPU + 板载时钟/复位 + MMIO→LED 演示。
2. 双板约束：ZedBoard（xc7z020，官方引脚）+ SUME（XC7VX690T，模板待核对引脚）。
3. 一键 TCL 工程脚本（建工程/加 RTL/复制 hex/综合/实现/比特流）。
4. LED 跑马灯演示程序 led.s；上板指南。

### 遇到的问题与解决方法
| # | 问题 | 现象/定位方法 | 根因 | 解决方法 |
|---|---|---|---|---|
| 10 | Vivado 2019.1 综合报错 `Strategy 'Performance_Explore' is not supported by the flow 'Vivado Synthesis 2019'` | batch 日志直接给出策略名不支持的报错 | Performance_Explore 是旧版综合策略名，2019.1 已改名 | 删除策略设置，用 2019.1 默认综合策略（Performance 影响不大，流水线规模很小） |
| 11 | led.s 汇编后 lst/hex 地址 0x04 与 0x2C 缺失（`li` 大立即数后"少一条"） | 对比 lst 发现 addi rd,rd,0 未生成 | 汇编器对低 12 位为 0 的大立即数省略 addi 0（合法优化） | 确认空槽读 0x00000000=`lui x0,0` 无副作用，程序正确；记录该行为并用于后续测试程序 |
| 12 | 比特流生成时 DRC 报 6 个 LED 端口 UCIO-1（无 LOC）| DRC 列表：led[0,1,3,5,6,7] 未约束而 led[2,4] 有 | **凭记忆写的 ZedBoard LED 引脚（T14/T15/P16...）在 clg484 封装上不存在**，约束静默失败 | 从 Vivado 自带板卡文件（`data/boards/board_files/zed/1.4/part0_pins.xml`）提取官方引脚：LED=T22 T21 U22 U21 V22 W22 U19 U14、时钟 Y9、按钮 P16。**方法：引脚类信息不要凭记忆，直接读板卡文件/原理图** |
| 13 | 综合后 `$readmemh("program.hex")` 报 Critical Warning `could not open`，比特流里 imem 为空 | 日志 Synth 8-4445 | $readmemh 相对路径按**综合进程 cwd** 解析，launch_runs 的 cwd 不是工程目录（脚本在 fpga/scripts 下运行） | TCL 里 `create_project` 后 `cd $proj_dir`，使综合进程 cwd=工程目录（program.hex 已复制在那里）。**方法：上板类 bug 要看综合日志的 Critical Warning，别只看"综合通过"** |

### 实验结果
- `tb_single` 回归 PASS（LUI 修复后单周期不受影响）。
- led.s 汇编通过，机器码正确（13 条指令，含 MMIO 写 + 软件延时循环）。
- ZedBoard：综合/实现/比特流 **成功**（33.333MHz 时序收敛），`fpga_top.bit` 生成。
- SUME（XC7VX690T）：综合冒烟 **通过**（0 errors）；引脚待按原理图核对后出比特流。

### 结论
FPGA 工程骨架可用：顶层复用已验证的 riscv_pipeline，仅需板级 IO 包装；
ZedBoard 引脚已从 Vivado 自带板卡文件核对（不是凭记忆）；
$readmemh 的 cwd 问题已修复（TCL cd 到工程目录），综合不再丢程序。

### 下一步
1. 确认 ZedBoard 修复 $readmemh 后的比特流（无 Critical Warning）。
2. SUME 引脚核对后出比特流（build_sume.tcl）。
3. Git 提交 v0.2（含流水线 + FPGA 工程）+ README/risc-v.md 更新（推送网络恢复后重试）。
4. 系统级验证（riscv-tests 类）作为上板后对照。*

---

## 2026-10-16（第 4 次工作：AC7021B 实机烧录）

### 工作目标
1. 把五级流水线 CPU + LED 跑马灯程序**实际烧录**到实验室 Zynq-7020 板卡，验证"能上板"。
2. 澄清烧录通道（UART vs JTAG）并打通 JTAG 下载全流程。

### 环境情况（重要更正）
- **实验室实际手头板卡 = ALINX AC7021B**（xc7z020clg484-1，工业级），**不是 ZedBoard**、也不是 NetFPGA SUME。
- AC7021B = 核心板 + 底板。烧录通道：
  - **核心板 MINI USB = CP2102N UART 桥**（USB\VID_10C4&PID_EA60）：**只能串口通信，不能配置 FPGA**。
  - **底板 MINI USB = FT232HL USB-JTAG 桥**（USB\VID_0403&PID_6014，被 hw_server 识别为 Digilent cable）：**烧录必须走这里**。
  - 核心板 J1 为 6 针 JTAG 排针（需外接下载器）。
- 板卡 PL 时钟 50MHz（Y9，LVCMOS33）；PL 用户 LED 仅 1 个 LED2（R7，**低电平点亮**，标量端口 led）。
- 启动拨码 SW1：ON,ON=JTAG 模式（烧录后可从 JTAG 启动）。

### 遇到的问题与解决方法（含 debug 过程）
| # | 问题 | 现象/定位方法 | 根因 | 解决方法 |
|---|---|---|---|---|
| 14 | 综合后 `$readmemh("program.hex")` 仍报 `could not open`（第 3 次记录 #13 的 cd 方案在 AC7021B 工程无效） | 日志 Synth 8-4445；`check_pwd.tcl` 显示综合进程 cwd=**fpga/scripts**，但把 hex 复制到 cwd 仍失败 | $readmemh 相对路径**固定按 `<工程>.runs/synth_1` 目录解析**，与综合进程 cwd 无关 | TCL 里 `file mkdir <工程>.runs/synth_1` 并把 program.hex 复制进该目录 → Synth 8-3876 `read successfully`。**方法：先验证假设（cwd）再改，两次都不成立就要换假设（Vivado 的 readmem 目录规则）** |
| 15 | DRC NSTD-1/UCIO-1：端口 `led` 无 IO standard、无 LOC | DRC 报 Problem ports: **led**（不是 led[0]） | AC7021B 顶层端口 `led` 是**标量**（1 位），xdc 写 `[get_ports {led[0]}]` 匹配不到标量 | xdc 改 `[get_ports led]` + PACKAGE_PIN R7 / IOSTANDARD LVCMOS33 |
| 16 | 烧录脚本 `$argv` 收不到 `-tclargs` 且一度 BITSTREAM NOT FOUND | batch 日志 `ARGS: `（空）；`file exists` 又失败 | ① Vivado batch 模式 `-tclargs` 传参在 vivado.bat 下不可靠；② 日志行号与脚本对不上暴露**跑了旧文件**（Edit 落盘与执行有先后，需以最新 Read 为准） | 脚本内置默认 bit 路径（无参时烧 AC7021B 比特流），并保留 argv 覆盖；每次跑前 Read 确认脚本版本 |
| 17 | `open_hw_manager` 报 `invalid command name` | batch 直接报命令不存在 | **Vivado 2019.1 的硬件管理器命令是 `open_hw`**（2020.x+ 才叫 open_hw_manager） | 改 `open_hw` |
| 18 | hw_server 连上（TCP:localhost:3121）但 `open_hw_target` 报 no current hw_target | 系统 USB 设备列表：只有 CP2102N（UART，Status=Error），**无 FT232HL** | **插的是 UART 口**；UART 桥不连 JTAG，hw_server 自然看不到 target | 向用户解释 UART≠JTAG，请改插底板 FT232HL MINI USB 口 |
| 19 | 换插后 FT232H 被识别（VID_0403&PID_6014），但 `open_hw_target` 后 **No matching hw_devices**（JTAG 链空） | hw_diag 日志：target 存在（Digilent/210512180081）但 DEVICES 空 | FT232H 枚举/驱动就绪需要时间，或首次扫描过早 | hw_diag 加 `refresh_hw_server` + 4 次 `refresh_hw_target` 重扫（间隔 800ms）→ TRY0 即读到 `arm_dap_0 xc7z020_1` |
| 20 | 烧录脚本 `current_hw_device [lindex [get_hw_devices] 0]` 会选中 **arm_dap_0（ARM 调试口）而非 FPGA** | 日志 DEVICES=arm_dap_0 xc7z020_1 | Zynq JTAG 链有 2 个设备，第一个是 ARM DAP | 遍历设备按 `get_property PART` 匹配 `xc7z*` 选 FPGA，跳过 arm_dap |

**debug 方法补充（本阶段新增）**
1. **物理层先于软件层**：烧录失败先查"设备管理器有没有对应 USB 设备 / 状态是否 OK"，再查 hw_server——这次就是靠 `Get-PnpDevice` 一次性分清 UART(CP2102N) 与 JTAG(FT232H) 两个通道。
2. **板卡资料是唯一事实来源**：AC7021B 引脚/烧录通道以官方手册（AX7021B_UG.pdf）为准，手册说 UART 不能烧录就不要跟用户"感觉能烧"纠缠，用探测结果说话。
3. **综合类问题看 Critical Warning**：`Synth 8-4445` 一句就定位 readmem 失败；不要只看"综合 0 errors"。
4. **TCL 脚本用默认值兜底**：batch 模式传参不可靠时，脚本内置默认路径，交互模式仍可传参覆盖。

### 实验结果
- **AC7021B 实机烧录成功**：hw_server 检测到 `Digilent/210512180081`（FT232H），JTAG 链读到 `arm_dap_0 xc7z020_1`，选中 `xc7z020_1`（PART=xc7z020），`program_hw_devices` 完成，日志 `=== PROGRAMMING DONE ===`。
- 烧录的比特流 `fpga_top_ac7021b.bit`（4,045,676 字节）：五级流水线 CPU + led.s 跑马灯程序（$readmemh 已确认读入，Synth 8-3876）。
- 板卡 LED2（R7，低电平点亮）应随跑马灯程序**周期闪烁**（跑马灯 8 位循环取最低位接 LED，软件延时控制频率）。

### 结论
五级流水线 CPU 已在**真实 Zynq-7020 板卡（AC7021B）上运行**——仿真→综合→实现→比特流→JTAG 烧录全链路打通；
"USB 转串口能烧录"的说法不成立（CP2102N 只做 UART），实际靠底板 FT232HL USB-JTAG 口完成配置；
Zynq JTAG 链包含 ARM DAP + FPGA 两个设备，烧录必须显式选中 xc7z020。

### 下一步
1. **请用户观察 AC7021B LED2 是否闪烁**——确认程序在板子上实际执行（肉眼验证）。
2. ZedBoard 比特流用修复后脚本重生成（readmem 已烧入），作为第二块板备选。
3. SUME（XC7VX690T）引脚按原理图核对后出比特流——满足"双板上板"。
4. Git 提交：v0.2（流水线 d7af402）+ FPGA 工程 + 本次上板记录（推送重试）。
5. 系统级验证（riscv-tests 类）作为上板后对照。


