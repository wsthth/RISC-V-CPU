# phase2_impl.tcl - place/route/bitstream from synth run (single process, lower memory)
open_project D:/my_project/RISC-V/fpga/vivado_ac7021b/riscv_ac7021b.xpr
open_run synth_1
opt_design
place_design
route_design
file mkdir D:/my_project/RISC-V/fpga/vivado_ac7021b/riscv_ac7021b.runs/impl_1
write_bitstream -force D:/my_project/RISC-V/fpga/vivado_ac7021b/riscv_ac7021b.runs/impl_1/fpga_top.bit
puts "=== IMPL OK ==="
