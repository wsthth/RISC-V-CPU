// ============================================================================
// fpga_top.v —— FPGA 顶层（ZedBoard / AC7021B / NetFPGA SUME 通用，parameter 化）
// ----------------------------------------------------------------------------
// 将五级流水线 CPU 与板级外设连接：
//   - 板载时钟直接驱动 CPU（ZedBoard 33.333MHz / AC7021B 50MHz / SUME 待定）
//   - 复位：外部复位按钮（高有效）+ 内部上电复位（约 16 周期），两者相或
//   - MMIO 演示：CPU 写 0xF0000000 时，输出到板载 LED
//
// 参数：
//   LED_W          LED 数量（ZedBoard 8；AC7021B 1）
//   LED_ACTIVE_LOW LED 极性（0=高电平点亮 ZedBoard；1=低电平点亮 AC7021B）
// 无外部复位的板子（AC7021B）由 wrapper 将 btn_rst 接 1'b0。
//
// 说明：
//   - imem 通过 $readmemh 加载程序（仿真：program.hex；综合：工程目录/运行目录的 program.hex）
//   - 流水线 CPU 自带 MMIO 观察端口（io_write/io_wdata，见 riscv_pipeline.v）
// ============================================================================
module fpga_top #(
    parameter LED_W          = 8,   // ZedBoard：8 个 LED
    parameter LED_ACTIVE_LOW = 0    // 0=高电平点亮（ZedBoard）；1=低电平点亮（AC7021B）
) (
    input  wire           clk,      // 板载时钟
    input  wire           btn_rst,  // 复位按钮（高有效）；无外部复位时接 1'b0
    output wire [LED_W-1:0] led     // 板载 LED
);

    // ---- 内部上电复位：约 16 周期 ----
    reg [4:0] rst_cnt;
    always @(posedge clk) begin
        if (rst_cnt != 5'd31) rst_cnt <= rst_cnt + 1'b1;
    end
    wire reset = btn_rst | (rst_cnt < 5'd16);

    // ---- CPU 信号 ----
    wire [31:0] pc, instr;
    wire        io_write;
    wire [31:0] io_wdata;

    riscv_pipeline cpu (
        .clk      (clk),
        .reset    (reset),
        .pc       (pc),
        .instr    (instr),
        .io_write (io_write),
        .io_wdata (io_wdata)
    );

    // ---- MMIO：LED 寄存器 ----
    // CPU 向 0xF0000000 写值时，io_write=1、io_wdata 携带数据
    reg [LED_W-1:0] led_r;
    always @(posedge clk or posedge reset) begin
        if (reset)
            led_r <= {LED_W{1'b0}};
        else if (io_write)
            led_r <= io_wdata[LED_W-1:0];
    end
    generate
        if (LED_ACTIVE_LOW) begin : g_led_low
            // AC7021B LED2 低电平点亮（阳极接 3.3V）
            assign led = ~led_r;
        end
        else begin : g_led_high
            // ZedBoard LED 高电平点亮
            assign led = led_r;
        end
    endgenerate

endmodule
