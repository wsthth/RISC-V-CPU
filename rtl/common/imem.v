`timescale 1ns/1ps
// ============================================================================
// imem.v - 指令内存（默认 8192 x 32bit = 32KB，参数可调）
//   * SYNC_READ=1（流水线）：同步读，clk 边沿后 rd 有效（IF2 级取指），
//     可被 Vivado 推断为 Block RAM，不占分布式 LUT RAM
//   * SYNC_READ=0（单周期）：组合异步读（教材单周期 CPU 用法）
//   * 仿真：initial 通过 $readmemh 加载 program.hex（脚本控制目录）
//   * 综合：Vivado 由 TCL 将 hex 复制到工程 .runs/synth_1 目录
// ============================================================================
module imem #(parameter DEPTH = 8192, parameter SYNC_READ = 1) (
    input         clk,
    input         reset,   // 同步读地址寄存器复位（仿真防 X；综合仅影响复位行为）
    input  [31:0] a,       // 指令地址（字节寻址，取 a[31:2]）
    output wire [31:0] rd, // 指令字
    output wire [31:0] rd_addr  // 锁存的读地址（与 rd 同源，供 IF2 锁存 pc 配对）
);
    reg [31:0] mem [0:DEPTH-1];
    reg [31:0] rd_int;
`ifdef PROGRAM_HEX
    initial begin
        $display("imem: loading PROGRAM_HEX = %0s", `PROGRAM_HEX);
        $readmemh(`PROGRAM_HEX, mem);
    end
`else
    initial begin
        $display("imem: loading program.hex (relative CWD)");
        $readmemh("program.hex", mem);
    end
`endif
    generate
        if (SYNC_READ) begin : sync_read
            // 读地址边沿锁存 + 组合输出（read-address-only，可映射 BRAM）。
            // rd_addr 与 rd 同源（同一 addr_r），F2 级锁存 pc_f2<=rd_addr 即可
            // 保证 (pc_f2, instr_f2) 恒配对：stall 时 pcreg 保持 -> addr_r 保持。
            reg [31:0] addr_r;
            always @(posedge clk or posedge reset) begin
                if (reset) addr_r <= 32'b0;
                else       addr_r <= a;
            end
            assign rd = mem[addr_r[31:2]];
            assign rd_addr = addr_r;
        end
        else begin : async_read
            always @(*) rd_int = mem[a[31:2]];
            assign rd = rd_int;
            assign rd_addr = a;
        end
    endgenerate
endmodule
