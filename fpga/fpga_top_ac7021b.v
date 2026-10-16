// ============================================================================
// fpga_top_ac7021b.v —— ALINX AC7021B 顶层（薄 wrapper）
// ----------------------------------------------------------------------------
// AC7021B 核心板板级特性：
//   - 1 个 PL 用户 LED（LED2/R7），低电平点亮
//   - 无 PL 复位按键（核心板 RESET 键连 PS_POR_B，PL 用内部上电复位）
//   - PL 时钟 50MHz（Y9）
// 约束见 fpga/constraints/ac7021b.xdc，综合见 fpga/scripts/build_ac7021b.tcl
// ============================================================================
module fpga_top_ac7021b (
    input  wire clk,      // PL 系统时钟 50MHz（Y9）
    output wire led       // 用户 LED2（R7，低电平点亮）
);
    fpga_top #(
        .LED_W          (1),   // 1 个 PL LED
        .LED_ACTIVE_LOW (1)    // 低电平点亮
    ) u_fpga_top (
        .clk      (clk),
        .btn_rst  (1'b0),      // 无外部复位，内部上电复位
        .led      (led)
    );
endmodule
