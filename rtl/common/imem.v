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
    // 程序加载：
    //   仿真：run_sim.ps1 复制 hex 为运行目录下的 program.hex
    //   综合：Vivado 由 TCL 通过 -verilog_define PROGRAM_HEX=<绝对路径> 指定；
    //         未定义时回退 program.hex（工程目录内）
`ifdef PROGRAM_HEX
    initial $readmemh(`"PROGRAM_HEX`", mem);
`else
    initial $readmemh("program.hex", mem);
`endif
    assign rd = mem[a[31:2]];
endmodule