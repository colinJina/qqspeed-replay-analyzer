param([string]$AppDir=(Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))
$ErrorActionPreference='Stop'
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp=[IO.Path]::GetFullPath((Join-Path $tempRoot ('QQReplay_InputTimeline_'+[Guid]::NewGuid().ToString('N'))))
if(-not$temp.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test directory.'}
New-Item -ItemType Directory -Force -Path $temp | Out-Null
function Require([bool]$Ok,[string]$Message){if(-not$Ok){throw $Message}}
function Put([byte[]]$D,[int]$O,[byte[]]$Value){[Array]::Copy($Value,0,$D,$O,$Value.Length)}
try {
    . (Join-Path $AppDir 'Modules\Telemetry\Telemetry.CSharpCore.ps1')
    Initialize-TelemetryCSharpCore -AppDir $AppDir
    $count=240;$bytes=New-Object byte[] ($count*230+512)
    for($i=0;$i-lt$count;$i++){
        $b=$i*230;Put $bytes $b ([BitConverter]::GetBytes([uint32]($i*17)))
        Put $bytes ($b+20) ([BitConverter]::GetBytes([single]1))
        Put $bytes ($b+24) ([BitConverter]::GetBytes([single]($i*.2)))
        Put $bytes ($b+52) ([BitConverter]::GetBytes([int]5))
        Put $bytes ($b+76) ([BitConverter]::GetBytes([int]1))
        Put $bytes ($b+173) ([BitConverter]::GetBytes([single]12))
        $bytes[$b+66]=255;$bytes[$b+67]=[byte]$(if($i-ge5-and$i-lt8){1}else{0})
    }
    $bytes[25*230+62]=2
    $sav=Join-Path $temp 'sample.sav';[IO.File]::WriteAllBytes($sav,$bytes)
    $out=Join-Path $temp 'physical';[QQReplayPortable]::ExtractFastFromDelimited($sav,$out)
    $manifest=Get-Content -LiteralPath (Join-Path $out 'manifest.json') -Raw|ConvertFrom-Json
    $meta=@($manifest.replays[0].streams)[0]
    $qpf=Join-Path $out ([string]$meta.fastbin)
    $rows=[QQReplayPortable]::LoadFastRows($qpf,'2026','stream_01')
    Require ($rows.Count-eq$count) 'Physical extraction lost fixture records.'
    for($i=0;$i-lt$count;$i++){
        for($k=0;$k-lt8;$k++){Require ($rows[$i].input_bool_candidate[$k]-eq$bytes[$i*230+60+$k]) ('Raw transport mismatch at '+$i+'/'+$k)}
    }
    Require ([int]$rows[0].input_bool_candidate_66-eq255) 'Raw 255 was collapsed into missing.'
    Require ($rows[6].forward_related_input-eq$true) '67-only activation lost.'
    Require ($null-eq$rows[25].forward_related_input) 'Non-binary input falsely became released.'
    Require ([QQReplayInputCandidates]::Forward(0,0)-eq$false) '00 forward state.'
    Require ([QQReplayInputCandidates]::Forward(1,1)-eq$true) '11 forward state.'
    Require ($null-eq[QQReplayInputCandidates]::Forward(0,$null)) 'Missing 67 falsely became released.'
    $legacy=Join-Path $temp 'legacy.qpf';$old=New-Object byte[] 16
    [Array]::Copy([Text.Encoding]::ASCII.GetBytes('QQPFAST1'),0,$old,0,8);Put $old 8 ([BitConverter]::GetBytes([int]1));[IO.File]::WriteAllBytes($legacy,$old)
    Require (-not[QQReplayPortable]::ValidateFastBin($legacy)) 'Old six-channel cache accepted.'
    $root=$temp;$outputDir=Join-Path $root 'Output';$dataDir=Join-Path $root 'Data'
    $telDir=Join-Path $dataDir 'Telemetry\sample'
    New-Item -ItemType Directory -Force -Path $outputDir,$telDir | Out-Null
    $csv=Join-Path $telDir 'logical_01.csv';[QQReplayPortable]::WriteLogicalCsv($csv,$rows)
    $timeline=[QQReplayInputTimeline]::LoadCsv($csv)
    Require ($timeline.samples.Count-eq$count) 'Timeline lost CSV records.'
    Require (@($timeline.raw_fields_available)-contains67) '67 absent from timeline.'
    Require ($timeline.samples[6].forward_related-eq$true) 'Timeline lost combined input.'
    $tel=@{streams=@(@{id='shadow_local';role='local_high_frequency';csv='logical_01.csv';laps=@(@{lap=1})})}
    $tel|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $telDir 'telemetry_summary.json') -Encoding UTF8
    @{telemetry_summary='Data/Telemetry/sample/telemetry_summary.json'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $outputDir 'sample.json') -Encoding UTF8
    . (Join-Path $AppDir 'Modules\Frontend\Frontend.Backend.ps1')
    . (Join-Path $AppDir 'Modules\Frontend\Frontend.InputTimeline.ps1')
    $api=Get-InputTimelineLocal 'sample.json' 'shadow_local' 1
    Require ($api.records-eq$count-and-not$api.requires_reanalysis) 'Backend timeline contract lost records.'
    $serialized=Json-Text $api 8|ConvertFrom-Json
    Require ($serialized.samples[6].raw_inputs[7]-eq1-and$serialized.samples[6].forward_related) 'JSON lost channel 67.'
    . (Join-Path $AppDir 'Modules\Frontend\Frontend.Http.ps1')
    $tokens=$null;$errors=$null
    $entryAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $AppDir 'QQReplayFrontend.ps1'),[ref]$tokens,[ref]$errors)
    foreach($name in @('Invoke-FrontendRouter','Send-FrontendAsset')){
        $function=$entryAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-eq$name},$true)
        Require ($null-ne$function) ('Actual frontend function missing: '+$name)
        . ([scriptblock]::Create($function.Extent.Text))
    }
    $memory=New-Object IO.MemoryStream
    try {
        Invoke-FrontendRouter $memory ([pscustomobject]@{Line='GET /api/input-timeline?file=sample.json&stream=shadow_local&lap=1 HTTP/1.1';Headers=@{};Body=[byte[]]@()}) '' (Join-Path $AppDir 'Modules\Frontend') $root
        $response=[Text.Encoding]::UTF8.GetString($memory.ToArray())
        Require ($response.StartsWith('HTTP/1.1 200')) 'Actual timeline router did not return 200.'
        $wire=($response -split "`r`n`r`n",2)[1]|ConvertFrom-Json
        Require ($wire.samples.Count-eq$count-and$wire.samples[6].forward_related) 'HTTP response changed input samples.'
    } finally {$memory.Dispose()}
    $memory=New-Object IO.MemoryStream
    try {
        Invoke-FrontendRouter $memory ([pscustomobject]@{Line='GET /api/input-timeline?file=sample.json&stream=shadow_local&lap=bad HTTP/1.1';Headers=@{};Body=[byte[]]@()}) '' (Join-Path $AppDir 'Modules\Frontend') $root
        Require ([Text.Encoding]::UTF8.GetString($memory.ToArray()).StartsWith('HTTP/1.1 400')) 'Invalid lap did not reach explicit error.'
    } finally {$memory.Dispose()}
    $memory=New-Object IO.MemoryStream
    try {
        Invoke-FrontendRouter $memory ([pscustomobject]@{Line='GET /js/input-timeline.js HTTP/1.1';Headers=@{};Body=[byte[]]@()}) '' (Join-Path $AppDir 'Modules\Frontend') $root
        Require ([Text.Encoding]::UTF8.GetString($memory.ToArray()).StartsWith('HTTP/1.1 200')) 'Timeline asset route is missing.'
    } finally {$memory.Dispose()}
    # Old logical CSV cannot turn a missing alternative forward channel into false.
    $legacyRows=@(Import-Csv -LiteralPath $csv)
    $names=@($legacyRows[0].PSObject.Properties.Name|Where-Object{$_-ne'input_bool_candidate_67'})
    $legacyRows|Select-Object $names|Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    $oldApi=Get-InputTimelineLocal 'sample.json' 'shadow_local' 1
    Require ($oldApi.requires_reanalysis-and$null-eq$oldApi.samples[0].forward_related) 'Legacy CSV silently fabricated 67=0.'
    $bad=$false
    try {Get-InputTimelineLocal 'sample.json' 'missing' 1|Out-Null}catch{$bad=$true}
    Require $bad 'Unknown stream was guessed.'
    $tel.streams[0].csv='..\..\..\outside.csv'
    $tel|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $telDir 'telemetry_summary.json') -Encoding UTF8
    $bad=$false
    try {Get-InputTimelineLocal 'sample.json' 'shadow_local' 1|Out-Null}catch{$bad=$true}
    Require $bad 'Timeline path escaped telemetry directory.'
    # Execute the actual grouping block with a real equal-time input transition at a part boundary.
    $driver=Get-Content -LiteralPath (Join-Path $AppDir 'QQReplayTelemetry.ps1') -Raw
    $start=$driver.IndexOf('$groups=New-Object System.Collections.Generic.List[object]')
    $finish=$driver.IndexOf('$logical=@',$start)
    Require ($start-ge0-and$finish-gt$start) 'Grouping block not found.'
    function Part($id,$t0,$t1,$x0,$x1,$state){
        [pscustomobject]@{id=$id;t0=$t0;t1=$t1;hz=60;x0=$x0;y0=0;z0=0;x1=$x1;y1=0;z1=0;speed_source='replay_linear_velocity';profile='2026';record_semantic_schema_version=1;vehicle_forward_axis_local='-Y';rows=@([pscustomobject]@{time=$t0;input_bool_candidate_64=$state},[pscustomobject]@{time=$t1;input_bool_candidate_64=0})}
    }
    $parts=@((Part 'a' 0 1 0 1 0),(Part 'b' 1 2 1 2 1))
    . ([scriptblock]::Create($driver.Substring($start,$finish-$start)))
    Require ($groups.Count-eq1-and$groups[0].rows.Count-eq4) 'Equal-time boundary sample was lost.'
    Require ($groups[0].rows[2].input_bool_candidate_64-eq1) 'Boundary input change was lost.'
    Write-Host '[OK] Input timeline: eight raw channels, 255, OR/unknown, legacy rejection, backend/HTTP routes, path gate, boundary preservation.'
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    if($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}
}
