param([string]$AppDir=(Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))
$ErrorActionPreference='Stop'
. (Join-Path $AppDir 'Tests\Smoke-ComplexActions.ps1')
. (Join-Path $AppDir 'Modules\Telemetry\Telemetry.CSharpCore.ps1')
. (Join-Path $AppDir 'Modules\Frontend\Frontend.Backend.ps1')
. (Join-Path $AppDir 'Modules\Frontend\Frontend.Http.ps1')
. (Join-Path $AppDir 'Modules\Frontend\Frontend.InputTimeline.ps1')
. (Join-Path $AppDir 'Modules\Frontend\Frontend.ComplexActions.ps1')
. (Join-Path $AppDir 'Modules\Native\NativeReferenceGuidance.ps1')
$tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath());$root=Join-Path $tempBase ('QQReplayComplex_'+[Guid]::NewGuid().ToString('N'))
$outputDir=Join-Path $root 'Output';$dataDir=Join-Path $root 'Data';$dir=Join-Path $dataDir 'Telemetry\sample'
try {
    New-Item -ItemType Directory -Force $outputDir,$dir | Out-Null
    $csvRows=@(Samples|ForEach-Object{
        $s=$_;$r=[ordered]@{time_s=$s.time_s;x=$s.x;y=$s.y;z=$s.z;speed=$s.speed;lap_index=1;pose_valid=$true;pose_break_before=$false;vehicle_forward_heading_rad=0}
        for($k=0;$k-lt8;$k++){$r['input_bool_candidate_'+(60+$k)]=$s.raw_inputs[$k]};[pscustomobject]$r
    });$csvRows|Export-Csv -LiteralPath (Join-Path $dir 'logical.csv') -NoTypeInformation -Encoding UTF8
    $stream|Add-Member id 'local';$stream|Add-Member role 'local_high_frequency';$stream|Add-Member csv 'logical.csv';$stream|Add-Member laps @(@{lap=1})
    @{source_sha256='synthetic';streams=@($stream)}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'telemetry_summary.json') -Encoding UTF8
    @{map_id=7;map_name='sample-map';telemetry_summary='Data/Telemetry/sample/telemetry_summary.json'}|ConvertTo-Json|Set-Content (Join-Path $outputDir 'sample.json') -Encoding UTF8
    $select=@{file='sample.json';stream='local';lap=1}
    $res=Invoke-ComplexActionComparisonLocal @{subject=$select;baseline=$select}
    Require ($res.subject.stages.Count-eq4-and$res.comparison.matches.Count-eq4) 'Complete CSV did not reach complex comparison.'
    $focus=Get-ComplexActionSide @{file='sample.json';stream='local';lap=1;start_t=1.5;end_t=2}
    Require ($focus.actions.stages.Count-eq1-and$focus.actions.stages[0].end_t-gt2) 'Focus range clipped natural end.'
    $again=Get-ComplexActionSide $select;Require ([object]::ReferenceEquals($again,(Get-ComplexActionSide $select))) 'Derived side cache does not reuse rows.'
    $csvRows[40].input_bool_candidate_67=1;$csvRows|Export-Csv -LiteralPath (Join-Path $dir 'logical.csv') -NoTypeInformation -Encoding UTF8
    Require (-not[object]::ReferenceEquals($again,(Get-ComplexActionSide $select))) 'Cache signature did not invalidate after CSV changed.'
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $AppDir 'QQReplayFrontend.ps1'),[ref]$null,[ref]$null)
    foreach($name in @('Invoke-FrontendRouter','Send-FrontendAsset')){$f=$ast.Find({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-eq$name},$true);. ([scriptblock]::Create($f.Extent.Text))}
    foreach($route in @('/api/complex-action-comparison','/api/complex-action-batch','/js/complex-actions.js')){
        $memory=New-Object IO.MemoryStream
        try {
            $body=[Text.Encoding]::UTF8.GetBytes((@{subject=$select;baseline=$select;references=@($select);declarations=@{}}|ConvertTo-Json -Depth 8))
            $method=$(if($route.StartsWith('/api/')){'POST'}else{'GET'})
            Invoke-FrontendRouter $memory ([pscustomobject]@{Line=($method+' '+$route+' HTTP/1.1');Headers=@{};Body=$body}) '' (Join-Path $AppDir 'Modules\Frontend') $root
            $wire=[Text.Encoding]::UTF8.GetString($memory.ToArray());Require ($wire.StartsWith('HTTP/1.1 200')) ('Actual route failed: '+$route)
            if($method-eq'POST'){$json=($wire-split"`r`n`r`n",2)[1]|ConvertFrom-Json;Require ($json.subject.stages.Count-eq4) 'Wire lost stage observations.'}
            if($route-eq'/api/complex-action-batch'){Require ($json.guidance.accepted_reference_count-eq0-and$json.guidance.rejected_references[0].reason-eq'subject_cannot_reference_itself') 'Batch wire silently used A as its own reference.'}
        } finally {$memory.Dispose()}
    }
    $bad=$false;try {Invoke-ComplexActionComparisonLocal @{subject=@{file='sample.json';stream='local';lap=0}}|Out-Null}catch{$bad=$true};Require $bad 'Invalid lap accepted.'
    Write-Host '[OK] Complex routes: protected CSV, complete samples, natural focus boundaries, cache invalidation and actual HTTP/JS routes.'
} finally {
    $resolved=[IO.Path]::GetFullPath($root);if($resolved.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}
}
