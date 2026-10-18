# 断点续传下载 xPack riscv-none-elf-gcc（418MB，网络不稳定时自动续传）
$url = "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v14.3.0-1/xpack-riscv-none-elf-gcc-14.3.0-1-win32-x64.zip"
$target = "D:\my_project\RISC-V\bench\toolchain\gcc.zip"
$expected = 438590965
$maxTries = 80
for ($i = 0; $i -lt $maxTries; $i++) {
    curl.exe -L -C - -o $target $url --retry 2 --retry-delay 3 --max-time 280 -sS 2>&1 | Out-Null
    $len = (Get-Item $target -ErrorAction SilentlyContinue).Length
    if ($null -eq $len) { $len = 0 }
    Write-Output "try $i : $len / $expected"
    if ($len -eq $expected) { Write-Output "COMPLETE"; break }
    Start-Sleep -Seconds 3
}
Write-Output "DONE final=$len"
