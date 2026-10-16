`timescale 1ns/1ps
// ============================================================================
// dmem.v - 数据内存（1024 x 32bit = 4KB，字节寻址）
// 支持 lb/lh/lw/lbu/lhu/sb/sh/sw；组合读、时钟沿写
// 可选 $readmemh("data.hex") 初始化（由宏 DMEM_INIT 控制）
// ============================================================================
module dmem #(parameter DEPTH = 1024) (
    input             clk,
    input             we,       // MemWrite
    input  [2:0]      funct3,   // 访存宽度/符号
    input  [31:0]     a,        // 地址
    input  [31:0]     wd,       // 写数据
    output reg [31:0] rd        // 读数据
);
    reg [31:0] mem [0:DEPTH-1];
    integer i;

`ifdef DMEM_INIT
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'b0;
        $readmemh("data.hex", mem);
    end
`else
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'b0;
    end
`endif

    wire [31:0] addr = a[31:2];
    wire [1:0]  off  = a[1:0];

    // ---- 组合读 ----
    always @(*) begin
        case (funct3)
            3'b000: begin  // lb
                case (off)
                    2'b00:   rd = {{24{mem[addr][7]}},  mem[addr][7:0]};
                    2'b01:   rd = {{24{mem[addr][15]}}, mem[addr][15:8]};
                    2'b10:   rd = {{24{mem[addr][23]}}, mem[addr][23:16]};
                    default: rd = {{24{mem[addr][31]}}, mem[addr][31:24]};
                endcase
            end
            3'b001: begin  // lh
                case (off[1])
                    1'b0: rd = {{16{mem[addr][15]}}, mem[addr][15:0]};
                    default: rd = {{16{mem[addr][31]}}, mem[addr][31:16]};
                endcase
            end
            3'b010: rd = mem[addr];                    // lw
            3'b100: begin  // lbu
                case (off)
                    2'b00:   rd = {24'b0, mem[addr][7:0]};
                    2'b01:   rd = {24'b0, mem[addr][15:8]};
                    2'b10:   rd = {24'b0, mem[addr][23:16]};
                    default: rd = {24'b0, mem[addr][31:24]};
                endcase
            end
            3'b101: begin  // lhu
                case (off[1])
                    1'b0: rd = {16'b0, mem[addr][15:0]};
                    default: rd = {16'b0, mem[addr][31:16]};
                endcase
            end
            default: rd = mem[addr];
        endcase
    end

    // ---- 同步写 ----
    always @(posedge clk) begin
        if (we) begin
            case (funct3)
                3'b000: begin  // sb
                    case (off)
                        2'b00:   mem[addr][7:0]   <= wd[7:0];
                        2'b01:   mem[addr][15:8]  <= wd[7:0];
                        2'b10:   mem[addr][23:16] <= wd[7:0];
                        default: mem[addr][31:24] <= wd[7:0];
                    endcase
                end
                3'b001: begin  // sh
                    case (off[1])
                        1'b0: mem[addr][15:0]  <= wd[15:0];
                        default: mem[addr][31:16] <= wd[15:0];
                    endcase
                end
                3'b010: mem[addr] <= wd;             // sw
                default: ;
            endcase
        end
    end
endmodule