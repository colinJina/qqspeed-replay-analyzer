param([string]$AppDir=(Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))
$ErrorActionPreference='Stop'
. (Join-Path $AppDir 'Tests\Smoke-ComplexActions.ps1')
. (Join-Path $AppDir 'Modules\Replay\Replay.MapIdentityResolver.ps1')
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
    $analysisFixture=@{resource_map_id=45;game_map_id=145;map_name='synthetic-map';telemetry_summary='Data/Telemetry/sample/telemetry_summary.json'}
    $analysisFixture|ConvertTo-Json|Set-Content (Join-Path $outputDir 'sample.json') -Encoding UTF8
    $select=@{file='sample.json';stream='local';lap=1;start_t=1;end_t=9}
    $res=Invoke-ComplexActionComparisonLocal @{subject=$select;baseline=$select}
    Require ($res.subject.stages.Count-eq4-and$res.comparison.matches.Count-eq4) 'Complete CSV did not reach complex comparison.'
    Require ($res.subject.map_scope.allowed-and$res.subject.focus_range.start_t-eq1-and$res.subject.focus_range.end_t-eq9) 'Public observations lost the map scope or selected practice region.'
    $focus=Get-ComplexActionSide @{file='sample.json';stream='local';lap=1;start_t=1.5;end_t=2}
    Require ($focus.actions.stages.Count-eq1-and$focus.actions.chain_count-eq1-and$focus.actions.stages[0].end_t-gt2) 'Focus range clipped natural end or retained out-of-range chain counts.'
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
    $bad=$false;try {Get-ComplexActionSide @{file='sample.json';stream='local';lap=1}|Out-Null}catch{$bad=$true};Require $bad 'Whole-lap card analysis bypassed the required practice region.'
    # Renaming an unrelated or unresolved map must never enable this product feature.
    foreach($map in @(@{resource_map_id=37;game_map_id=137;map_name='月牙湾'},@{map_name='月牙湾'},@{resource_map_id=45;game_map_id=137;map_name='月牙湾'},@{resource_map_id=46;map_identity=@{authoritative=$true;resource_map_id=45};map_name='月牙湾'})){
        $map.telemetry_summary=$analysisFixture.telemetry_summary
        $map|ConvertTo-Json -Depth 5|Set-Content (Join-Path $outputDir 'sample.json') -Encoding UTF8
        $memory=New-Object IO.MemoryStream
        try {
            $body=[Text.Encoding]::UTF8.GetBytes((@{subject=$select}|ConvertTo-Json -Depth 5))
            Invoke-FrontendRouter $memory ([pscustomobject]@{Line='POST /api/complex-action-comparison HTTP/1.1';Headers=@{};Body=$body}) '' (Join-Path $AppDir 'Modules\Frontend') $root
            Require ([Text.Encoding]::UTF8.GetString($memory.ToArray()).StartsWith('HTTP/1.1 400')) 'Non-Moon-Bay identity bypassed the actual HTTP scope gate.'
            Require ((Get-InputTimelineLocal 'sample.json' 'local' 1).records-eq301) 'Map scope incorrectly disabled the generic input timeline.'
        } finally {$memory.Dispose()}
    }
    $analysisFixture|ConvertTo-Json|Set-Content (Join-Path $outputDir 'sample.json') -Encoding UTF8
    @{resource_map_id=37;game_map_id=137;telemetry_summary=$analysisFixture.telemetry_summary}|ConvertTo-Json|Set-Content (Join-Path $outputDir 'other.json') -Encoding UTF8
    $other=@{file='other.json';stream='local';lap=1;start_t=1;end_t=9}
    $rejected=Invoke-ComplexActionBatchLocal @{subject=$select;references=@($other);declarations=@{}}
    Require ($rejected.guidance.accepted_reference_count-eq0-and$rejected.guidance.rejected_references[0].reason-eq'reference_load_failed') 'A non-Moon-Bay reference entered the batch distribution.'
    Write-Host '[OK] Complex routes: Moon Bay identity/focus gate, generic timeline preserved, protected CSV, natural boundaries, cache invalidation and actual HTTP/JS routes.'
} finally {
    $resolved=[IO.Path]::GetFullPath($root);if($resolved.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}
}
