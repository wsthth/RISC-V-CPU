`timescale 1ns/1ps
// ============================================================================
// branch_predictor.v - 2-bit ���ͼ�������֧Ԥ���� + BTB����֧Ŀ�껺�壩
//
// �ṹ��
//   - 128 �� 2-bit ���ͼ��������� PC[8:2] ������PC 32 �ֽڶ��룩
//   - 128 �� BTB��ÿ�� 1-bit valid + 32-bit Ŀ���ַ
//   - Ԥ��Ϊ taken ��������BTB ���У��� PC ��ִ�й���ת���Ҽ�������λΪ 1
//
// ���£�EX �Σ��� B ���� jal ������jalr ���������
//   - ʵ����ת��д��/���� BTB Ŀ�꣬������ +1�����ͣ�
//   - ʵ�ʲ����������� -1�����ͣ�
//
// ˵����
//   - jalr Ŀ����������ʱ rs1���� ret �ķ��ص�ַ�������ʺ� BTB��Ԥ���Ϊ not-taken
//   - ͬһ PC ��ָ��̶���BTB ���м������õ�ַ������ת�� B/jal������������ָͨ��
// ============================================================================
module branch_predictor (
    input             clk,
    input             reset,
    // ---- IF �β�ѯ ----
    input  [31:0]     pcf,
    output wire [31:0] pred_target,
    output wire       pred_taken,
    // ---- EX �θ��� ----
    input             branch_resolved,  // EX ��Ϊ B/jal ����Ч
    input             branch_taken,     // ʵ���Ƿ���ת
    input  [31:0]     branch_pc,        // EX �� PC
    input  [31:0]     branch_target     // EX ��Ŀ���ַ
);
    localparam N = 128;    // v0.15: 1024->128 (v0.11 BTB扩容仿真无收益, 且1024项阵列撑爆综合布线拥塞)
    // 128 项: idx=PC[8:2], tag=PC[31:9] (20bit)

    reg [1:0]   counter [0:N-1];
    reg         valid   [0:N-1];
    reg [31:0]  btb     [0:N-1];
    reg [22:0]  tag     [0:N-1];   // PC[31:9] tag (128-entry, PC[8:2] idx)

    wire [6:0] idx_f = pcf[8:2];
    wire [6:0] idx_e = branch_pc[8:2];

    integer i;

    assign pred_taken  = valid[idx_f] & (tag[idx_f] == pcf[31:9]) & counter[idx_f][1];
    assign pred_target = btb[idx_f];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < N; i = i + 1) begin
                counter[i] <= 2'b00;
                valid[i]   <= 1'b0;
                btb[i]     <= 32'b0;
                tag[i]     <= 20'b0;
            end
        end
        else if (branch_resolved) begin
            if (branch_taken) begin
                valid[idx_e]   <= 1'b1;
                btb[idx_e]     <= branch_target;
                tag[idx_e]     <= branch_pc[31:9];
                counter[idx_e] <= (counter[idx_e] == 2'b11) ? 2'b11 : counter[idx_e] + 2'b01;
            end
            else begin
                counter[idx_e] <= (counter[idx_e] == 2'b00) ? 2'b00 : counter[idx_e] - 2'b01;
            end
        end
    end
endmodule
