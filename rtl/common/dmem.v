`timescale 1ns/1ps
// ============================================================================
// dmem.v - 数据内存（默认 8192 x 32bit = 32KB，参数可调）
//   * SYNC_READ=1（流水线）：同步读。funct3_r + rd_addr（EX 阶段）在 clk
//     边沿锁存读出的字，下个周期（MEM 阶段）rd 稳定可用 —— 保持 load 转发
//     1 拍可用；读写地址分离（读提前到 EX），可推断 Block RAM
//   * SYNC_READ=0（单周期）：组合异步读（教材单周期 CPU 用法）
//   * 同步写：we + funct3_w + wr_addr + wd 在 clk 边沿写入（MEM 阶段）
//   * 支持 lb/lh/lw/lbu/lhu/sb/sh/sw，含非对齐跨字读写
// ============================================================================
module dmem #(parameter DEPTH = 8192, parameter SYNC_READ = 1) (
    input             clk,
    input             we,        // MemWrite（MEM 阶段）
    input  [2:0]      funct3_r,  // 读访问类型（EX 阶段）
    input  [2:0]      funct3_w,  // 写访问类型（MEM 阶段）
    input  [31:0]     rd_addr,   // 读地址（EX 阶段）
    input  [31:0]     wr_addr,   // 写地址（MEM 阶段）
    input  [31:0]     wd,        // 写数据（MEM 阶段）
    output wire [31:0] rd        // 读数据
);
    reg [31:0] mem [0:DEPTH-1];
    reg [31:0] mem1 [0:DEPTH-1];  // 镜像存储（供跨字读 rd_word1，双 BRAM 推断）
    reg [31:0] rd_word0;   // 同步读出的目标字
    reg [31:0] rd_word1;   // 目标字+1（跨字读需要）
    reg [31:0] rd_int;
    assign rd = rd_int;
    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = 32'b0;
            mem1[i] = 32'b0;
        end
`ifdef DMEM_INIT
        $readmemh("data.hex", mem);
        $readmemh("data.hex", mem1);
