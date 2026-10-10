# Deterministic comparison guidance. User declarations are recorded as declarations, not decoded facts.
function NRG-Distribution($Values) {
    $v=@($Values|Where-Object{$null-ne$_}|ForEach-Object{[double]$_}|Sort-Object)
    return [pscustomobject]@{count=$v.Count;median=$(if($v.Count){NDA-Percentile ([double[]]$v) .5}else{$null});p25=$(if($v.Count){NDA-Percentile ([double[]]$v) .25}else{$null});p75=$(if($v.Count){NDA-Percentile ([double[]]$v) .75}else{$null});min=$(if($v.Count){$v[0]}else{$null});max=$(if($v.Count){$v[$v.Count-1]}else{$null})}
}
function NRG-Strategy($Stages) {return (@($Stages|ForEach-Object{[string]$_.kind})-join'>')}
function NRG-Build($Subject,$References,$Declarations) {
    $seen=@{};$accepted=New-Object System.Collections.Generic.List[object];$rejected=New-Object System.Collections.Generic.List[object]
    $strategy=NRG-Strategy $Subject.actions.stages
    foreach($ref in @($References)){
        if($null-ne$ref.error){$rejected.Add([pscustomobject]@{file=$ref.file;reason='reference_load_failed';error=$ref.error});continue}
        $b=$ref.side;$c=$ref.comparison
        $identity=[string]$b.source_sha256+':'+[string]$b.stream+':'+[string]$b.lap
        if([string]::IsNullOrWhiteSpace([string]$b.source_sha256)){$identity=$b.key}
        $subjectIdentity=[string]$Subject.source_sha256+':'+[string]$Subject.stream+':'+[string]$Subject.lap
        $reason=$null
        if($identity-eq$subjectIdentity){$reason='subject_cannot_reference_itself'}
        elseif($seen.ContainsKey($identity)){$reason='duplicate_replay_stream_lap'}
        elseif(-not$c.identity.comparable){$reason='map_identity_conflict_or_unknown'}
        elseif((NRG-Strategy $b.actions.stages)-ne$strategy){$reason='different_candidate_strategy_or_missing_stage'}
        elseif(@($c.matches).Count-ne@($Subject.actions.stages).Count-or-not@($c.matches).Count){$reason='incomplete_or_ambiguous_stage_correspondence'}
        if($null-ne$reason){$rejected.Add([pscustomobject]@{file=$b.file;reason=$reason});continue}
        $seen[$identity]=$true;$accepted.Add($ref)
    }
    $items=New-Object System.Collections.Generic.List[object]
    foreach($stage in @($Subject.actions.stages)){
        $evidence=@()
        foreach($r in $accepted){
            $m=@($r.comparison.matches|Where-Object{$_.a_stage_id-eq$stage.id})[0]
            if($null-eq$m){continue}
            $evidence+=,[pscustomobject]@{reference_file=$r.side.file;reference_stream=$r.side.stream;reference_lap=$r.side.lap;reference_sha256=$r.side.source_sha256;reference_stage_id=$m.b_stage_id;subject_start_t=$stage.start_t;subject_end_t=$stage.end_t;reference_start_t=$m.b.start_t;reference_end_t=$m.b.end_t;reference_start_csv_index=$m.b.start_csv_index;reference_end_csv_index=$m.b.end_csv_index;onset_offset_s=$m.onset_equivalent_offset_s;resolution_estimate_s=$m.onset_resolution_estimate_s;common_time_delta_s=$m.common_time_delta_s;common_start=$m.common_start;common_end=$m.common_end;mapped_reference_on_a=$m.mapped_reference_on_a;reference_peak_speed=$m.b.speed.peak;reference_min_speed=$m.b.speed.minimum;reference_bridge_s=$(if($null-ne$m.b.bridge){$m.b.bridge.duration_s}else{$null});reference_drift_samples=(@($m.b.drift_pulses|ForEach-Object{$_.samples}|Measure-Object -Sum).Sum);match=$m}
        }
        $offset=NRG-Distribution @($evidence|ForEach-Object{$_.onset_offset_s});$time=NRG-Distribution @($evidence|ForEach-Object{$_.common_time_delta_s})
        $reasons=New-Object System.Collections.Generic.List[string]
        if(-not[bool]$Declarations.inputs_and_stages_reviewed){$reasons.Add('input_and_stage_review_missing')}
        if(-not[bool]$Declarations.same_vehicle_configuration){$reasons.Add('vehicle_configuration_not_confirmed')}
        if([string]::IsNullOrWhiteSpace([string]$Declarations.vehicle_configuration_note)){$reasons.Add('vehicle_configuration_note_missing')}
        if(-not[bool]$Declarations.same_strategy_reviewed){$reasons.Add('strategy_not_reviewed')}
        if($offset.count-eq0){$reasons.Add('no_comparable_reference')}
        $resolution=$null
        if($evidence.Count){$resolution=($evidence|Measure-Object resolution_estimate_s -Maximum).Maximum}
        $positive=@($evidence|Where-Object{$null-ne$_.onset_offset_s-and$_.onset_offset_s-gt$_.resolution_estimate_s}).Count
        $negative=@($evidence|Where-Object{$null-ne$_.onset_offset_s-and$_.onset_offset_s-lt(-$_.resolution_estimate_s)}).Count
        if($offset.count-and($positive-ne$offset.count-and$negative-ne$offset.count)){$reasons.Add('references_disagree_or_difference_below_resolution')}
        foreach($e in $evidence){
            $m=$e.match;$a=$m.a;$b=$m.b
            if(-not$a.complete-or-not$b.complete){$reasons.Add('incomplete_input_boundaries')}
            if($null-eq$m.mapping_quality.separation_m-or$m.mapping_quality.separation_m-gt3-or$m.mapping_quality.heading_deg-gt25){$reasons.Add('spatial_alignment_too_uncertain')}
            if($null-eq$a.speed.entry-or$null-eq$b.speed.entry-or[Math]::Abs($a.speed.entry-$b.speed.entry)-gt([Math]::Max(1.0,[double]$b.speed.entry)*.1)){$reasons.Add('entry_speed_differs_more_than_10_percent')}
            if($null-eq$a.angle_start_deg-or$null-eq$b.angle_start_deg-or[Math]::Abs($a.angle_start_deg-$b.angle_start_deg)-gt20){$reasons.Add('entry_heading_state_not_comparable')}
            if($null-eq$a.map_propulsion_at_start-or$null-eq$b.map_propulsion_at_start){$reasons.Add('native_propulsion_evidence_missing')}
            elseif($a.map_propulsion_at_start-ne$b.map_propulsion_at_start){$reasons.Add('propulsion_context_differs')}
            $timeAdvantage=($null-ne$m.common_time_delta_s-and$m.common_time_delta_s-gt0)
            $peakAdvantage=($null-ne$a.speed.peak-and$null-ne$b.speed.peak-and$b.speed.peak-gt$a.speed.peak)
            if(-not$timeAdvantage-and-not$peakAdvantage){$reasons.Add('reference_has_no_observed_time_or_peak_advantage')}
        }
        $available=($reasons.Count-eq0)
        $direction=$(if($available-and$offset.median-gt0){'try_earlier_at_reference_position'}elseif($available){'try_later_at_reference_position'}else{'observation_only'})
        $items.Add([pscustomobject]@{rule_id='reference_onset_position_v1';stage_id=$stage.id;chain=$stage.chain;ordinal=$stage.ordinal;status=$(if($available){'reference_relative_trial'}else{'observation_only'});direction=$direction;trial_shift_s=$(if($available){-$offset.median}else{$null});onset_offset_s=$offset;common_time_delta_s=$time;reference_peak_speed=(NRG-Distribution @($evidence|ForEach-Object{$_.reference_peak_speed}));reference_min_speed=(NRG-Distribution @($evidence|ForEach-Object{$_.reference_min_speed}));reference_bridge_s=(NRG-Distribution @($evidence|ForEach-Object{$_.reference_bridge_s}));reference_drift_samples=(NRG-Distribution @($evidence|ForEach-Object{$_.reference_drift_samples}));resolution_estimate_s=$resolution;unavailable_reasons=@($reasons.ToArray()|Select-Object -Unique);evidence=@($evidence|Select-Object * -ExcludeProperty match)})
    }
    return [pscustomobject]@{contract='reference_guidance_v1';authority='deterministic_reference_comparison_not_causal_or_optimal';declarations=$Declarations;declaration_source='user_statement_not_sav_metadata';strategy_signature=$strategy;accepted_reference_count=$accepted.Count;distinct_sav_count=@($accepted|ForEach-Object{$_.side.source_sha256}|Select-Object -Unique).Count;rejected_references=@($rejected.ToArray());items=@($items.ToArray());limits='trial relative to selected references; no promised gain, success score, physical key travel or RT millimetres'}
}
