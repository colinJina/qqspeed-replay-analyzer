function Get-ComplexActionSide($Selection) {
    $name=[string]$Selection.file;$lap=0
    if(-not[int]::TryParse([string]$Selection.lap,[ref]$lap)-or$lap-lt1){throw 'A positive lap is required.'}
    $timeline=Get-InputTimelineLocal $name ([string]$Selection.stream) $lap
    if(-not$timeline.nondecreasing_time){throw 'Complex analysis requires nondecreasing sample times.'}
    $fp=Get-AnalysisPath $name;if($null-eq$fp){throw 'Analysis not found.'}
    $analysis=Read-JsonFile $fp;$path=Get-TelemetryPathForAnalysis $name;$tel=Read-JsonFile $path
    $s=@($tel.streams|Where-Object{[string]$_.id-eq[string]$Selection.stream})[0]
    if($null-eq$s){throw 'Explicit stream required.'}
    $csv=Join-Path (Split-Path -Parent $path) ([string]$s.csv)
    $signature=(@($fp,$path,$csv)|ForEach-Object{$f=Get-Item -LiteralPath $_;[string]$f.Length+':'+[string]$f.LastWriteTimeUtc.Ticks})-join'|'
    $cacheKey=$name+'|'+[string]$Selection.stream+'|'+$lap+'|'+[string]$Selection.start_t+'|'+[string]$Selection.end_t+'|'+$signature
    if($null-eq$script:complexSideCache){$script:complexSideCache=@{}}
    if($script:complexSideCache.ContainsKey($cacheKey)){return $script:complexSideCache[$cacheKey]}
    $actions=NCA-BuildActions $timeline.samples $s
    # A focus range selects complete natural candidates; it never clips their endpoints.
    if($null-ne$Selection.start_t-or$null-ne$Selection.end_t){
        $start=NAS-Num $Selection.start_t;$end=NAS-Num $Selection.end_t
        if($null-eq$start-or$null-eq$end-or$end-le$start){throw 'Focus range requires finite start < end.'}
        $actions.stages=@($actions.stages|Where-Object{$_.start_t-ge$start-and$_.start_t-le$end})
    }
    $mapName=$(if($analysis.map_name){[string]$analysis.map_name}else{Analysis-MapName $analysis})
    $side=[pscustomobject]@{key=([string]$tel.source_sha256+':'+$name+':'+[string]$s.id+':'+$lap);signature=$cacheKey;file=$name;stream=[string]$s.id;role=[string]$s.role;lap=$lap;resource_map_id=$(if($null-ne$analysis.resource_map_id){$analysis.resource_map_id}else{$analysis.map_id});game_map_id=$analysis.game_map_id;map_name=$mapName;map_name_key=(Comparison-MapNameKey $mapName);source_sha256=$tel.source_sha256;requires_reanalysis=$timeline.requires_reanalysis;actions=$actions}
    if($script:complexSideCache.Count-ge6){$script:complexSideCache=@{}};$script:complexSideCache[$cacheKey]=$side
    return $side
}
function Get-ComplexComparisonCached($A,$B) {
    if($null-eq$script:complexPairCache){$script:complexPairCache=@{}}
    $key=$A.signature+'::'+$B.signature
    if($script:complexPairCache.ContainsKey($key)){return $script:complexPairCache[$key]}
    $comparison=NCA-BuildComparison $A $B
    if($script:complexPairCache.Count-ge12){$script:complexPairCache=@{}};$script:complexPairCache[$key]=$comparison
    return $comparison
}
function Get-ComplexActionPublic($Side) {
    return [ordered]@{contract=$Side.actions.contract;file=$Side.file;stream=$Side.stream;role=$Side.role;lap=$Side.lap;source_sha256=$Side.source_sha256;requires_reanalysis=$Side.requires_reanalysis;semantic_status=$Side.actions.semantic_status;rules=$Side.actions.rules;stages=@($Side.actions.stages);chain_count=$Side.actions.chain_count;sample_interval_s=$Side.actions.sample_interval_s;unknown_forward_samples=$Side.actions.raw_unknown_samples;curve=@($Side.actions.rows|ForEach-Object{[pscustomobject]@{t=$_.t;speed=$_.speed;index=$_.index;pose_valid=$_.pose_valid;break_before=$_.break_before;angle_deg=$_.angle_deg;native_drift=$_.native_drift;map_propulsion=$_.map_propulsion}})}
}
function Invoke-ComplexActionComparisonLocal($Req) {
    $a=Get-ComplexActionSide $Req.subject;$b=$null;$comparison=$null
    if($null-ne$Req.baseline){$b=Get-ComplexActionSide $Req.baseline;$comparison=Get-ComplexComparisonCached $a $b}
    return [ordered]@{ok=$true;subject=(Get-ComplexActionPublic $a);baseline=$(if($null-ne$b){Get-ComplexActionPublic $b}else{$null});comparison=$comparison}
}
