`timescale 1ns/1ps
// ============================================================================
// imem.v - 指令内存（1024 x 32bit = 4KB）
// 组合读；initial 通过 $readmemh 加载 program.hex（仿真脚本负责复制到运行目录）
// 注：4KB 较小，综合时可推断为分布式 RAM（异步读），时序余量充足
// ============================================================================
module imem #(parameter DEPTH = 1024) (
    input  [31:0] a,
    output wire [31:0] rd
);
    reg [31:0] mem [0:DEPTH-1];
    initial $readmemh("program.hex", mem);
    assign rd = mem[a[31:2]];
endmodule