`endif
    end

    wire [1:0] off = rd_addr[1:0];
    wire [1:0] woff = wr_addr[1:0];

    // ---- 读（SYNC_READ=1：EX 地址边沿锁存，funct3/off 同步锁存；
    //         =0：组合读）----
    generate
        if (SYNC_READ) begin : sync_read
            reg [2:0]  rd_f3_r;
            reg [1:0]  rd_off_r;
            // 纯同步读（标准 BRAM 读模式，可推断 Block RAM）：
            // rd_word0<=mem[rd_addr] 边沿锁存；非对齐跨字读的高字由
            // 镜像存储 mem1 同步读出（双 BRAM，Vivado 可综合）。
            // read-after-write（sw 在 MEM 写、同址 lw 在 EX 读同一拍边沿，
            // 读采旧值）由本块的 write-through 旁路修正（wpost0/wpost1 按
            // funct3_w/woff 组合"写后字"），BRAM 写仍保持字节使能语义。
            // ---- 写后值组合计算（read-after-write 旁路）----
            reg [31:0] wpost0, wpost1;
            always @(*) begin
                wpost0 = mem[wr_addr[31:2]];
                wpost1 = mem1[wr_addr[31:2] + 1];
                case (funct3_w)
                    3'b000: begin  // sb
                        case (woff)
                            2'b00:   wpost0 = {mem[wr_addr[31:2]][31:8], wd[7:0]};
                            2'b01:   wpost0 = {mem[wr_addr[31:2]][31:16], wd[7:0], mem[wr_addr[31:2]][7:0]};
                            2'b10:   wpost0 = {mem[wr_addr[31:2]][31:24], wd[7:0], mem[wr_addr[31:2]][15:0]};
                            default: wpost0 = {wd[7:0], mem[wr_addr[31:2]][23:0]};
                        endcase
                    end
                    3'b001: begin  // sh（off=3 跨字：低字高字节 + 高字低字节）
                        case (woff)
                            2'b00:   wpost0 = {mem[wr_addr[31:2]][31:16], wd[15:0]};
                            2'b01:   wpost0 = {mem[wr_addr[31:2]][31:24], wd[15:0], mem[wr_addr[31:2]][7:0]};
                            2'b10:   wpost0 = {wd[15:0], mem[wr_addr[31:2]][15:0]};
                            default: begin
                                wpost0 = {wd[7:0], mem[wr_addr[31:2]][23:0]};
                                wpost1 = {mem1[wr_addr[31:2] + 1][31:8], wd[15:8]};
                            end
                        endcase
                    end
                    3'b010: begin  // sw（未对齐跨字写：低字 + 高字）
                        case (woff)
                            2'b00:   wpost0 = wd;
                            2'b01: begin
                                wpost0 = {wd[23:0], mem[wr_addr[31:2]][7:0]};
                                wpost1 = {mem1[wr_addr[31:2] + 1][31:8], wd[31:24]};
                            end
                            2'b10: begin
                                wpost0 = {wd[15:0], mem[wr_addr[31:2]][15:0]};
                                wpost1 = {mem1[wr_addr[31:2] + 1][31:16], wd[31:16]};
                            end
                            default: begin
                                wpost0 = {wd[7:0], mem[wr_addr[31:2]][23:0]};
                                wpost1 = {mem1[wr_addr[31:2] + 1][7:0], wd[31:8]};
                            end
                        endcase
                    end
                    default: ;
                endcase
            end
            always @(posedge clk) begin
                if (we) begin
                    // 写后读同拍同址：锁存写后值（write-through）
                    rd_word0 <= wpost0;
                    rd_word1 <= wpost1;
                end else begin
                    rd_word0 <= mem[rd_addr[31:2]];
                    rd_word1 <= mem1[rd_addr[31:2] + 1];
                end
                rd_f3_r  <= funct3_r;
                rd_off_r <= rd_addr[1:0];
            end
            always @(*) begin
                case (rd_f3_r)
                    3'b000: begin  // lb
                        case (rd_off_r)
                            2'b00:   rd_int = {{24{rd_word0[7]}},  rd_word0[7:0]};
                            2'b01:   rd_int = {{24{rd_word0[15]}}, rd_word0[15:8]};
                            2'b10:   rd_int = {{24{rd_word0[23]}}, rd_word0[23:16]};
                            default: rd_int = {{24{rd_word0[31]}}, rd_word0[31:24]};
                        endcase
                    end
                    3'b001: begin  // lh（含非对齐）
                        case (rd_off_r)
                            2'b00:   rd_int = {{16{rd_word0[15]}},  rd_word0[15:0]};
                            2'b01:   rd_int = {{16{rd_word0[23]}},  rd_word0[23:8]};
                            2'b10:   rd_int = {{16{rd_word0[31]}},  rd_word0[31:16]};
                            default: rd_int = {{16{rd_word1[7]}}, rd_word1[7:0], rd_word0[31:24]};
                        endcase
                    end
                    3'b010: begin  // lw（含非对齐）
                        case (rd_off_r)
                            2'b00:   rd_int = rd_word0;
                            2'b01:   rd_int = {rd_word1[7:0],  rd_word0[31:8]};
                            2'b10:   rd_int = {rd_word1[15:0], rd_word0[31:16]};
                            default: rd_int = {rd_word1[23:0], rd_word0[31:24]};
                        endcase
                    end
                    3'b100: begin  // lbu
                        case (rd_off_r)
                            2'b00:   rd_int = {24'b0, rd_word0[7:0]};
                            2'b01:   rd_int = {24'b0, rd_word0[15:8]};
                            2'b10:   rd_int = {24'b0, rd_word0[23:16]};
                            default: rd_int = {24'b0, rd_word0[31:24]};
                        endcase
                    end
                    3'b101: begin  // lhu（含非对齐）
                        case (rd_off_r)
                            2'b00:   rd_int = {16'b0, rd_word0[15:0]};
                            2'b01:   rd_int = {16'b0, rd_word0[23:8]};
                            2'b10:   rd_int = {16'b0, rd_word0[31:16]};
                            default: rd_int = {16'b0, rd_word1[7:0], rd_word0[31:24]};
                        endcase
                    end
                    default: rd_int = 32'b0;
                endcase
            end
        end
        else begin : async_read
            always @(*) begin
                case (funct3_r)
                    3'b000: begin  // lb
                        case (off)
                            2'b00:   rd_int = {{24{mem[rd_addr[31:2]][7]}},  mem[rd_addr[31:2]][7:0]};
                            2'b01:   rd_int = {{24{mem[rd_addr[31:2]][15]}}, mem[rd_addr[31:2]][15:8]};
                            2'b10:   rd_int = {{24{mem[rd_addr[31:2]][23]}}, mem[rd_addr[31:2]][23:16]};
                            default: rd_int = {{24{mem[rd_addr[31:2]][31]}}, mem[rd_addr[31:2]][31:24]};
                        endcase
                    end
                    3'b001: begin  // lh（含非对齐）
                        case (off)
                            2'b00:   rd_int = {{16{mem[rd_addr[31:2]][15]}},  mem[rd_addr[31:2]][15:0]};
                            2'b01:   rd_int = {{16{mem[rd_addr[31:2]][23]}},  mem[rd_addr[31:2]][23:8]};
                            2'b10:   rd_int = {{16{mem[rd_addr[31:2]][31]}},  mem[rd_addr[31:2]][31:16]};
                            default: rd_int = {{16{mem[rd_addr[31:2] + 1][7]}}, mem[rd_addr[31:2] + 1][7:0], mem[rd_addr[31:2]][31:24]};
                        endcase
                    end
                    3'b010: begin  // lw（含非对齐）
                        case (off)
                            2'b00:   rd_int = mem[rd_addr[31:2]];
                            2'b01:   rd_int = {mem[rd_addr[31:2] + 1][7:0],  mem[rd_addr[31:2]][31:8]};
                            2'b10:   rd_int = {mem[rd_addr[31:2] + 1][15:0], mem[rd_addr[31:2]][31:16]};
                            default: rd_int = {mem[rd_addr[31:2] + 1][23:0], mem[rd_addr[31:2]][31:24]};
                        endcase
                    end
                    3'b100: begin  // lbu
                        case (off)
                            2'b00:   rd_int = {24'b0, mem[rd_addr[31:2]][7:0]};
                            2'b01:   rd_int = {24'b0, mem[rd_addr[31:2]][15:8]};
                            2'b10:   rd_int = {24'b0, mem[rd_addr[31:2]][23:16]};
                            default: rd_int = {24'b0, mem[rd_addr[31:2]][31:24]};
                        endcase
                    end
                    3'b101: begin  // lhu（含非对齐）
                        case (off)
                            2'b00:   rd_int = {16'b0, mem[rd_addr[31:2]][15:0]};
                            2'b01:   rd_int = {16'b0, mem[rd_addr[31:2]][23:8]};
                            2'b10:   rd_int = {16'b0, mem[rd_addr[31:2]][31:16]};
                            default: rd_int = {16'b0, mem[rd_addr[31:2] + 1][7:0], mem[rd_addr[31:2]][31:24]};
                        endcase
                    end
                    default: rd_int = 32'b0;
                endcase
            end
        end
    endgenerate

    // ---- 同步写（MEM 阶段，clk 边沿写入）----
    generate
        if (SYNC_READ) begin : bram_write
            always @(posedge clk) begin
                if (we) begin
                    case (funct3_w)
                        3'b000: begin  // sb（单字内字节写，BRAM 字节使能）
                            case (woff)
                                2'b00: begin
                                    mem[wr_addr[31:2]][7:0]   <= wd[7:0];
                                    mem1[wr_addr[31:2]][7:0]  <= wd[7:0];
                                end
                                2'b01: begin
                                    mem[wr_addr[31:2]][15:8]  <= wd[7:0];
                                    mem1[wr_addr[31:2]][15:8] <= wd[7:0];
                                end
                                2'b10: begin
                                    mem[wr_addr[31:2]][23:16] <= wd[7:0];
                                    mem1[wr_addr[31:2]][23:16] <= wd[7:0];
                                end
                                default: begin
                                    mem[wr_addr[31:2]][31:24] <= wd[7:0];
                                    mem1[wr_addr[31:2]][31:24] <= wd[7:0];
                                end
                            endcase
                        end
                        3'b001: begin  // sh（off=3 跨字：低字高字节 + 高字低字节）
                            case (woff)
                                2'b00: begin
                                    mem[wr_addr[31:2]][15:0]  <= wd[15:0];
                                    mem1[wr_addr[31:2]][15:0] <= wd[15:0];
                                end
                                2'b01: begin
                                    mem[wr_addr[31:2]][23:8]  <= wd[15:0];
                                    mem1[wr_addr[31:2]][23:8] <= wd[15:0];
                                end
                                2'b10: begin
                                    mem[wr_addr[31:2]][31:16] <= wd[15:0];
                                    mem1[wr_addr[31:2]][31:16] <= wd[15:0];
                                end
                                default: begin
                                    mem[wr_addr[31:2]][31:24]  <= wd[7:0];
                                    mem1[wr_addr[31:2]][31:24] <= wd[7:0];
                                    mem[wr_addr[31:2] + 1][7:0] <= wd[15:8];
                                    mem1[wr_addr[31:2] + 1][7:0] <= wd[15:8];
                                end
                            endcase
                        end
                        3'b010: begin  // sw（未对齐跨字写：低字 + 高字双存储）
                            case (woff)
                                2'b00: begin
                                    mem[wr_addr[31:2]] <= wd;
                                    mem1[wr_addr[31:2]] <= wd;
                                end
                                2'b01: begin
                                    mem[wr_addr[31:2]][31:8]   <= wd[23:0];
                                    mem1[wr_addr[31:2]][31:8]  <= wd[23:0];
                                    mem[wr_addr[31:2] + 1][7:0] <= wd[31:24];
                                    mem1[wr_addr[31:2] + 1][7:0] <= wd[31:24];
                                end
                                2'b10: begin
                                    mem[wr_addr[31:2]][31:16]  <= wd[15:0];
                                    mem1[wr_addr[31:2]][31:16] <= wd[15:0];
                                    mem[wr_addr[31:2] + 1][15:0] <= wd[31:16];
                                    mem1[wr_addr[31:2] + 1][15:0] <= wd[31:16];
                                end
                                default: begin
                                    mem[wr_addr[31:2]][31:24]  <= wd[7:0];
                                    mem1[wr_addr[31:2]][31:24] <= wd[7:0];
                                    mem[wr_addr[31:2] + 1][23:0] <= wd[31:8];
                                    mem1[wr_addr[31:2] + 1][23:0] <= wd[31:8];
                                end
                            endcase
                        end
                        default: ;
                    endcase
                end
            end
        end
        else begin : async_write
            always @(posedge clk) begin
                if (we) begin
                    case (funct3_w)
                        3'b000: begin  // sb
                            case (woff)
                                2'b00:   mem[wr_addr[31:2]][7:0]   <= wd[7:0];
                                2'b01:   mem[wr_addr[31:2]][15:8]  <= wd[7:0];
                                2'b10:   mem[wr_addr[31:2]][23:16] <= wd[7:0];
                                default: mem[wr_addr[31:2]][31:24] <= wd[7:0];
                            endcase
                        end
                        3'b001: begin  // sh（含非对齐）
                            case (woff)
                                2'b00:   mem[wr_addr[31:2]][15:0]  <= wd[15:0];
                                2'b01:   mem[wr_addr[31:2]][23:8]  <= wd[15:0];
                                2'b10:   mem[wr_addr[31:2]][31:16] <= wd[15:0];
                                default: begin
                                    mem[wr_addr[31:2]][31:24] <= wd[7:0];
                                    mem[wr_addr[31:2] + 1][7:0] <= wd[15:8];
                                end
                            endcase
                        end
                        3'b010: begin  // sw（支持非对齐，跨字写入）
                            case (woff)
                                2'b00:   mem[wr_addr[31:2]] <= wd;
                                2'b01: begin
                                    mem[wr_addr[31:2]][31:8]   <= wd[23:0];
                                    mem[wr_addr[31:2] + 1][7:0] <= wd[31:24];
                                end
                                2'b10: begin
                                    mem[wr_addr[31:2]][31:16]  <= wd[15:0];
                                    mem[wr_addr[31:2] + 1][15:0] <= wd[31:16];
                                end
                                default: begin
                                    mem[wr_addr[31:2]][31:24]  <= wd[7:0];
                                    mem[wr_addr[31:2] + 1][23:0] <= wd[31:8];
                                end
                            endcase
                        end
                        default: ;
                    endcase
                end
            end
        end
    endgenerate
endmodule
