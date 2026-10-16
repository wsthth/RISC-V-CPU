# ============================================================================
# program.tcl —— 连接 Zynq 板卡（JTAG）并烧录比特流
# 用法：
#   D:\Xilinx\Vivado\2019.1\bin\vivado.bat -mode batch -source program.tcl -tclargs <bit路径>
# 示例：
#   ... -source program.tcl -tclargs D:/my_project/RISC-V/fpga/vivado_ac7021b/riscv_ac7021b.runs/impl_1/fpga_top_ac7021b.bit
# 不带 -tclargs 时默认烧录 AC7021B 比特流。
# 前置：板子已上电并连接 JTAG（AC7021B 底板 FT232HL USB-JTAG / ZedBoard 板载 USB-JTAG）
# ============================================================================

puts "ARGS: $argv"
if {[llength $argv] >= 1} {
    set bit [lindex $argv 0]
} else {
    set bit "D:/my_project/RISC-V/fpga/vivado_ac7021b/riscv_ac7021b.runs/impl_1/fpga_top_ac7021b.bit"
}
puts "BITSTR=$bit"
puts "BITEXISTS=[file exists $bit]"
if {![file exists $bit]} {
    error "BITSTREAM NOT FOUND: $bit"
}

# Vivado 2019.1 硬件管理器命令为 open_hw（2020.x+ 才叫 open_hw_manager）
open_hw
connect_hw_server
open_hw_target
refresh_hw_server
set devs [get_hw_devices]
puts "DEVICES=$devs"
if {[llength $devs] == 0} {
    error "NO HW DEVICE FOUND: 请检查 JTAG 连接/板卡供电（FT232HL / Digilent USB-JTAG）"
}
# 选择 Zynq FPGA 器件（xc7z020），跳过 ARM DAP
set chosen ""
foreach d $devs {
    set part [get_property PART $d]
    puts "DEV $d PART=$part"
    if {[string match "xc7z*" $part]} { set chosen $d }
}
if {$chosen eq ""} { set chosen [lindex $devs 0] }
current_hw_device $chosen

set_property PROGRAM.FILE $bit [current_hw_device]
refresh_hw_device [current_hw_device]
program_hw_devices [current_hw_device]

puts "=== PROGRAMMING DONE ==="
puts "Device : [get_property NAME [current_hw_device]]"
puts "Bitstream: $bit"
