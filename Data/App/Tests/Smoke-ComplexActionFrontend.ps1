param([string]$AppDir=(Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))
$ErrorActionPreference='Stop'
$node=Get-Command node -ErrorAction SilentlyContinue
if($null-eq$node){Write-Host '[SKIP] Node unavailable: complex frontend harness NOT run.';exit 0}
& $node.Source (Join-Path $AppDir 'Tests\frontend\complex_actions_contract.cjs')
if($LASTEXITCODE-ne0){throw 'Complex action frontend contract failed.'}
