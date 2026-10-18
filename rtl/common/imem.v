`timescale 1ns/1ps
// ============================================================================
// imem.v - ָ���ڴ棨Ĭ�� 8192 x 32bit = 32KB�������ɵ���
//   * SYNC_READ=1����ˮ�ߣ���ͬ������clk ���غ� rd ��Ч��IF2 ��ȡָ����
//     �ɱ� Vivado �ƶ�Ϊ Block RAM����ռ�ֲ�ʽ LUT RAM
//   * SYNC_READ=0�������ڣ�������첽�����̲ĵ�����?CPU �÷���
//   * ���棺initial ͨ�� $readmemh ���� program.hex���ű�����Ŀ¼��
//   * �ۺϣ�Vivado �� TCL �� hex ���Ƶ����� .runs/synth_1 Ŀ¼
// ============================================================================
module imem #(parameter DEPTH = 8192, parameter SYNC_READ = 1) (
    input         clk,
    input         reset,   // ͬ������ַ�Ĵ�����λ�������?X���ۺϽ�Ӱ�츴λ��Ϊ��
    input  [31:0] a,       // ָ���ַ���ֽ�Ѱַ���?a[31:2]��
    output wire [31:0] rd, // ָ����
    output wire [31:0] rd_addr  // ����Ķ���ַ����?rd ͬԴ���� IF2 ���� pc ��ԣ�?
);
    (* ram_style = "block" *) reg [31:0] mem [0:DEPTH-1];
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
            // 真同步读（BRAM 标准读模式）：rd_r �?clk 边沿锁存 mem[a]�?
            // rd=rd_r 纯同步输出，可被 Vivado 推断�?Block RAM（不�?LUTRAM）�?
            // rd_addr=a 为组合读地址（供波形/调试），取指配对�?riscv_pipeline
            // 侧的 a_r（a 的延迟寄存器）承担：a_r �?N = a �?N-1 = rd_r 的读地址�?
            // 注意：rd_r 复位�?0，reset 释放后首�?(a_r=0, rd_r=0) 伪指令以
            // v0 丢弃（IF2 重复检测基准已�?FFFFFFFF 防误抑制）�?
            reg [31:0] rd_r;
            initial rd_r = 32'b0;
            always @(posedge clk) begin
                rd_r <= mem[a[31:2]];
            end
            assign rd = rd_r;
            assign rd_addr = a;
        end
        else begin : async_read
            always @(*) rd_int = mem[a[31:2]];
            assign rd = rd_int;
            assign rd_addr = a;
        end
    endgenerate
endmodule
