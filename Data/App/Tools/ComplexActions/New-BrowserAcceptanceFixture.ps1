param(
    [string]$AppDir=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$OutDir='',
    # Optional, already extracted real telemetry. No source SAV is parsed or altered here.
    [string]$RealTelemetryPath=''
)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($OutDir)){
    $OutDir=Join-Path (Split-Path -Parent $AppDir) ('Diagnostics\Acceptance\browser_'+[guid]::NewGuid().ToString('N'))
}
if(Test-Path -LiteralPath $OutDir){throw 'Choose a new fixture directory; existing data is never overwritten.'}
$fixtureRoot=[IO.Path]::GetFullPath($OutDir)
$fixtureData=Join-Path $fixtureRoot 'Data';$fixtureOutput=Join-Path $fixtureRoot 'Output'
New-Item -ItemType Directory -Force $fixtureData,$fixtureOutput|Out-Null
Copy-Item -LiteralPath $AppDir -Destination $fixtureData -Recurse
. (Join-Path $AppDir 'Modules\Replay\Replay.Catalog.ps1')
$encoding=New-Object Text.UTF8Encoding($true)
function Write-PreviewJson([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 30),$encoding)}

# Known spatial controls: A has a 5 s prefix delay and a five-position later release.
# They test the UI and deterministic measurement; they are not real driving evidence.
foreach($label in @('A','B','C')){
    $speed=25.0
    $nativeSpeed=$(if($label-eq'A'){25.0}else{27.0})
    $prefix=$(if($label-eq'A'){5.0}else{0.0})
    $shift=$(if($label-eq'A'){5}elseif($label-eq'C'){-1}else{0})
    $rows=@(for($i=0;$i-le300;$i++){
        $raw=@(1,0,1,0,0,0,0,0)
        for($k=0;$k-lt4;$k++){
            $start=40+50*$k+$shift
            if($i-ge$start-and$i-lt$start+20){$raw[2]=0;if($i-lt$start+5){$raw[4]=1}}
        }
        $row=[ordered]@{time_s=($prefix+$i/$speed);x=$i;y=0;z=0;distance=$i;speed=$nativeSpeed;lap_index=1;pose_valid=$true;pose_break_before=$false;vehicle_forward_heading_rad=0;source_stream='browser_synthetic'}
        for($k=0;$k-lt8;$k++){$row['input_bool_candidate_'+(60+$k)]=$raw[$k]}
        [pscustomobject]$row
    })
    $telemetryDir=Join-Path $fixtureData ('Telemetry\synthetic_'+$label)
    New-Item -ItemType Directory -Force $telemetryDir|Out-Null
    $rows|Export-Csv -LiteralPath (Join-Path $telemetryDir 'logical.csv') -NoTypeInformation -Encoding UTF8
    $sha=(Get-FileHash -LiteralPath (Join-Path $telemetryDir 'logical.csv') -Algorithm SHA256).Hash
    $laps=@(@{lap=1;start_t=$prefix;end_t=($prefix+300/$speed);duration_s=(300/$speed);distance=300})
    $stream=@{
        id='local';role='local_high_frequency';role_label='合成界面样本';records=$rows.Count;sample_hz=$speed
        csv='logical.csv';duration_s=(300/$speed);distance=300;laps=$laps
        system_drift_state_available=$true;system_drift_segments=@(@{start_t=($prefix+40/$speed);end_t=($prefix+65/$speed)})
        speed_effect_state_available=$true;map_propulsion_effect_segments=@(@{start_t=0;end_t=30})
        route_preview=@($rows|ForEach-Object{@{t=$_.time_s;x=$_.x;y=$_.y;z=$_.z;speed=$_.speed;lap=1}})
    }
    Write-PreviewJson (Join-Path $telemetryDir 'telemetry_summary.json') @{source_sha256=$sha;streams=@($stream);evidence_kind='synthetic_browser_fixture'}
    $name='synthetic_'+$label+'_analysis.json'
    Write-PreviewJson (Join-Path $fixtureOutput $name) ([ordered]@{
        replay_sha256=$sha;replay_file=('合成界面样本 '+$label);map_name='月牙湾（合成界面样本）';resource_map_id=45;game_map_id=145
        status='native_ready';telemetry_status='ready';architecture='native_first_v1'
        telemetry_summary=('Data/Telemetry/synthetic_'+$label+'/telemetry_summary.json');streams=@($stream)
        evidence_kind='synthetic_browser_fixture';native_map=@{status='unavailable'}
    })
    [void](Add-ReplayCatalogEntry -DataDir $fixtureData -Sha256 $sha -OriginalName ('合成界面样本 '+$label) -SourcePresent $false -AnalysisDir $fixtureOutput)
}
if(-not[string]::IsNullOrWhiteSpace($RealTelemetryPath)){
    $real=Get-Content -LiteralPath $RealTelemetryPath -Raw -Encoding UTF8|ConvertFrom-Json
    $target=Join-Path $fixtureData 'Telemetry\real';New-Item -ItemType Directory -Force $target|Out-Null
    $sourceBase=[IO.Path]::GetFullPath((Split-Path -Parent $RealTelemetryPath)).TrimEnd('\')+'\'
    foreach($stream in @($real.streams)){
        $csv=[IO.Path]::GetFullPath((Join-Path $sourceBase ([string]$stream.csv)))
        if(-not$csv.StartsWith($sourceBase,[StringComparison]::OrdinalIgnoreCase)){throw 'Real CSV is outside its telemetry directory.'}
        $copyName=[IO.Path]::GetFileName($csv);Copy-Item -LiteralPath $csv -Destination (Join-Path $target $copyName)
        $stream.csv=$copyName
    }
    $real.replay_file='真实采样验证样本'
    Write-PreviewJson (Join-Path $target 'telemetry_summary.json') $real
    Write-PreviewJson (Join-Path $fixtureOutput 'real_analysis.json') ([ordered]@{
        replay_sha256=$real.source_sha256;replay_file='真实采样验证样本';map_name='真实输入（地图身份未在此夹具验证）'
        status='native_ready';telemetry_status='ready';architecture='native_first_v1';native_map=@{status='unavailable'}
        telemetry_summary='Data/Telemetry/real/telemetry_summary.json';streams=$real.streams
        evidence_kind='real_telemetry_in_browser_fixture'
    })
    [void](Add-ReplayCatalogEntry -DataDir $fixtureData -Sha256 $real.source_sha256 -OriginalName '真实采样验证样本' -SourcePresent $false -AnalysisDir $fixtureOutput)
}
Write-PreviewJson (Join-Path $fixtureRoot 'fixture.json') @{
    contract='complex_action_browser_fixture_v1';source_app=$AppDir
    evidence='Synthetic A/B/C test browser flows; optional real telemetry tests display only. No game/map/technique verification.'
}
[pscustomobject]@{root=$fixtureRoot;frontend=(Join-Path $fixtureData 'App\QQReplayFrontend.ps1');evidence_kind='browser_fixture'}
