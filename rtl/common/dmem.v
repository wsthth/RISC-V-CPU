`timescale 1ns/1ps
// ============================================================================
// dmem.v - data memory (DEPTH x 32bit, parameterized)
//   * SYNC_READ=1 (pipeline): synchronous read. rd_addr (EX-stage value) is
//     latched with the read word; rd valid next cycle (MEM stage).
//     Single array mem + second read port rd_addr2 (= rd_addr + 4) for
//     cross-word high word -> pure 1W2R BRAM pattern (inferable).
//   * SYNC_READ=0 (single cycle): combinational async read + full unaligned
//     write (simulation verification only).
//   * Write (SYNC_READ=1): byte-enable (be[3:0] + shifted wd_sh), independent
//     per-byte if -> Vivado 2019.1 infers Block RAM.
//     BRAM single write port cannot do cross-word dual-address write
//     (sh off=3 / sw off!=0 ignored in SYNC_READ=1).
//   * write-after-read same-addr bypass: rd_word0 is a pure sync read; the
//     bypass happens in the rd_int combinational stage using one-cycle-late
//     write info (wpost_*). Unwritten bytes keep the true old value from
//     rd_word0 (= mem[write addr] when same-addr) -> no read-range subset
//     assumption needed for same-funct3 store/load pairs.
// ============================================================================
module dmem #(parameter DEPTH = 8192, parameter SYNC_READ = 1) (
    input             clk,
    input             we,          // MemWrite (MEM stage)
    input  [2:0]      funct3_r,    // read access type
    input  [2:0]      funct3_w,    // write access type (MEM stage)
    input  [31:0]     rd_addr,     // read address (EX stage value)
    input  [31:0]     rd_addr2,    // second read address = rd_addr + 4 (high word)
    input  [31:0]     wr_addr,     // write address (MEM stage)
    input  [31:0]     wd,          // write data (MEM stage)
    output wire [31:0] rd          // read data
);
    (* ram_style = "block" *) reg [31:0] mem [0:DEPTH-1];
    reg [31:0] rd_word0;   // sync-read target word
    reg [31:0] rd_word1;   // target word + 4 (cross-word read high word)
    reg [31:0] rd_int;
    assign rd = rd_int;
    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = 32'b0;
`ifdef DMEM_INIT
        $readmemh("data.hex", mem);
