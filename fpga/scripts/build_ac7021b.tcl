# ============================================================================
# build_ac7021b.tcl —— ALINX AC7021B (xc7z020clg484-1) 一键建工程/综合/实现/比特流
# 用法（Windows 命令行，在 fpga\scripts 目录）：
#   D:\Xilinx\Vivado\2019.1\bin\vivado.bat -mode batch -source build_ac7021b.tcl
# 产物：..\vivado_ac7021b\riscv_ac7021b.runs\impl_1\fpga_top.bit
# 板级适配：-verilog_define AC7021B（1 个 LED 低电平点亮、无外部复位、50MHz）
# ============================================================================

set root "D:/my_project/RISC-V"
set proj_dir "$root/fpga/vivado_ac7021b"
set part   xc7z020clg484-1

file delete -force $proj_dir

# 1) 建工程
create_project riscv_ac7021b $proj_dir -part $part -force

# 2) 添加 RTL（common + single_cycle + pipeline + fpga_top）
add_files [list \
    "$root/rtl/common/alu.v" \
    "$root/rtl/common/regfile.v" \
    "$root/rtl/common/extend.v" \
    "$root/rtl/common/muxes.v" \
    "$root/rtl/common/flopr.v" \
    "$root/rtl/common/imem.v" \
    "$root/rtl/common/dmem.v" \
    "$root/rtl/common/branch_unit.v" \
    "$root/rtl/single_cycle/control_unit.v" \
    "$root/rtl/single_cycle/riscv_single.v" \
    "$root/rtl/pipeline/riscv_pipeline.v" \
    "$root/rtl/pipeline/pipe_regs.v" \
    "$root/rtl/pipeline/hazard_unit.v" \
    "$root/rtl/pipeline/forward_unit.v" \
    "$root/rtl/pipeline/branch_predictor.v" \
    "$root/fpga/fpga_top.v" \
    "$root/fpga/fpga_top_ac7021b.v" \
]

# 3) 复制测试程序 hex：$readmemh 在综合时按 <工程>.runs/synth_1 目录解析
set run_dir [pwd]
file copy -force "$root/testprog/hex/led.hex" "$proj_dir/program.hex"
file mkdir "$proj_dir/riscv_ac7021b.runs/synth_1"
file copy -force "$root/testprog/hex/led.hex" "$proj_dir/riscv_ac7021b.runs/synth_1/program.hex"

# 4) 顶层与约束
set_property top fpga_top_ac7021b [current_fileset]
read_xdc "$root/fpga/constraints/ac7021b.xdc"

# 5) 综合 -> 实现 -> 比特流
#（imem 程序靠复制到综合进程 cwd 的 program.hex）
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "SYNTHESIS FAILED"
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "IMPLEMENTATION FAILED"
}

puts "=== AC7021B BUILD OK ==="
# write_bitstream 默认输出以顶层模块命名
puts "Bitstream: $proj_dir/riscv_ac7021b.runs/impl_1/fpga_top.bit"
