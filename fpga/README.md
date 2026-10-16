# FPGA 上板指南（NetFPGA SUME / ZedBoard）

本文档说明如何把五级流水线 RISC-V CPU 综合到两块板卡并烧录运行。

## 目录

```
fpga/
├── fpga_top.v            # FPGA 顶层：CPU + 时钟/复位 + MMIO→LED
├── constraints/
│   ├── zedboard.xdc      # ZedBoard 引脚约束（33.333MHz 时钟、BTNC 复位、LED0-7）
│   └── sume.xdc          # SUME 约束模板（引脚需按原理图核对）
├── scripts/
│   ├── build_zed.tcl     # ZedBoard 一键综合/实现/比特流
│   └── build_sume.tcl    # SUME 一键综合/实现/比特流
└── vivado_zed/           # （运行脚本后生成）ZedBoard Vivado 工程
```

## 演示程序

`testprog/led.s` → `testprog/hex/led.hex`：向 MMIO 端口 `0xF0000000` 写值，
FPGA 顶层把低 8 位送到板载 LED，实现 1→2→4→…→128 跑马灯循环（带软件延时）。

上板现象：**复位后 LED 依次左移循环闪烁**。

## 一、ZedBoard（xc7z020clg484-1）

### 1. 建工程 + 综合 + 实现 + 比特流

```powershell
cd D:\my_project\RISC-V\fpga\scripts
D:\Xilinx\Vivado\2019.1\bin\vivado.bat -mode batch -source build_zed.tcl
```

产物：`fpga\vivado_zed\riscv_zed.runs\impl_1\fpga_top.bit`

### 2. 烧录

- 方式 A（Vivado 硬件管理器）：打开 Hardware Manager → Open Target → Program Device，
  选择 `riscv_zed.bit`，下载。
- 方式 B（JTAG 命令行）：

```tcl
open_hw_manager
connect_hw_server
open_hw_target
set_property PROGRAM.FILE {D:/my_project/RISC-V/fpga/vivado_zed/riscv_zed.runs/impl_1/fpga_top.bit} [current_hw_device]
program_hw_devices [current_hw_device]
```

### 3. 操作

1. 上电连接 JTAG；
2. Program Device 烧入比特流；
3. 按下中心按钮 BTNC（复位，高有效）释放后，LED0..LED7 开始跑马灯。

### 4. 时钟与引脚说明（已写入 zedboard.xdc）

引脚取自 **Vivado 2019.1 自带 ZedBoard 板卡文件**（`data/boards/board_files/zed/1.4/part0_pins.xml`）：

| 信号 | 引脚 | 电平 | 说明 |
|---|---|---|---|
| clk | Y9 | LVCMOS33 | PL 系统时钟 33.333MHz |
| btn_rst | P16 | LVCMOS25 | 中心按钮 BTNC（btns_5bits_tri_i_0），按下=高=复位 |
| led[0..7] | T22 T21 U22 U21 V22 W22 U19 U14 | LVCMOS33 | LD0..LD7 |

## 二、NetFPGA SUME（XC7VX690TFFG1761-3）

### 1. 说明

SUME 不是 Vivado 自带板卡，`build_sume.tcl` 直接按器件建工程。
**`sume.xdc` 中的引脚（时钟/复位/LED）需要先按手头 SUME 原理图核对填写**，
核对后删掉 TODO 注释即可。

### 2. 建工程 + 综合 + 实现 + 比特流

```powershell
cd D:\my_project\RISC-V\fpga\scripts
D:\Xilinx\Vivado\2019.1\bin\vivado.bat -mode batch -source build_sume.tcl
```

产物：`fpga\vivado_sume\riscv_sume.runs\impl_1\fpga_top.bit`

> 上板前可先跑综合冒烟（不要求引脚）：
> `vivado.bat -mode batch -source fpga\scripts\synth_sume_check.tcl`

### 3. 烧录与操作

与 ZedBoard 相同（Open Hardware Target → Program Device）。
注意 SUME 通过 PCIe 供电 + JTAG（Xilinx USB Cable 或板载 JTAG 口）连接。

## 三、更换演示程序

1. 修改 `testprog/led.s`（或新建 `.s`）；
2. 汇编：`python tools\riscv_asm.py testprog\led.s testprog\hex`；
3. 重新运行 build_*.tcl（脚本会自动复制最新 `led.hex` 到工程目录作为 `program.hex`）。

> `imem.v` 用 `$readmemh("program.hex", ...)` 加载指令，综合时文件必须存在于
> Vivado 工程目录（脚本已自动复制）。
