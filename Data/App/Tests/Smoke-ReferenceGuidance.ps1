param([string]$AppDir=(Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))
$ErrorActionPreference='Stop'
. (Join-Path $AppDir 'Tests\Smoke-ComplexActions.ps1')
. (Join-Path $AppDir 'Modules\Native\NativeReferenceGuidance.ps1')
function RefSide([string]$Key,[int]$Shift=0){
    $s=Side $Key (Samples -Shift $Shift)
    $s|Add-Member source_sha256 $Key;$s|Add-Member file ($Key+'.json');$s|Add-Member stream 'local';$s|Add-Member lap 1
    return $s
}
$subject=RefSide 'subject' 5;$ref=RefSide 'ref-a';$ref2=RefSide 'ref-b' -1
foreach($s in @($ref,$ref2)){foreach($stage in $s.actions.stages){$stage.speed.peak=27}}
$entries=@([pscustomobject]@{side=$ref;comparison=(NCA-BuildComparison $subject $ref)},[pscustomobject]@{side=$ref2;comparison=(NCA-BuildComparison $subject $ref2)})
$decl=[pscustomobject]@{inputs_and_stages_reviewed=$true;same_vehicle_configuration=$true;vehicle_configuration_note='synthetic test configuration';same_strategy_reviewed=$true}
$report=NRG-Build $subject $entries $decl
Require ($report.accepted_reference_count-eq2-and$report.items[0].status-eq'reference_relative_trial') 'Comparable references did not yield a relative trial.'
Require (Approx $report.items[0].trial_shift_s (-.22)) 'Reference median incorrectly includes prefix or uses the wrong side time basis.'
Require ($report.items[0].evidence.Count-eq2-and$report.distinct_sav_count-eq2) 'Guidance lost reference evidence.'
$duplicate=NRG-Build $subject @($entries[0],$entries[0]) $decl
Require ($duplicate.accepted_reference_count-eq1-and$duplicate.rejected_references[0].reason-eq'duplicate_replay_stream_lap') 'Duplicate SAV inflated reference sample count.'
$decl.same_vehicle_configuration=$false;$blocked=NRG-Build $subject $entries $decl
Require ($null-eq$blocked.items[0].trial_shift_s-and$blocked.items[0].unavailable_reasons-contains'vehicle_configuration_not_confirmed') 'Unknown vehicle configuration still emitted seconds advice.'
$decl.same_vehicle_configuration=$true;$opposite=RefSide 'ref-c' 12
foreach($s in $opposite.actions.stages){$s.speed.peak=27}
$disagree=NRG-Build $subject @($entries[0],[pscustomobject]@{side=$opposite;comparison=(NCA-BuildComparison $subject $opposite)}) $decl
Require ($disagree.items[0].status-eq'observation_only'-and$disagree.items[0].unavailable_reasons-contains'references_disagree_or_difference_below_resolution') 'Opposing references were hidden by a median.'
$missing=RefSide 'missing';$missing.actions.stages=@($missing.actions.stages|Where-Object{$_.id-ne2})
$excluded=NRG-Build $subject @([pscustomobject]@{side=$missing;comparison=(NCA-BuildComparison $subject $missing)}) $decl
Require ($excluded.accepted_reference_count-eq0-and$excluded.rejected_references[0].reason-eq'different_candidate_strategy_or_missing_stage') 'Different strategy was silently mixed.'
$close=RefSide 'close' 4;foreach($s in $close.actions.stages){$s.speed.peak=27}
$small=NRG-Build $subject @([pscustomobject]@{side=$close;comparison=(NCA-BuildComparison $subject $close)}) $decl
Require ($small.items[0].status-eq'observation_only') 'Difference below sample/mapping resolution produced precise advice.'
$entries[0].comparison.matches[0].a.complete=$false
$incomplete=NRG-Build $subject @($entries[0]) $decl
Require ($incomplete.items[0].unavailable_reasons-contains'incomplete_input_boundaries') 'Incomplete input phase still yielded advice.'
Write-Host '[OK] Reference guidance: comparable strategy, distinct sources, distributions, evidence, declarations, disagreements and resolution gates.'
