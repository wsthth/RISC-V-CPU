# =============================================================================
# run_sim.ps1 - Vivado 2019.1 xsim 仿真脚本
# 用法：
#   powershell -File run_sim.ps1 -TB tb_alu
#   powershell -File run_sim.ps1 -TB tb_single -HEX ..\..\testprog\hex\basic.hex
#   powershell -File run_sim.ps1 -TB tb_dmem -Wave
# 说明：
#   - 自动编译 rtl/ 下全部 Verilog + sim/tb/<TB>.v
#   - 在 sim/work/<TB>/ 下运行，program.hex / data.hex 由脚本复制到该目录
#   - -Wave 时输出 waves.vcd（可用 xsim 或 GTKWave 打开）
#   - 结束时打印 TEST PASSED / TEST FAILED / 超时信息
# =============================================================================
param(
    [Parameter(Mandatory=$true)][string]$TB,
    [string]$HEX = "",
    [string]$DATA = "",
    [switch]$Wave,
    [string]$Define = ""   # 额外宏，如 -Define ASYNC_DMEM（逗号分隔多个）
)

$vivado = "D:\Xilinx\Vivado\2019.1\bin"
$root   = "D:\my_project\RISC-V"
$work   = Join-Path $root ("sim\work\" + $TB)

New-Item -ItemType Directory -Force -Path $work | Out-Null
if ($HEX  -and (Test-Path $HEX))  { Copy-Item $HEX  (Join-Path $work "program.hex") -Force }
if ($DATA -and (Test-Path $DATA)) { Copy-Item $DATA (Join-Path $work "data.hex") -Force }

Set-Location $work

# ---- 1. 编译 RTL + TB ----
$rtlFiles = @()
Get-ChildItem (Join-Path $root "rtl") -Filter *.v -Recurse | Sort-Object FullName |
    ForEach-Object { $rtlFiles += $_.FullName }
$tbFile = Join-Path $root ("sim\tb\" + $TB + ".v")
if (-not (Test-Path $tbFile)) { Write-Host "ERROR: TB not found: $tbFile"; exit 1 }

Write-Host "== xvlog =="
$defineArgs = @()
if ($DATA) { $defineArgs += "-d"; $defineArgs += "DMEM_INIT" }
if ($Define) { foreach ($m in ($Define -split ',')) { if ($m) { $defineArgs += "-d"; $defineArgs += $m } } }
& "$vivado\xvlog.bat" -work work $defineArgs $rtlFiles $tbFile 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { Write-Host "COMPILE FAILED"; exit 1 }

# ---- 2. 例化 ----
Write-Host "== xelab =="
& "$vivado\xelab.bat" -L work -debug typical $TB -s sim_snapshot 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { Write-Host "ELAB FAILED"; exit 1 }

# ---- 3. 运行 ----
Write-Host "== xsim =="
if ($Wave) {
    $tcl = "open_vcd `"waves.vcd`"`nlog_vcd [get_objects -r /$TB/*]`nrun all`nclose_vcd`nquit`n"
} else {
    $tcl = "run all`nquit`n"
}
$tcl | Out-File -FilePath (Join-Path $work "run.tcl") -Encoding ascii
$simout = & "$vivado\xsim.bat" sim_snapshot -t run.tcl 2>&1
$simout | Out-Host

# ---- 4. 结果 ----
if ($simout -match "TEST PASSED") {
    Write-Host ">>> RESULT: PASS"
    exit 0
} elseif ($simout -match "TEST FAILED") {
    Write-Host ">>> RESULT: FAIL"
    exit 1
} else {
    Write-Host ">>> RESULT: UNKNOWN (see sim output above)"
    exit 2
}
