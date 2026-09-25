param(
    [ValidateSet('CUSTOM', 'MAX', 'BASE', 'MIN')]
    [string]$Config = 'CUSTOM',
    [switch]$Perf,
    [switch]$Disable,
    [string]$VivadoBin = 'C:\Xilinx\Vivado\2022.2\bin'
)

$sourceRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
$files = @(Get-Content (Join-Path $sourceRoot 'core.files') |
    Where-Object { $_.Trim() } |
    ForEach-Object { Join-Path $sourceRoot $_.Trim() })
$testbench = Join-Path $sourceRoot 'tb\scr1_branch_predictor_tb.sv'
$defines = @()
switch ($Config) {
    'MAX'  { $defines += @('-d', 'SCR1_CFG_RV32IMC_MAX') }
    'BASE' { $defines += @('-d', 'SCR1_CFG_RV32IC_BASE') }
    'MIN'  { $defines += @('-d', 'SCR1_CFG_RV32EC_MIN') }
}
if ($Perf) { $defines += @('-d', 'SCR1_BP_PERF') }
if ($Disable) { $defines += @('-d', 'SCR1_BP_DISABLE') }

$runName = ('scr1_bp_{0}_{1}_{2}' -f $Config.ToLower(),
    $(if ($Perf) { 'perf' } else { 'functional' }),
    $(if ($Disable) { 'off' } else { 'on' }))
$buildDir = Join-Path $env:TEMP $runName
New-Item -ItemType Directory -Force $buildDir | Out-Null

Push-Location $buildDir
try {
    & (Join-Path $VivadoBin 'xvlog.bat') -sv -i (Join-Path $sourceRoot 'includes') @defines @files $testbench
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }

    & (Join-Path $VivadoBin 'xelab.bat') --timescale 1ns/1ps work.scr1_branch_predictor_tb -s $runName
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }

    & (Join-Path $VivadoBin 'xsim.bat') $runName -runall | Tee-Object -Variable simOutput
    if ($LASTEXITCODE -ne 0 -or -not ($simOutput -match '^PASS:')) {
        throw 'branch predictor simulation failed'
    }
} finally {
    Pop-Location
}
