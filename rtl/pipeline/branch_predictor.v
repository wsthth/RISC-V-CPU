`timescale 1ns/1ps
// ============================================================================
// branch_predictor.v - 2-bit 饱和计数器分支预测器 + BTB（分支目标缓冲）
//
// 结构：
//   - 128 项 2-bit 饱和计数器，按 PC[8:2] 索引（PC 32 字节对齐）
//   - 128 项 BTB：每项 1-bit valid + 32-bit 目标地址
//   - 预测为 taken 的条件：BTB 命中（该 PC 曾执行过跳转）且计数器高位为 1
//
// 更新（EX 段，仅 B 型与 jal 触发，jalr 不入表）：
//   - 实际跳转：写入/更新 BTB 目标，计数器 +1（饱和）
//   - 实际不跳：计数器 -1（饱和）
//
// 说明：
//   - jalr 目标依赖运行时 rs1（如 ret 的返回地址），不适合 BTB，预测恒为 not-taken
//   - 同一 PC 的指令固定，BTB 命中即代表该地址是曾跳转的 B/jal，不会误伤普通指令
// ============================================================================
module branch_predictor (
    input             clk,
    input             reset,
    // ---- IF 段查询 ----
    input  [31:0]     pcf,
    output wire [31:0] pred_target,
    output wire       pred_taken,
    // ---- EX 段更新 ----
    input             branch_resolved,  // EX 段为 B/jal 且有效
    input             branch_taken,     // 实际是否跳转
    input  [31:0]     branch_pc,        // EX 段 PC
    input  [31:0]     branch_target     // EX 段目标地址
);
    localparam N = 128;

    reg [1:0]   counter [0:N-1];
    reg         valid   [0:N-1];
    reg [31:0]  btb     [0:N-1];
    integer i;

    wire [6:0] idx_f = pcf[8:2];
    wire [6:0] idx_e = branch_pc[8:2];

    assign pred_taken  = valid[idx_f] & counter[idx_f][1];
    assign pred_target = btb[idx_f];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < N; i = i + 1) begin
                counter[i] <= 2'b00;
                valid[i]   <= 1'b0;
                btb[i]     <= 32'b0;
            end
        end
        else if (branch_resolved) begin
            if (branch_taken) begin
                valid[idx_e]   <= 1'b1;
                btb[idx_e]     <= branch_target;
                counter[idx_e] <= (counter[idx_e] == 2'b11) ? 2'b11 : counter[idx_e] + 2'b01;
            end
            else begin
                counter[idx_e] <= (counter[idx_e] == 2'b00) ? 2'b00 : counter[idx_e] - 2'b01;
            end
        end
    end
endmodule
