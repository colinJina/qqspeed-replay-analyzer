# Derived input observations. These rules never promote an input candidate to a native action.
function NCA-Binary($Value) {
    if($null-eq$Value){return $null};if($Value-eq1){return $true};if($Value-eq0){return $false};return $null
}
function NCA-Forward($Raw) {
    $a=NCA-Binary $Raw[2];$b=NCA-Binary $Raw[7]
    if($a-eq$true-or$b-eq$true){return $true}
    if($null-ne$a-and$null-ne$b-and-not$a-and-not$b){return $false};return $null
}
function NCA-Holds($Rows,[string]$Field,[int]$Start,[int]$End) {
    $out=New-Object System.Collections.Generic.List[object];$i=$Start
    while($i-le$End){
        if($Rows[$i].$Field-ne$true){$i++;continue}
        $first=$i;$last=$i
        while($last-lt$End-and$Rows[$last+1].$Field-eq$true-and-not$Rows[$last+1].break_before){$last++}
        $closedLeft=($first-gt0-and$null-ne$Rows[$first-1].$Field-and$Rows[$first-1].$Field-eq$false-and-not$Rows[$first].break_before)
        $closedRight=($last-lt($Rows.Count-1)-and$null-ne$Rows[$last+1].$Field-and$Rows[$last+1].$Field-eq$false-and-not$Rows[$last+1].break_before)
        $low=[Math]::Max(0.0,([double]$Rows[$last].t-[double]$Rows[$first].t))
        $high=$null;if($closedLeft-and$closedRight){$high=[double]$Rows[$last+1].t-[double]$Rows[$first-1].t}
        $out.Add([pscustomobject]@{start_i=$first;end_i=$last;start_t=$Rows[$first].t;end_t=$Rows[$last].t;samples=($last-$first+1);observed_span_s=$low;duration_lower_s=$low;duration_upper_s=$high;bounded=($closedLeft-and$closedRight)})
        $i=$last+1
    };return @($out.ToArray())
}
function NCA-SpeedStats($Rows,[int]$Start,[int]$End) {
    $values=New-Object System.Collections.Generic.List[double];$weighted=0.0;$seconds=0.0
    for($i=$Start;$i-le$End;$i++){
        if($null-eq$Rows[$i].speed-or-not$Rows[$i].pose_valid){continue}
        $values.Add([double]$Rows[$i].speed)
        if($i-gt$Start-and$Rows[$i-1].pose_valid-and-not$Rows[$i].break_before-and$null-ne$Rows[$i-1].speed){
            $dt=[double]$Rows[$i].t-[double]$Rows[$i-1].t
            if($dt-gt0){$weighted+=(([double]$Rows[$i].speed+[double]$Rows[$i-1].speed)*.5*$dt);$seconds+=$dt}
        }
    }
    $measure=$values|Measure-Object -Minimum -Maximum
    return [pscustomobject]@{entry=$Rows[$Start].speed;end=$Rows[$End].speed;minimum=$(if($values.Count){$measure.Minimum}else{$null});peak=$(if($values.Count){$measure.Maximum}else{$null});time_weighted_mean=$(if($seconds-gt0){$weighted/$seconds}else{$null});valid_samples=$values.Count;unit='m/s'}
}
function NCA-InInterval($Intervals,[double]$Time) {
    foreach($v in @($Intervals)){if($null-ne$v-and$Time-ge[double]$v.start_t-and$Time-le[double]$v.end_t){return $true}};return $false
}
function NCA-BuildActions($Samples,$Stream,[double]$ChainGapS=1.5) {
    $rows=New-Object System.Collections.Generic.List[object];$distance=0.0;$block=0;$positive=New-Object System.Collections.Generic.List[double]
    foreach($s in @($Samples)){if($null-ne$s.delta_ms-and$s.delta_ms-gt0){$positive.Add([double]$s.delta_ms/1000)}}
    $median=$(if($positive.Count){NDA-Percentile ([double[]]$positive.ToArray()) .5}else{0.0})
    $gap=[Math]::Max(.1,5*$median)
    for($i=0;$i-lt$Samples.Count;$i++){
        $s=$Samples[$i];$broken=[bool]$s.break_before
        if($i-gt0){
            $prev=$Samples[$i-1];$dt=[double]$s.time_s-[double]$prev.time_s
            if($dt-lt0-or$dt-gt$gap-or-not$s.pose_valid-or-not$prev.pose_valid){$broken=$true}
            if(-not$broken){$distance+=[Math]::Sqrt([Math]::Pow(($s.x-$prev.x),2)+[Math]::Pow(($s.y-$prev.y),2)+[Math]::Pow(($s.z-$prev.z),2))}
        }
        if($broken){$block++}
        $left=NCA-Binary $s.raw_inputs[0];$right=NCA-Binary $s.raw_inputs[1]
        $direction=$null;if($null-ne$left-and$null-ne$right){$direction=($left-xor$right)}
        $angle=$null
        if($i-gt0-and-not$broken-and$s.pose_valid-and$null-ne$s.forward_heading_rad){
            $dx=$s.x-$Samples[$i-1].x;$dy=$s.y-$Samples[$i-1].y
            if([Math]::Abs($dx)+[Math]::Abs($dy)-gt1e-6){
                $angle=([Math]::Atan2($dy,$dx)-[double]$s.forward_heading_rad)*180/[Math]::PI
                while($angle-gt180){$angle-=360};while($angle-lt-180){$angle+=360}
            }
        }
        $rows.Add([pscustomobject]@{t=[double]$s.time_s;time_s=$s.time_s;index=$s.index;x=$s.x;y=$s.y;z=$s.z;distance=$distance;pose_valid=[bool]$s.pose_valid;break_before=$broken;block=$block;speed=$s.speed;forward=(NCA-Forward $s.raw_inputs);drift=(NCA-Binary $s.raw_inputs[4]);direction=$direction;raw=$s.raw_inputs;angle_deg=$angle;native_drift=$(if($Stream.system_drift_state_available){NCA-InInterval $Stream.system_drift_segments $s.time_s}else{$null});map_propulsion=$(if($Stream.speed_effect_state_available){NCA-InInterval $Stream.map_propulsion_effect_segments $s.time_s}else{$null})})
    }
    $r=@($rows.ToArray());$stages=New-Object System.Collections.Generic.List[object];$i=0
    while($i-lt$r.Count){
        if($null-eq$r[$i].forward-or$r[$i].forward){$i++;continue}
        $start=$i;$end=$i
        while($end+1-lt$r.Count-and$null-ne$r[$end+1].forward-and-not$r[$end+1].forward-and-not$r[$end+1].break_before){$end++}
        $drift=@(NCA-Holds $r 'drift' $start $end)
        $directionCount=@($r[$start..$end]|Where-Object{$_.direction-eq$true}).Count
        if($drift.Count-gt0-and$directionCount-gt0){
            $restored=($end+1-lt$r.Count-and$r[$end+1].forward-eq$true-and-not$r[$end+1].break_before)
            $releaseObserved=($start-gt0-and$r[$start-1].forward-eq$true-and-not$r[$start].break_before)
            $last=$(if($restored){$end+1}else{$end})
            $unknown=@($r[$start..$last]|Where-Object{$null-eq$_.drift-or$null-eq$_.direction}).Count
            $nativeEnd=$null
            if($Stream.system_drift_state_available){foreach($v in @($Stream.system_drift_segments)){if($v.start_t-le$r[$end].t-and$v.end_t-ge$r[$start].t){if($null-eq$nativeEnd-or$v.end_t-gt$nativeEnd){$nativeEnd=[double]$v.end_t}}}}
            $stage=[pscustomobject]@{id=($stages.Count+1);chain=0;ordinal=0;kind='released_drift_candidate';status='requires_review';start_i=$start;end_i=$last;last_released_i=$end;start_csv_index=$r[$start].index;end_csv_index=$r[$last].index;start_t=$r[$start].t;end_t=$r[$last].t;duration_s=($r[$last].t-$r[$start].t);start_d=$r[$start].distance;end_d=$r[$last].distance;block=$r[$start].block;release_observed=$releaseObserved;forward_restored=$restored;complete=($releaseObserved-and$restored-and$unknown-eq0);unknown_input_samples=$unknown;drift_stays_active_at_restore=($restored-and$r[$last].drift-eq$true);drift_pulses=@($drift);direction_holds=@(NCA-Holds $r 'direction' $start $end);forward_released_samples=($end-$start+1);forward_release_duration_lower_s=($r[$end].t-$r[$start].t);forward_release_duration_upper_s=$(if($releaseObserved-and$restored){$r[$last].t-$r[$start-1].t}else{$null});release_to_drift_s=($drift[0].start_t-$r[$start].t);release_to_drift_lower_s=$(if($releaseObserved-and$drift[0].start_i-gt0-and$r[$drift[0].start_i-1].drift-eq$false){$r[$drift[0].start_i-1].t-$r[$start].t}else{$null});release_to_drift_upper_s=$(if($releaseObserved-and$drift[0].start_i-gt0-and$r[$drift[0].start_i-1].drift-eq$false){$drift[0].start_t-$r[$start-1].t}else{$null});native_drift_end_t=$nativeEnd;angle_start_deg=$r[$start].angle_deg;angle_end_deg=$r[$last].angle_deg;speed=(NCA-SpeedStats $r $start $last);map_propulsion_at_start=$r[$start].map_propulsion;map_propulsion_samples=$(if($Stream.speed_effect_state_available){@($r[$start..$last]|Where-Object{$_.map_propulsion-eq$true}).Count}else{$null});bridge=$null}
            if($stage.drift_stays_active_at_restore){$stage.kind='sustained_drift_candidate'}
            $stages.Add($stage)
        };$i=$end+1
    }
    $chain=0;$ordinal=0;$previous=$null
    foreach($stage in $stages){
        $linked=$false
        if($null-ne$previous-and$previous.forward_restored-and$previous.block-eq$stage.block-and($stage.start_t-$previous.end_t)-le$ChainGapS){
            $between=@($r[$previous.end_i..$stage.start_i]);$linked=(@($between|Where-Object{$null-eq$_.forward-or$_.break_before}).Count-eq0)
            if($linked){$previous.bridge=[pscustomobject]@{start_t=$previous.end_t;end_t=$stage.start_t;duration_s=($stage.start_t-$previous.end_t);start_i=$previous.end_i;end_i=$stage.start_i;forward_holds=@(NCA-Holds $r 'forward' $previous.end_i ($stage.start_i-1));speed=(NCA-SpeedStats $r $previous.end_i $stage.start_i);next_stage_id=$stage.id}}
        }
        if(-not$linked){$chain++;$ordinal=0};$ordinal++;$stage.chain=$chain;$stage.ordinal=$ordinal;$previous=$stage
    }
    return [pscustomobject]@{contract='sav_complex_actions_v1';semantic_status='candidate_requires_replay_review';rules=[pscustomobject]@{forward='nullable OR 62/67';candidate='forward released with drift input and one steering direction; one released run is one candidate';chain_gap_s=$ChainGapS;gap_break_s=$gap;super_drift='sustained drift is only a review candidate, not a decoded super-drift action';angle='signed [-180,180] pose displacement vs native heading, unavailable at zero displacement or a pose break';time_unit='seconds';frame_kind='replay_sample'};rows=$r;stages=@($stages.ToArray());sample_interval_s=$median;chain_count=$chain;raw_unknown_samples=@($r|Where-Object{$null-eq$_.forward}).Count}
}
