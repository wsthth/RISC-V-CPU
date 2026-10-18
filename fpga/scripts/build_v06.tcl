# build_v06.tcl - AC7021B full flow: synth -> impl -> bitstream (clean ASCII)
set root "D:/my_project/RISC-V"
set proj_dir "$root/fpga/vivado_ac7021b"
set part   xc7z020clg484-1

file delete -force $proj_dir
create_project riscv_ac7021b $proj_dir -part $part -force

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

file copy -force "$root/testprog/hex/led.hex" "$proj_dir/program.hex"
file mkdir "$proj_dir/riscv_ac7021b.runs/synth_1"
file copy -force "$root/testprog/hex/led.hex" "$proj_dir/riscv_ac7021b.runs/synth_1/program.hex"

set_property top fpga_top_ac7021b [current_fileset]
read_xdc "$root/fpga/constraints/ac7021b.xdc"

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "SYNTHESIS FAILED"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "IMPLEMENTATION FAILED"
}

puts "=== AC7021B BUILD OK ==="
puts "Bitstream: $proj_dir/riscv_ac7021b.runs/impl_1/fpga_top.bit"
