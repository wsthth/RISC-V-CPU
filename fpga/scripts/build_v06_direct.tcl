# build_v06_direct.tcl - AC7021B full flow via single-process flow
# avoids launch_runs subprocess TclStackFree crash (Vivado 2019.1 bug)
set root "D:/my_project/RISC-V"
set part   xc7z020clg484-1

# put program.hex in cwd so $readmemh("program.hex") works for synth_design
file copy -force "$root/testprog/hex/led.hex" "./program.hex"

read_verilog [list \
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

read_xdc "$root/fpga/constraints/ac7021b.xdc"

synth_design -top fpga_top_ac7021b -part $part
opt_design
place_design
route_design
write_bitstream -force "fpga_top.bit"

puts "=== AC7021B BUILD OK ==="
puts "Bitstream: [pwd]/fpga_top.bit"
