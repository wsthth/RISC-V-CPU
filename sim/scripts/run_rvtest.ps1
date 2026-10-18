# =============================================================================
# run_rvtest.ps1 - 批量跑 riscv-tests rv32ui 官方测试集
# 每个测试：翻译 -> 汇编 -> xsim 仿真，收集 PASS/FAIL
# 用法：powershell -File run_rvtest.ps1 [-Only addi,and,...] [-Start 0] [-Count 43]
# =============================================================================
param(
    [string]$Only = "",
    [int]$Start = 0,
    [int]$Count = 43
)
$root = "D:\my_project\RISC-V"
$src  = "$root\riscv-tests-src\riscv-tests-master\isa\rv32ui"
$out  = "$root\testprog\rvtest"
Set-Location $root

$names = Get-ChildItem "$src\*.S" | ForEach-Object { $_.BaseName } | Sort-Object
if ($Only) { $names = $Only -split ',' }
$names = $names | Select-Object -Skip $Start -First $Count

# 功能边界 SKIP（有明确理由，见 risc-v.md 第 6/8/9 次记录）：
#   ma_data : test_136+ 期望依赖官方 #if __riscv_xlen==64 内的 RV64 sd 写入链，
#             RV32 语义下无法满足（CPU 非对齐读写已修复，test 1-135 全过）
#   fence_i : 自修改代码测试（imem 为 ROM 无法支持）+ 汇编器不支持 GAS 三操作数访存
$skip = @{
    'ma_data' = 'RV32 适配瑕疵: test_136+ 期望依赖官方 RV64 sd 写入链(非对齐读写已修复, test1-135 全过)'
    'fence_i' = '自修改代码: imem 为 ROM 无法支持 + GAS 三操作数访存语法'
}

$results = @()
foreach ($t in $names) {
    Write-Host "===== $t ====="
    if ($skip.ContainsKey($t)) { $results += "$t : SKIP ($($skip[$t]))"; continue }
    # 1. 翻译
    $c = python tools\riscv_tests_conv.py "$src\$t.S" $out 2>&1
    if ($LASTEXITCODE -ne 0) { $results += "$t : ASM_conv_fail"; continue }
    # 2. 汇编
    $a = python tools\riscv_asm.py "$out\$t.s" "$out\hex" 2>&1
    if ($LASTEXITCODE -ne 0) {
        $err = ($a | Select-String "ValueError|Error" | Select-Object -First 1)
        $results += "$t : ASM_FAIL ($err)"
        continue
    }
    # 3. 仿真
    $data = "$out\hex\$t.data.hex"
    $dataArg = @()
    if (Test-Path $data) { $dataArg = @("-DATA", $data) }
    $so = powershell -ExecutionPolicy Bypass -File "sim\scripts\run_sim.ps1" -TB tb_rvtest -HEX "$out\hex\$t.hex" @dataArg 2>&1
    if ($so -match "TEST PASSED")      { $results += "$t : PASS" }
    elseif ($so -match "TEST FAILED")  { $results += "$t : FAIL" }
    else                               { $results += "$t : UNKNOWN" }
}
"============ 汇总 ============"
$results | ForEach-Object { $_ }
"PASS: " + (($results | Where-Object { $_ -match ': PASS' }).Count) + "/" + $results.Count
