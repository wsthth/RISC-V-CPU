# ============================================================================
# NetFPGA SUME 约束文件（XC7VX690TFFG1761-3）
# ----------------------------------------------------------------------------
# 注意：NetFPGA SUME 不是 Vivado 自带板卡，需要按器件建工程（见 build_sume.tcl）。
# 下面的引脚位需要按手头 SUME 板卡原理图核对后填写（本文件为结构模板）：
#   - 板载用户时钟：SUME 参考设计使用 200MHz 差分时钟（MGT 参考 156.25MHz 勿混）
#     若你的 SUME 版本为 200MHz 差分，请在原理图确认引脚后替换下面两行。
#   - 用户 LED：SUME 提供 4 颗板载 LED（LD0..LD3），位置见原理图。
#   - 复位：可使用 GPIO 按键或直接绑到一个拨码/排针。
# 核对完成后删掉 TODO 行即可直接综合实现。
# ============================================================================

## 时钟（TODO：核对 SUME 原理图后填写真实引脚）
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports clk]
# create_clock -period 5.000 -name clk [get_ports clk]     # 200MHz

## 复位（TODO：核对后填写，高有效）
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports btn_rst]

## LED0..LED3（TODO：核对后填写；未用到的 led[7:4] 悬空即可）
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports {led[0]}]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports {led[1]}]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports {led[2]}]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports {led[3]}]
