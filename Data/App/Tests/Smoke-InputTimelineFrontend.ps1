param([string]$AppDir=(Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))
$ErrorActionPreference='Stop'
$node=Get-Command node -ErrorAction SilentlyContinue
if($null-eq$node){Write-Host '[SKIP] Node unavailable: input timeline frontend harness NOT run.';exit 0}
& $node.Source (Join-Path $AppDir 'Tests\frontend\input_timeline_contract.cjs')
if($LASTEXITCODE-ne0){throw 'Input timeline frontend contract failed.'}
