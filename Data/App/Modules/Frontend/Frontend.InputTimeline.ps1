function Clear-InputTimelineRowCache { $script:inputTimelineRowCache=$null }

function Get-InputTimelineRowsCached([string]$CsvPath) {
    if($null-eq$script:inputTimelineRowCache){$script:inputTimelineRowCache=@{}}
    $info=Get-Item -LiteralPath $CsvPath -ErrorAction Stop
    $key=[IO.Path]::GetFullPath($CsvPath)
    $signature=([string]$info.Length+'|'+[string]$info.LastWriteTimeUtc.Ticks)
    if($script:inputTimelineRowCache.ContainsKey($key)){
        $hit=$script:inputTimelineRowCache[$key]
        if($hit.signature-eq$signature){$hit.access=[DateTime]::UtcNow.Ticks;return $hit.data}
        [void]$script:inputTimelineRowCache.Remove($key)
    }
    Initialize-TelemetryCSharpCore -AppDir $appDir
    $data=[QQReplayInputTimeline]::LoadCsv($key)
    if($script:inputTimelineRowCache.Count-ge6){
        $old=@($script:inputTimelineRowCache.Keys|Sort-Object {$script:inputTimelineRowCache[$_].access}|Select-Object -First 1)[0]
        [void]$script:inputTimelineRowCache.Remove($old)
    }
    $script:inputTimelineRowCache[$key]=@{signature=$signature;data=$data;access=[DateTime]::UtcNow.Ticks}
    return $data
}

function Get-InputTimelineLocal([string]$AnalysisName,[string]$StreamId,[int]$LapNo) {
    $path=Get-TelemetryPathForAnalysis $AnalysisName
    if([string]::IsNullOrWhiteSpace($path)){throw 'Input timeline telemetry not found.'}
    $telemetry=Read-JsonFile $path
    $stream=$null
    foreach($s in @($telemetry.streams)){if([string]$s.id-eq$StreamId){$stream=$s;break}}
    if($null-eq$stream){throw 'Input timeline stream not found.'}
    if($LapNo-lt1 -or -not @($stream.laps|Where-Object{[int]$_.lap-eq$LapNo}).Count){throw 'Input timeline lap not found.'}
    $base=[IO.Path]::GetFullPath((Split-Path -Parent $path)).TrimEnd('\')+'\'
    $csv=[IO.Path]::GetFullPath((Join-Path $base ([string]$stream.csv)))
    if(-not$csv.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Input timeline CSV is outside its telemetry directory.'}
    $data=Get-InputTimelineRowsCached $csv
    $samples=@($data.samples|Where-Object{$null-ne$_.lap_index -and [int]$_.lap_index-eq$LapNo})
    $ordered=$true;$duplicates=0
    for($i=1;$i-lt$samples.Count;$i++){
        $delta=[double]$samples[$i].time_s-[double]$samples[$i-1].time_s
        if($delta-lt0){$ordered=$false};if($delta-eq0){$duplicates++}
    }
    return [ordered]@{
        schema_version=1;contract='replay_input_timeline_v1';semantic_status='candidate_functional_requires_replay_validation'
        frame_kind='replay_sample';forward_rule='binary OR of raw 62 and 67; unknown is not released'
        stream_id=$StreamId;role=[string]$stream.role;lap=$LapNo
        source_csv=[IO.Path]::GetFileName($csv);source_rows=$data.samples.Count;records=$samples.Count
        raw_fields_available=@($data.raw_fields_available);requires_reanalysis=(-not(@($data.raw_fields_available)-contains67))
        nondecreasing_time=$ordered;duplicate_time_transitions=$duplicates;samples=$samples
    }
}
