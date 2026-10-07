param([string]$OutputDir = 'results/power_optimization/regression')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$benches = @('tb_pe_mac','tb_skew_buffers','tb_dual_systolic_array','tb_accel_dual_tile_core','tb_adaptive_gemm','tb_ping_pong_bram','tb_accel_top_axis','tb_accel_cache_mvm','tb_accel_dual_engine_top','tb_power_regression')
foreach ($bench in $benches) {
    $binary = Join-Path $OutputDir "$bench.vvp"
    $compileLog = Join-Path $OutputDir "$bench.compile.txt"
    $runLog = Join-Path $OutputDir "$bench.txt"
    & iverilog -g2012 -s $bench -o $binary (Get-ChildItem -LiteralPath 'src' -Filter '*.sv' | ForEach-Object FullName) "simulation/$bench.sv" 2> $compileLog
    if ($LASTEXITCODE -ne 0) { throw "$bench compile failed: $compileLog" }
    & vvp $binary > $runLog
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $runLog -Pattern '\[FAIL\]|FATAL:|FAIL:|ERROR:|\[ERROR\]') -or -not (Select-String -LiteralPath $runLog -Pattern 'PASS')) { throw "$bench failed: $runLog" }
    Write-Output "$bench PASS"
}
foreach ($dspLimit in @(96,80,64)) {
    $binary = Join-Path $OutputDir "tb_power_dsp$dspLimit.vvp"
    $runLog = Join-Path $OutputDir "tb_power_dsp$dspLimit.txt"
    & iverilog -g2012 -s tb_power_regression "-Ptb_power_regression.DSP_LIMIT=$dspLimit" -o $binary (Get-ChildItem -LiteralPath 'src' -Filter '*.sv' | ForEach-Object FullName) simulation/tb_power_regression.sv 2> (Join-Path $OutputDir "tb_power_dsp$dspLimit.compile.txt")
    if ($LASTEXITCODE -ne 0) { throw "DSP $dspLimit compile failed" }
    & vvp $binary > $runLog
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $runLog -Pattern '\[FAIL\]|FATAL:|FAIL:|ERROR:|\[ERROR\]') -or -not (Select-String -LiteralPath $runLog -Pattern 'PASS')) { throw "DSP $dspLimit regression failed" }
    Write-Output "DSP $dspLimit/engine functional regression PASS"
}
& python simulation/test_driver_metrics.py > (Join-Path $OutputDir 'driver.txt') 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Driver metrics regression failed' }
Write-Output 'driver metrics PASS (software test double)'
& python simulation/test_power_flow.py > (Join-Path $OutputDir 'power_flow.txt') 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Power qualification regression failed' }
Write-Output 'power qualification gates PASS'
