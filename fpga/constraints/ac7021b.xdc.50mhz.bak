# ============================================================================
# AC7021B 约束文件（ALINX AC7021B / AX7021B 核心板，xc7z020clg484-1）
# ----------------------------------------------------------------------------
# 引脚取自 ALINX 官方用户手册（AX7021B_UG.pdf）：
#   - PL 系统时钟 50MHz：Y9（BANK13 MRCC，LVCMOS33）
#   - 用户 LED2（PL 侧）：R7（低电平点亮，阳极接 3.3V）
#   - 复位：PL 侧无复位按键（核心板 RESET 键连 PS_POR_B/B5，PL 用内部上电复位）
# fpga_top 已用 AC7021B 宏适配（LED 数量=1、低电平点亮、无外部复位）。
# ============================================================================

## 时钟：50MHz
set_property PACKAGE_PIN Y9   [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 20.000 -name clk [get_ports clk]

## 用户 LED2（低电平点亮）——顶层端口为标量 led
set_property PACKAGE_PIN R7 [get_ports led]
set_property IOSTANDARD LVCMOS33 [get_ports led]
