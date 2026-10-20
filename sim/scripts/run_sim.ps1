# =============================================================================
# run_sim.ps1 - Vivado 2019.1 xsim launcher (ASCII only, no encoding issues)
# Usage:
#   powershell -File run_sim.ps1 -TB tb_alu
#   powershell -File run_sim.ps1 -TB tb_pipe_full
#   powershell -File run_sim.ps1 -TB tb_pipe_full -HEX ..\..\testprog\hex\matmul.hex -DATA ..\..\testprog\hex\matmul.data.hex
#   powershell -File run_sim.ps1 -TB tb_coremark -HEX ..\..\testprog\hex\coremark1.hex -DATA ..\..\testprog\hex\coremark1.data.hex -Define PREDICT_OFF
# Notes:
#   - compiles all RTL *.v + sim/tb/<TB>.v into library work
#   - runs in sim/work/<TB>/ ; program.hex / data.hex are copied by this script
#   - -Wave: dump waves.vcd
#   - prints TEST PASSED / TEST FAILED / timeout info
# =============================================================================
param(
    [Parameter(Mandatory=$true)][string]$TB,
    [string]$HEX = "",
    [string]$DATA = "",
    [switch]$Wave,
    [string]$Define = ""
)

$vivado = "D:\Xilinx\Vivado\2019.1\bin"
$root   = "D:\my_project\RISC-V"
$work   = Join-Path $root ("sim\work\" + $TB)

# tb_pipe_full regression defaults to full.hex so a stale program.hex
# left by a previous -HEX run cannot leak into the regression.
if ($TB -eq "tb_pipe_full" -and -not $HEX) {
    $HEX = Join-Path $root "testprog\hex\full.hex"
}

New-Item -ItemType Directory -Force -Path $work | Out-Null
if ($HEX  -and (Test-Path $HEX))  { Copy-Item $HEX  (Join-Path $work "program.hex") -Force }
if ($DATA -and (Test-Path $DATA)) { Copy-Item $DATA (Join-Path $work "data.hex") -Force }

Set-Location $work

# ---- 1. compile all RTL + TB ----
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

# ---- 2. elaborate ----
Write-Host "== xelab =="
& "$vivado\xelab.bat" -L work -debug typical $TB -s sim_snapshot 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { Write-Host "ELAB FAILED"; exit 1 }

# ---- 3. simulate ----
Write-Host "== xsim =="
if ($Wave) {
    $tcl = "open_vcd `"waves.vcd`"`nlog_vcd [get_objects -r /$TB/*]`nrun all`nclose_vcd`nquit`n"
} else {
    $tcl = "run all`nquit`n"
}
$tcl | Out-File -FilePath (Join-Path $work "run.tcl") -Encoding ascii
$simout = & "$vivado\xsim.bat" sim_snapshot -t run.tcl 2>&1
$simout | Out-Host

# ---- 4. verdict ----
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
