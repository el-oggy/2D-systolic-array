param([string]$Vivado='C:\Xilinx\2025.1\Vivado\bin\vivado.bat')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location -LiteralPath $projectRoot
foreach($dspLimit in @(110,96,80,64)) {
    $candidateDir="results/power_optimization/screen$dspLimit"
    New-Item -ItemType Directory -Path $candidateDir -Force | Out-Null
    Get-ChildItem -LiteralPath 'src' -File | Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash | ConvertTo-Json | Set-Content -LiteralPath "$candidateDir/source-hashes.json"
    & $Vivado -mode batch -nojournal -nolog -source board_implementation/vivado/synth_power_candidate.tcl -tclargs . "$candidateDir/ooc" $dspLimit 100 > "$candidateDir/build.log" 2>&1
    if($LASTEXITCODE -ne 0) { throw "DSP $dspLimit screening failed; see $candidateDir/build.log" }
    Write-Output "DSP $dspLimit/engine screening completed"
}
