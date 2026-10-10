param([string]$AppDir=(Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))
$ErrorActionPreference='Stop'
foreach($name in @('NativeDrivingAnalysis','NativeDrivingEpisodes','NativeTrainingSections','NativeTrainingTimeLoss','NativeAnalysisSegments','NativeSegmentComparison','NativeComplexActions','NativeComplexComparison')){. (Join-Path $AppDir ('Modules\Native\'+$name+'.ps1'))}
function Require([bool]$Value,[string]$Message){if(-not$Value){throw $Message}}
function Approx($A,$B,[double]$E=.000001){return ($null-ne$A-and$null-ne$B-and[math]::Abs($A-$B)-le$E)}
function Samples([double]$Prefix=0,[double]$Speed=25,[int]$Shift=0,[int]$Missing=-1){
    $r=@()
    for($i=0;$i-le300;$i++){
        $raw=@(1,0,1,0,0,0,0,0)
        for($k=0;$k-lt4;$k++){
            if($k-eq$Missing){continue};$start=40+50*$k+$Shift
            if($i-ge$start-and$i-lt$start+20){$raw[2]=0;if($i-lt$start+5){$raw[4]=1}}
        }
        $r+=,[pscustomobject]@{index=$i;time_s=($Prefix+$i/$Speed);delta_ms=$(if($i){1000/$Speed}else{$null});x=[double]$i;y=0.0;z=0.0;speed=$Speed;lap_index=1;pose_valid=$true;break_before=$false;forward_heading_rad=0.0;raw_inputs=$raw}
    };return $r
}
$stream=[pscustomobject]@{system_drift_state_available=$true;system_drift_segments=@([pscustomobject]@{start_t=1.6;end_t=2.5});speed_effect_state_available=$true;map_propulsion_effect_segments=@([pscustomobject]@{start_t=0;end_t=20})}
function Side([string]$Key,$Rows){return [pscustomobject]@{key=$Key;resource_map_id=7;game_map_id=$null;map_name_key='sample-map';actions=(NCA-BuildActions $Rows $stream)}}
$a=Side 'a' (Samples -Prefix 5 -Speed 20 -Shift 5);$b=Side 'b' (Samples)
Require ($a.actions.stages.Count-eq4) 'Candidate count was forced or lost.'
Require ($a.actions.stages[0].bridge.forward_holds[0].samples-eq30) 'Forward bridge sample count is wrong.'
$pulse=$a.actions.stages[0].drift_pulses[0]
Require (Approx $pulse.duration_lower_s .2) 'Hold lower duration ignores observed timestamps.'
Require (Approx $pulse.duration_upper_s .3) 'Hold upper duration must include surrounding released samples.'
Require (Approx $a.actions.stages[0].release_to_drift_lower_s (-.05)) 'Same-sample input changes cannot establish sub-sample ordering.'
Require (Approx $a.actions.stages[0].release_to_drift_upper_s .05) 'Onset ordering uncertainty must retain both sample intervals.'
Require ($a.actions.stages[0].map_propulsion_samples-eq21) 'Native map propulsion evidence lost.'
$ab=NCA-BuildComparison $a $b;$ba=NCA-BuildComparison $b $a
Require ($ab.matches.Count-eq4-and$ba.matches.Count-eq4) 'Unique stages did not match.'
Require (Approx $ab.chains[0].common_time_delta_s (-$ba.chains[0].common_time_delta_s)) 'Shared chain timing must include bridges and negate on swap.'
for($i=0;$i-lt4;$i++){
    Require (Approx $ab.matches[$i].common_time_delta_s (-$ba.matches[$i].common_time_delta_s)) 'Common-space delta does not negate on swap.'
    Require (Approx $ab.matches[$i].onset_equivalent_offset_s .25) 'Absolute prefix delay leaked into onset guidance.'
    Require (Approx $ab.matches[$i].natural_duration_delta_s .2) 'Natural duration must remain separate from common time.'
}
$missing=Side 'c' (Samples -Missing 1);$cmp=NCA-BuildComparison $b $missing
Require ($cmp.matches.Count-eq3-and$cmp.matches[1].a_stage_id-eq3-and$cmp.matches[1].b_stage_id-eq2) 'Missing card shifted subsequent correspondence.'
$missing.resource_map_id=8;Require (-not(NCA-BuildComparison $b $missing).identity.comparable) 'Map conflict was ignored.'
$raw=Samples
for($i=40;$i-lt60;$i++){$raw[$i].raw_inputs[7]=1}
Require ((NCA-BuildActions $raw $stream).stages.Count-eq3) 'Single-channel release incorrectly became full forward release.'
$raw=Samples;$raw[43].raw_inputs[4]=255
Require (-not(NCA-BuildActions $raw $stream).stages[0].complete) 'Nonbinary drift was promoted to known input.'
$raw=Samples;$raw[50].break_before=$true
Require (-not(NCA-BuildActions $raw $stream).stages[0].forward_restored) 'Input phase crossed a pose break.'
$raw=Samples;$raw[50].time_s=$raw[49].time_s;$raw[50].delta_ms=0
$dup=NCA-BuildActions $raw $stream
Require ($dup.rows.Count-eq301-and$dup.stages[0].forward_released_samples-eq20) 'Equal-time record was dropped.'
$raw=Samples;for($i=0;$i-lt60;$i++){$raw[$i].raw_inputs[2]=0};$open=NCA-BuildActions $raw $stream
Require (-not$open.stages[0].release_observed) 'Open left boundary became a complete card.'
$raw=Samples;for($i=190;$i-le210;$i++){$raw[$i].raw_inputs[4]=1};$sustained=NCA-BuildActions $raw $stream
Require ($sustained.stages[3].kind-eq'sustained_drift_candidate') 'Sustained drift evidence disappeared.'
Write-Host '[OK] Complex candidates: native boundaries, hold bounds, OR, unknowns, duplicates, natural endpoints, missing cards, spatial timing and swap.'
