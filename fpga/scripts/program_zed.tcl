# ============================================================================
# program_zed.tcl —— 连接 ZedBoard 并烧录比特流
# 用法：
#   D:\Xilinx\Vivado\2019.1\bin\vivado.bat -mode batch -source program_zed.tcl
# 前置：板子已上电并连接 JTAG（ZedBoard 板载 Digilent USB-JTAG）
# ============================================================================

open_hw_manager
connect_hw_server

# 打开目标并选择第一个设备（通常只有一个 FPGA）
open_hw_target
if {[llength [get_hw_devices]] == 0} {
    error "NO HW DEVICE FOUND: 请检查 JTAG 连接/驱动（ZedBoard 需 Digilent USB-JTAG 驱动）"
}
current_hw_device [lindex [get_hw_devices] 0]

set bit "D:/my_project/RISC-V/fpga/vivado_zed/riscv_zed.runs/impl_1/fpga_top.bit"
if {![file exists $bit]} {
    error "BITSTREAM NOT FOUND: $bit"
}

set_property PROGRAM.FILE $bit [current_hw_device]
refresh_hw_device [current_hw_device]
program_hw_devices [current_hw_device]

puts "=== PROGRAMMING DONE ==="
puts "Device: [get_property NAME [current_hw_device]]"
puts "Bitstream: $bit"
