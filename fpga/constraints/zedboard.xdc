# ============================================================================
# ZedBoard 约束文件（xc7z020clg484-1）
# ----------------------------------------------------------------------------
# 引脚取自 Vivado 2019.1 自带 ZedBoard 板卡文件
#   (D:\Xilinx\Vivado\2019.1\data\boards\board_files\zed\1.4\part0_pins.xml)：
#   - 系统时钟 sys_clk 33.333MHz：Y9（LVCMOS33）
#   - 按钮 btns_5bits_tri_i_0（BTNC 中心键，按下=高）：P16（LVCMOS25）
#   - LED0..LED7：T22 T21 U22 U21 V22 W22 U19 U14（LVCMOS33）
# ============================================================================

## 时钟：33.333MHz
set_property PACKAGE_PIN Y9   [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 30.000 -name clk [get_ports clk]

## 复位按钮 BTNC（按下为高电平，接高有效异步复位）
set_property PACKAGE_PIN P16  [get_ports btn_rst]
set_property IOSTANDARD LVCMOS25 [get_ports btn_rst]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_ports btn_rst]

## LED0..LED7
set_property PACKAGE_PIN T22 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property PACKAGE_PIN T21 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
set_property PACKAGE_PIN U22 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
set_property PACKAGE_PIN U21 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]
set_property PACKAGE_PIN V22 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[4]}]
set_property PACKAGE_PIN W22 [get_ports {led[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[5]}]
set_property PACKAGE_PIN U19 [get_ports {led[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[6]}]
set_property PACKAGE_PIN U14 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[7]}]
