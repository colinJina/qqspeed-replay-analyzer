function NCA-Anchor($Stage,$Control,$Components,[string]$Side) {
    $u0=NSC-ProgressOfDistance $Control $Stage.start_d;$u1=NSC-ProgressOfDistance $Control $Stage.end_d
    if($null-eq$u0-or$null-eq$u1){return $null}
    foreach($c in @($Components)){
        $s0=NTA-SideProgressToShared $c.pairs $Side $u0;$s1=NTA-SideProgressToShared $c.pairs $Side $u1
        if($null-ne$s0-and$null-ne$s1-and$s1-ge$s0){return [pscustomobject]@{stage=$Stage;s0=$s0;s1=$s1;component=$c.component_index}}
    };return $null
}
function NCA-AtDistance($Rows,[double]$Distance) {
    if($Rows.Count-lt2-or$Distance-lt$Rows[0].distance-or$Distance-gt$Rows[$Rows.Count-1].distance){return $null}
    $lo=0;$hi=$Rows.Count-1
    while($hi-$lo-gt1){$m=[int][Math]::Floor(($lo+$hi)/2);if($Rows[$m].distance-le$Distance){$lo=$m}else{$hi=$m}}
    $a=$Rows[$lo];$b=$Rows[$hi]
    if($b.break_before-or-not$a.pose_valid-or-not$b.pose_valid-or$b.distance-le$a.distance){return $null}
    $f=($Distance-$a.distance)/($b.distance-$a.distance)
    return [pscustomobject]@{t=($a.t+($b.t-$a.t)*$f);speed=$(if($null-ne$a.speed-and$null-ne$b.speed){$a.speed+($b.speed-$a.speed)*$f}else{$null});sample_span_s=($b.t-$a.t);index=$a.index;x=($a.x+($b.x-$a.x)*$f);y=($a.y+($b.y-$a.y)*$f)}
}
function NCA-SharedPoint($Component,[double]$S,$RowsA,$RowsB) {
    $p=NTA-SharedProgressToSides $Component.pairs $S;if($null-eq$p){return $null}
    $a=NCA-AtDistance $RowsA $p.a_d;$b=NCA-AtDistance $RowsB $p.b_d
    if($null-eq$a-or$null-eq$b){return $null};return [pscustomobject]@{s=$S;a=$a;b=$b}
}
function NCA-MappingQuality($Component,[double]$S) {
    $p=@($Component.pairs);$lo=0;$hi=$p.Count-1
    if($p.Count-lt2){return [pscustomobject]@{separation_m=$null;heading_deg=$null;control_span_s=$null}}
    while($hi-$lo-gt1){$m=[int][Math]::Floor(($lo+$hi)/2);if($p[$m].s-le$S){$lo=$m}else{$hi=$m}}
    return [pscustomobject]@{separation_m=[Math]::Max([double]$p[$lo].separation_m,[double]$p[$hi].separation_m);heading_deg=[Math]::Max([double]$p[$lo].heading_delta_deg,[double]$p[$hi].heading_delta_deg);control_span_s=[Math]::Max(($p[$hi].a_t-$p[$lo].a_t),($p[$hi].b_t-$p[$lo].b_t))}
}
function NCA-BuildComparison($SideA,$SideB) {
    $gate=NSC-IdentityGate $SideA $SideB
    $result=[ordered]@{contract='sav_complex_comparison_v1';identity=$gate;status='unavailable';time_basis='A minus B over the same mapped spatial interval; natural durations are separate; overlapping windows are not additive';matches=@();unmatched_a=@();unmatched_b=@();chains=@();alignment=$null}
    if(-not$gate.comparable){$result.status=$gate.status;return [pscustomobject]$result}
    # Canonical alignment makes swapping A/B preserve geometry and negate signed time metrics.
    $swapped=([string]$SideA.key).CompareTo([string]$SideB.key)-gt0
    $a=$(if($swapped){$SideB}else{$SideA});$b=$(if($swapped){$SideA}else{$SideB})
    $cpA=@(NTA-TrajectoryControlPoints $a.actions.rows 0 ($a.actions.rows.Count-1) -MinStepM 1 -MaxPoints 600)
    $cpB=@(NTA-TrajectoryControlPoints $b.actions.rows 0 ($b.actions.rows.Count-1) -MinStepM 1 -MaxPoints 600)
    $sp=NTA-SharedCorrespondence $cpA $cpB -MaxSeparationM 15 -MaxHeadingDeltaDeg 45
    $result.alignment=$sp.stats
    # The shared kernel bounds progress gaps; additionally forbid crossing either pose block.
    $components=New-Object System.Collections.Generic.List[object]
    foreach($c in @($sp.components)){
        $part=New-Object System.Collections.Generic.List[object];$previous=$null
        foreach($p in @($c.pairs)){
            if($null-ne$previous-and($p.a_block-ne$previous.a_block-or$p.b_block-ne$previous.b_block)){
                $components.Add([pscustomobject]@{component_index=$components.Count;pairs=@($part.ToArray())});$part.Clear()
            };$part.Add($p);$previous=$p
        };if($part.Count){$components.Add([pscustomobject]@{component_index=$components.Count;pairs=@($part.ToArray())})}
    }
    $components=@($components.ToArray())
    $aa=@();$bb=@()
    foreach($s in @($a.actions.stages)){$anchor=NCA-Anchor $s $cpA $components 'a';if($null-ne$anchor){$aa+=,$anchor}}
    foreach($s in @($b.actions.stages)){$anchor=NCA-Anchor $s $cpB $components 'b';if($null-ne$anchor){$bb+=,$anchor}}
    $edges=@()
    foreach($x in $aa){foreach($y in $bb){
        if($x.component-ne$y.component-or$x.stage.kind-ne$y.stage.kind){continue}
        $separation=[Math]::Sqrt([Math]::Pow(($a.actions.rows[$x.stage.start_i].x-$b.actions.rows[$y.stage.start_i].x),2)+[Math]::Pow(($a.actions.rows[$x.stage.start_i].y-$b.actions.rows[$y.stage.start_i].y),2))
        if([Math]::Abs($x.s0-$y.s0)-le.03-and$separation-le25){$edges+=,[pscustomobject]@{a=$x;b=$y;cost=[Math]::Abs($x.s0-$y.s0);separation_m=$separation}}
    }}
    $matches=New-Object System.Collections.Generic.List[object];$usedA=@{};$usedB=@{};$lastB=-1
    foreach($x in $aa){
        $candidates=@($edges|Where-Object{$_.a.stage.id-eq$x.stage.id}|Sort-Object cost)
        if(-not$candidates.Count){continue};$edge=$candidates[0]
        $reverse=@($edges|Where-Object{$_.b.stage.id-eq$edge.b.stage.id}|Sort-Object cost)
        # Mutual unique nearest stages; missing cards never shift all later ordinals.
        if($reverse[0].a.stage.id-ne$x.stage.id-or($candidates.Count-gt1-and$candidates[1].cost-$edge.cost-lt.001)-or($reverse.Count-gt1-and$reverse[1].cost-$edge.cost-lt.001)-or$edge.b.stage.id-le$lastB){continue}
        $y=$edge.b;$c=$components[$x.component]
        $s0=[Math]::Min($x.s0,$y.s0);$s1=[Math]::Max($x.s1,$y.s1)
        $start=NCA-SharedPoint $c $s0 $a.actions.rows $b.actions.rows;$end=NCA-SharedPoint $c $s1 $a.actions.rows $b.actions.rows
        $onset=NCA-SharedPoint $c $y.s0 $a.actions.rows $b.actions.rows
        $opposite=NCA-SharedPoint $c $x.s0 $a.actions.rows $b.actions.rows
        $offset=$null;$mapped=$null
        if($swapped-and$null-ne$opposite){$offset=$y.stage.start_t-$opposite.b.t;$mapped=$opposite.b}
        elseif(-not$swapped-and$null-ne$onset){$offset=$x.stage.start_t-$onset.a.t;$mapped=$onset.a}
        $da=$null;$db=$null;$delta=$null
        if($null-ne$start-and$null-ne$end-and$s1-gt$s0){$da=$end.a.t-$start.a.t;$db=$end.b.t-$start.b.t;$delta=$da-$db}
        $stageA=$(if($swapped){$y.stage}else{$x.stage});$stageB=$(if($swapped){$x.stage}else{$y.stage})
        $resolution=$SideA.actions.sample_interval_s+$SideB.actions.sample_interval_s
        if($null-ne$mapped){$resolution+=$mapped.sample_span_s}
        # A resolution estimate, not a guaranteed error bound on spatial matching.
        $quality=NCA-MappingQuality $c $(if($swapped){$x.s0}else{$y.s0})
        if($null-ne$quality.control_span_s){$resolution+=$quality.control_span_s}
        if($null-ne$mapped-and$null-ne$mapped.speed-and$mapped.speed-gt1-and$null-ne$quality.separation_m){$resolution+=$quality.separation_m/$mapped.speed}
        $matches.Add([pscustomobject]@{a_stage_id=$stageA.id;b_stage_id=$stageB.id;kind=$stageA.kind;status='matched_candidate';shared_component=$x.component;shared_start_s=$s0;shared_end_s=$s1;common_a_duration_s=$(if($swapped){$db}else{$da});common_b_duration_s=$(if($swapped){$da}else{$db});common_time_delta_s=$(if($null-eq$delta){$null}elseif($swapped){-$delta}else{$delta});natural_duration_delta_s=($stageA.duration_s-$stageB.duration_s);peak_speed_delta=$(if($null-ne$stageA.speed.peak-and$null-ne$stageB.speed.peak){$stageA.speed.peak-$stageB.speed.peak}else{$null});onset_equivalent_offset_s=$offset;onset_shared_progress_delta=$(if($swapped){$y.s0-$x.s0}else{$x.s0-$y.s0});onset_resolution_estimate_s=$resolution;onset_separation_m=$edge.separation_m;mapping_quality=$quality;mapped_reference_on_a=$mapped;a=$stageA;b=$stageB;common_start=$(if($swapped-and$null-ne$start){[pscustomobject]@{s=$start.s;a=$start.b;b=$start.a}}else{$start});common_end=$(if($swapped-and$null-ne$end){[pscustomobject]@{s=$end.s;a=$end.b;b=$end.a}}else{$end})})
        $usedA[[string]$x.stage.id]=$true;$usedB[[string]$y.stage.id]=$true;$lastB=$y.stage.id
    }
    $result.matches=@($matches.ToArray())
    $groups=@{}
    foreach($m in $matches){$key=[string]$m.a.chain+':'+[string]$m.b.chain+':'+[string]$m.shared_component;if(-not$groups.ContainsKey($key)){$groups[$key]=@()};$groups[$key]+=,$m}
    $chains=@()
    foreach($groupKey in @($groups.Keys|Sort-Object)){
        $group=@($groups[$groupKey]);$first=$group[0]
        $s0=($group|Measure-Object shared_start_s -Minimum).Minimum;$s1=($group|Measure-Object shared_end_s -Maximum).Maximum
        $start=NCA-SharedPoint $components[$first.shared_component] $s0 $a.actions.rows $b.actions.rows;$end=NCA-SharedPoint $components[$first.shared_component] $s1 $a.actions.rows $b.actions.rows
        $timeA=$null;$timeB=$null
        if($null-ne$start-and$null-ne$end){$timeA=$end.a.t-$start.a.t;$timeB=$end.b.t-$start.b.t}
        $chains+=,[pscustomobject]@{a_chain=$first.a.chain;b_chain=$first.b.chain;matched_stages=$group.Count;a_stage_ids=@($group|ForEach-Object{$_.a_stage_id});b_stage_ids=@($group|ForEach-Object{$_.b_stage_id});shared_component=$first.shared_component;common_a_duration_s=$(if($swapped){$timeB}else{$timeA});common_b_duration_s=$(if($swapped){$timeA}else{$timeB});common_time_delta_s=$(if($null-eq$timeA-or$null-eq$timeB){$null}elseif($swapped){$timeB-$timeA}else{$timeA-$timeB});covers_complete_a_chain=(@($SideA.actions.stages|Where-Object{$_.chain-eq$first.a.chain}).Count-eq$group.Count);covers_complete_b_chain=(@($SideB.actions.stages|Where-Object{$_.chain-eq$first.b.chain}).Count-eq$group.Count)}
    };$result.chains=$chains
    $unA=@($a.actions.stages|Where-Object{-not$usedA.ContainsKey([string]$_.id)}|ForEach-Object{[pscustomobject]@{stage_id=$_.id;reason='no_unique_ordered_spatial_match'}})
    $unB=@($b.actions.stages|Where-Object{-not$usedB.ContainsKey([string]$_.id)}|ForEach-Object{[pscustomobject]@{stage_id=$_.id;reason='no_unique_ordered_spatial_match'}})
    $result.unmatched_a=$(if($swapped){$unB}else{$unA});$result.unmatched_b=$(if($swapped){$unA}else{$unB})
    $result.status=$(if($matches.Count){'ready_candidate_review_required'}else{'unavailable_no_unique_stage_match'})
    return [pscustomobject]$result
}
