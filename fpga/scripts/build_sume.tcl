# ============================================================================
# build_sume.tcl —— NetFPGA SUME (XC7VX690TFFG1761-3) 一键建工程/综合/实现/出比特流
# 用法（Windows 命令行，在 fpga\scripts 目录）：
#   D:\Xilinx\Vivado\2019.1\bin\vivado.bat -mode batch -source build_sume.tcl
# 产物：..\vivado_sume\riscv_sume.runs\impl_1\riscv_sume.bit
# 注意：SUME 不是 Vivado 自带板卡，此处直接按器件建工程；
#       约束 sume.xdc 中的引脚需按板卡原理图核对（见文件头注释）。
# ============================================================================

set root "D:/my_project/RISC-V"
set proj_dir "$root/fpga/vivado_sume"
set part   xc7vx690tffg1761-3

# 清理旧工程（重建）
file delete -force $proj_dir

# 1) 建工程
create_project riscv_sume $proj_dir -part $part -force

# 1b) 切到工程目录：$readmemh("program.hex") 在综合时按进程 cwd 解析
cd $proj_dir

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
]

# 3) 复制测试程序 hex：$readmemh 在综合时按 <工程>.runs/synth_1 目录解析
set run_dir [pwd]
file copy -force "$root/testprog/hex/led.hex" "$proj_dir/program.hex"
file mkdir "$proj_dir/riscv_sume.runs/synth_1"
file copy -force "$root/testprog/hex/led.hex" "$proj_dir/riscv_sume.runs/synth_1/program.hex"

# 4) 顶层与约束
set_property top fpga_top [current_fileset]
read_xdc "$root/fpga/constraints/sume.xdc"

# 5) 综合 -> 实现 -> 比特流
#（Vivado 2019.1 用默认综合策略即可，无需 Performance_Explore）
# imem 程序通过宏绝对路径加载（值不带引号，避免 MORE_OPTIONS 解析失败）
set_property STEPS.SYNTH_DESIGN.ARGS.MORE_OPTIONS {-verilog_define PROGRAM_HEX=D:/my_project/RISC-V/fpga/vivado_sume/program.hex} [get_runs synth_1]
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

puts "=== SUME BUILD OK ==="
# write_bitstream 默认输出以顶层模块命名
puts "Bitstream: $proj_dir/riscv_sume.runs/impl_1/fpga_top.bit"