`endif
    end

    wire [1:0] off  = rd_addr[1:0];
    wire [1:0] woff = wr_addr[1:0];
    wire [3:0] be;
    wire [31:0] wd_sh;
    assign be = (funct3_w == 3'b000) ? (4'b0001 << woff) :
                (funct3_w == 3'b001) ? (4'b0011 << woff) :
                (funct3_w == 3'b010 && woff == 2'b00) ? 4'b1111 : 4'b0000;
    assign wd_sh = wd << {woff, 3'b000};

    generate
        if (SYNC_READ) begin : sync_read
            reg [2:0]  rd_f3_r;
            reg [1:0]  rd_off_r;
            reg [29:0] rd_addr_r;
            // one-cycle-late write info (for combinational write-through)
            reg        wpost_we_r;
            reg [29:0] wpost_addr_r;
            reg [3:0]  wpost_be_r;
            reg [31:0] wpost_wd_sh_r;
            // ---- write (byte enable, BRAM) ----
            always @(posedge clk) begin
                if (we && be[0]) mem[wr_addr[31:2]][7:0]   <= wd_sh[7:0];
                if (we && be[1]) mem[wr_addr[31:2]][15:8]  <= wd_sh[15:8];
                if (we && be[2]) mem[wr_addr[31:2]][23:16] <= wd_sh[23:16];
                if (we && be[3]) mem[wr_addr[31:2]][31:24] <= wd_sh[31:24];
            end
            // ---- read (pure sync, BRAM 1W2R) ----
            always @(posedge clk) begin
                rd_word0 <= mem[rd_addr[31:2]];
                rd_word1 <= mem[rd_addr2[31:2]];
                rd_f3_r  <= funct3_r;
                rd_off_r <= rd_addr[1:0];
                rd_addr_r <= rd_addr[31:2];
                wpost_we_r    <= we && (rd_addr[31:2] == wr_addr[31:2]);
                wpost_addr_r  <= wr_addr[31:2];
                wpost_be_r    <= be;
                wpost_wd_sh_r <= wd_sh;
            end
            // ---- write-through bypass (combinational) ----
            // When a store wrote the same word the current load reads, the
            // BRAM sync read returned the OLD word; rebuild the post-write
            // word: written bytes from wd_sh, unwritten bytes keep the true
            // old value (rd_word0 is mem[write addr] in the same-addr case).
            wire [31:0] rd_wpost = {wpost_be_r[3] ? wpost_wd_sh_r[31:24] : rd_word0[31:24],
                                    wpost_be_r[2] ? wpost_wd_sh_r[23:16] : rd_word0[23:16],
                                    wpost_be_r[1] ? wpost_wd_sh_r[15:8]  : rd_word0[15:8],
                                    wpost_be_r[0] ? wpost_wd_sh_r[7:0]   : rd_word0[7:0]};
            wire [31:0] rd_word_s = (wpost_we_r && wpost_addr_r == rd_addr_r) ? rd_wpost : rd_word0;
            // ---- read data extraction (lb/lh/lw/lbu/lhu, incl. cross-word) ----
            always @(*) begin
                case (rd_f3_r)
                    3'b000: begin  // lb
                        case (rd_off_r)
                            2'b00:   rd_int = {{24{rd_word_s[7]}},  rd_word_s[7:0]};
                            2'b01:   rd_int = {{24{rd_word_s[15]}}, rd_word_s[15:8]};
                            2'b10:   rd_int = {{24{rd_word_s[23]}}, rd_word_s[23:16]};
                            default: rd_int = {{24{rd_word_s[31]}}, rd_word_s[31:24]};
                        endcase
                    end
                    3'b001: begin  // lh (incl. cross-word off=3)
                        case (rd_off_r)
                            2'b00:   rd_int = {{16{rd_word_s[15]}},  rd_word_s[15:0]};
                            2'b01:   rd_int = {{16{rd_word_s[23]}},  rd_word_s[23:8]};
                            2'b10:   rd_int = {{16{rd_word_s[31]}},  rd_word_s[31:16]};
                            default: rd_int = {{16{rd_word1[7]}}, rd_word1[7:0], rd_word_s[31:24]};
                        endcase
                    end
                    3'b010: begin  // lw (incl. cross-word)
                        case (rd_off_r)
                            2'b00:   rd_int = rd_word_s;
                            2'b01:   rd_int = {rd_word1[7:0],  rd_word_s[31:8]};
                            2'b10:   rd_int = {rd_word1[15:0], rd_word_s[31:16]};
                            default: rd_int = {rd_word1[23:0], rd_word_s[31:24]};
                        endcase
                    end
                    3'b100: begin  // lbu
                        case (rd_off_r)
                            2'b00:   rd_int = {24'b0, rd_word_s[7:0]};
                            2'b01:   rd_int = {24'b0, rd_word_s[15:8]};
                            2'b10:   rd_int = {24'b0, rd_word_s[23:16]};
                            default: rd_int = {24'b0, rd_word_s[31:24]};
                        endcase
                    end
                    3'b101: begin  // lhu (incl. cross-word off=3)
                        case (rd_off_r)
                            2'b00:   rd_int = {16'b0, rd_word_s[15:0]};
                            2'b01:   rd_int = {16'b0, rd_word_s[23:8]};
                            2'b10:   rd_int = {16'b0, rd_word_s[31:16]};
                            default: rd_int = {16'b0, rd_word1[7:0], rd_word_s[31:24]};
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
                    3'b001: begin  // lh (incl. cross-word)
                        case (off)
                            2'b00:   rd_int = {{16{mem[rd_addr[31:2]][15]}},  mem[rd_addr[31:2]][15:0]};
                            2'b01:   rd_int = {{16{mem[rd_addr[31:2]][23]}},  mem[rd_addr[31:2]][23:8]};
                            2'b10:   rd_int = {{16{mem[rd_addr[31:2]][31]}},  mem[rd_addr[31:2]][31:16]};
                            default: rd_int = {{16{mem[rd_addr[31:2] + 1][7]}}, mem[rd_addr[31:2] + 1][7:0], mem[rd_addr[31:2]][31:24]};
                        endcase
                    end
                    3'b010: begin  // lw (incl. cross-word)
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
                    3'b101: begin  // lhu (incl. cross-word)
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
            // combinational write (full unaligned support, sim only)
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
                        3'b001: begin  // sh
                            case (woff)
                                2'b00:   mem[wr_addr[31:2]][15:0]  <= wd[15:0];
                                2'b01:   mem[wr_addr[31:2]][23:8]  <= wd[15:0];
                                2'b10:   mem[wr_addr[31:2]][31:16] <= wd[15:0];
                                default: begin
                                    mem[wr_addr[31:2]][31:24]    <= wd[7:0];
                                    mem[wr_addr[31:2] + 1][7:0] <= wd[15:8];
                                end
                            endcase
                        end
                        3'b010: begin  // sw
                            case (woff)
                                2'b00:   mem[wr_addr[31:2]] <= wd;
                                2'b01: begin
                                    mem[wr_addr[31:2]][31:8]  <= wd[23:0];
                                    mem[wr_addr[31:2] + 1][7:0] <= wd[31:24];
                                end
                                2'b10: begin
                                    mem[wr_addr[31:2]][31:16] <= wd[15:0];
                                    mem[wr_addr[31:2] + 1][15:0] <= wd[31:16];
                                end
                                default: begin
                                    mem[wr_addr[31:2]][31:24] <= wd[7:0];
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
