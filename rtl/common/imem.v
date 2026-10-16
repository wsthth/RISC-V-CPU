`timescale 1ns/1ps
// ============================================================================
// imem.v - ָ���ڴ棨1024 x 32bit = 4KB��
// ��϶���initial ͨ�� $readmemh ���� program.hex������ű������Ƶ�����Ŀ¼��
// ע��4KB ��С���ۺ�ʱ���ƶ�Ϊ�ֲ�ʽ RAM���첽������ʱ����������
// ============================================================================
module imem #(parameter DEPTH = 1024) (
    input  [31:0] a,
    output wire [31:0] rd
);
    reg [31:0] mem [0:DEPTH-1];
    // ������أ�
    //   ���棺run_sim.ps1 ���� hex Ϊ����Ŀ¼�µ� program.hex
    //   �ۺϣ�Vivado �� TCL ͨ�� -verilog_define PROGRAM_HEX=<����·��> ָ����
    //         δ����ʱ���� program.hex������Ŀ¼�ڣ�
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
    initial $display("imem[0]=%08h imem[1]=%08h", mem[0], mem[1]);
    assign rd = mem[a[31:2]];
endmodule