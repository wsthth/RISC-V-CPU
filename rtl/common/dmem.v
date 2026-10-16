`timescale 1ns/1ps
// ============================================================================
// dmem.v - �����ڴ棨1024 x 32bit = 4KB���ֽ�Ѱַ��
// ֧�� lb/lh/lw/lbu/lhu/sb/sh/sw����϶���ʱ����д
// ��ѡ $readmemh("data.hex") ��ʼ�����ɺ� DMEM_INIT ���ƣ�
// ============================================================================
module dmem #(parameter DEPTH = 1024) (
    input             clk,
    input             we,       // MemWrite
    input  [2:0]      funct3,   // �ô����/����
    input  [31:0]     a,        // ��ַ
    input  [31:0]     wd,       // д����
    output reg [31:0] rd        // ������
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

    // ---- 组合读（支持非对齐：lh/lhu 跨 16 位边界、lw 跨字）----
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
            3'b001: begin  // lh（含非对齐）
                case (off)
                    2'b00:   rd = {{16{mem[addr][15]}},  mem[addr][15:0]};
                    2'b01:   rd = {{16{mem[addr][23]}},  mem[addr][23:8]};
                    2'b10:   rd = {{16{mem[addr][31]}},  mem[addr][31:16]};
                    default: rd = {{16{mem[addr + 1][7]}}, mem[addr + 1][7:0], mem[addr][31:24]};
                endcase
            end
            3'b010: begin  // lw（支持非对齐，跨字拼接）
                case (off)
                    2'b00:   rd = mem[addr];
                    2'b01:   rd = {mem[addr + 1][7:0],  mem[addr][31:8]};
                    2'b10:   rd = {mem[addr + 1][15:0], mem[addr][31:16]};
                    default: rd = {mem[addr + 1][23:0], mem[addr][31:24]};
                endcase
            end
            3'b100: begin  // lbu
                case (off)
                    2'b00:   rd = {24'b0, mem[addr][7:0]};
                    2'b01:   rd = {24'b0, mem[addr][15:8]};
                    2'b10:   rd = {24'b0, mem[addr][23:16]};
                    default: rd = {24'b0, mem[addr][31:24]};
                endcase
            end
            3'b101: begin  // lhu（含非对齐）
                case (off)
                    2'b00:   rd = {16'b0, mem[addr][15:0]};
                    2'b01:   rd = {16'b0, mem[addr][23:8]};
                    2'b10:   rd = {16'b0, mem[addr][31:16]};
                    default: rd = {16'b0, mem[addr + 1][7:0], mem[addr][31:24]};
                endcase
            end
            default: rd = mem[addr];
        endcase
    end

    // ---- 同步写（支持非对齐 sh/sw 跨字）----
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
                3'b001: begin  // sh（含非对齐）
                    case (off)
                        2'b00: begin
                            mem[addr][15:0]  <= wd[15:0];
                        end
                        2'b01: begin
                            mem[addr][23:8]  <= wd[15:0];
                        end
                        2'b10: begin
                            mem[addr][31:16] <= wd[15:0];
                        end
                        default: begin
                            mem[addr][31:24] <= wd[7:0];
                            mem[addr + 1][7:0] <= wd[15:8];
                        end
                    endcase
                end
                3'b010: begin  // sw（支持非对齐，跨字写入）
                    case (off)
                        2'b00:   mem[addr] <= wd;
                        2'b01: begin
                            mem[addr][31:8]   <= wd[23:0];
                            mem[addr + 1][7:0] <= wd[31:24];
                        end
                        2'b10: begin
                            mem[addr][31:16]  <= wd[15:0];
                            mem[addr + 1][15:0] <= wd[31:16];
                        end
                        default: begin
                            mem[addr][31:24]  <= wd[7:0];
                            mem[addr + 1][23:0] <= wd[31:8];
                        end
                    endcase
                end
                default: ;
            endcase
        end
    end
endmodule