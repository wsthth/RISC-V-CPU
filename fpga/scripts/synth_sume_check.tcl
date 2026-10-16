# ============================================================================
# synth_sume_check.tcl —— SUME (XC7VX690T) 综合冒烟验证（不实现/不烧录）
# 用途：确认 RTL 在 V7 器件可综合、资源推断正确。
# 完整上板流程（含实现+比特流）请先按原理图填好 sume.xdc 后运行 build_sume.tcl
# ============================================================================

set root "D:/my_project/RISC-V"
set proj_dir "$root/fpga/vivado_sume_check"

file delete -force $proj_dir
create_project riscv_sume_check $proj_dir -part xc7vx690tffg1761-3 -force
cd $proj_dir

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

file copy -force "$root/testprog/hex/led.hex" "$proj_dir/program.hex"
set_property top fpga_top [current_fileset]

synth_design -top fpga_top -part xc7vx690tffg1761-3 \
    -verilog_define PROGRAM_HEX="D:/my_project/RISC-V/fpga/vivado_sume_check/program.hex"

report_utilization -file "$proj_dir/sume_synth_utilization.rpt"
puts "=== SUME SYNTH CHECK OK ==="
