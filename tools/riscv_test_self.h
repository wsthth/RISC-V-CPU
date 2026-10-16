// ============================================================================
// riscv_test.h —— 自定义框架（riscv-tests 兼容，适配本项目 CPU）
// ----------------------------------------------------------------------------
// 官方 riscv_test.h 需要 CSR(mtvec/misa)、fence、ecall 与 riscv-gcc 环境；
// 本版本做最小化替换（保持 TEST_* 宏接口不变）：
//   - 无 CSR：不初始化 mtvec（CPU 无异常处理，测试不触发异常）
//   - 无 ecall/fence：PASS/FAIL 用 gp(x3)=1/0 + 自旋，仿真 TB 读 gp 判定
//   - 无初始化序列：regfile 上电清零，PC 从 0 开始
// 用法：翻译器 riscv_tests_conv.py 在展开 #include "riscv_test.h" 时注入本文件。
// ============================================================================

// 测试号寄存器（TEST_CASE 里 li TESTNUM, testnum 用）
// 注意：官方 riscv_test.h 约定 TESTNUM=x3（与 PASS/FAIL 的 gp 判定复用同一寄存器）；
// TEST_BR2_OP 等宏直接用 x1/x2 做操作数，若 TESTNUM 占用 x1 会被覆盖，必须用 x3。
#define TESTNUM x3

// RV32 用户态模式：无初始化（regfile 已清零），直接进入代码段
#define RVTEST_RV32U

// 代码段开始：CPU 复位后 PC=0，直接执行（无需跳转）
#define RVTEST_CODE_BEGIN

// 代码段结束：提供 test_end 自旋标号（PASS/FAIL 的 j test_end 落点）
#define RVTEST_CODE_END \
        j test_end; \
        test_end: \
        j test_end

// PASS：TESTNUM(x3)=1 并自旋（TB 读 x3 判定）
#define RVTEST_PASS \
        li TESTNUM, 1; \
        j test_end

// FAIL：TESTNUM(x3)=0 并自旋
#define RVTEST_FAIL \
        li TESTNUM, 0; \
        j test_end

// 数据段：test_data 等标签由汇编器布局（紧跟代码段）
#define RVTEST_DATA_BEGIN
#define RVTEST_DATA_END
