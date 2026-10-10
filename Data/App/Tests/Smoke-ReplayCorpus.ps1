param([string]$AppDir=(Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))
$ErrorActionPreference='Stop'
. (Join-Path $AppDir 'Tests\September2026Corpus.ps1')
. (Join-Path $AppDir 'Tests\TrainingAnalysisCorpus.ps1')
function Require([bool]$Ok,[string]$Message){if(-not$Ok){throw $Message}}
$tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
$fixture=Join-Path $tempBase ('QQReplayCorpus_'+[guid]::NewGuid().ToString('N'))
try {
    Require (@(Get-September2026Corpus -ProjectRoot $fixture).Count-eq0) 'Missing directories must not fabricate a corpus.'
    $userDir=Join-Path $fixture 'replay';$archiveDir=Join-Path $fixture 'Data\ReplayArchive\copy'
    New-Item -ItemType Directory -Force $userDir,$archiveDir|Out-Null
    $user=Join-Path $userDir 'sample-map-20260910-121314-control.sav'
    [IO.File]::WriteAllBytes($user,[byte[]]@(1,2,3))
    [IO.File]::WriteAllBytes((Join-Path $archiveDir 'alias-20260911-101010-control.sav'),[byte[]]@(1,2,3))
    [IO.File]::WriteAllBytes((Join-Path $archiveDir 'sample-20260912-020304-control.sav'),[byte[]]@(4,5,6))
    [IO.File]::WriteAllBytes((Join-Path $archiveDir 'sample-20261001-020304-control.sav'),[byte[]]@(7,8,9))
    [IO.File]::WriteAllBytes((Join-Path $archiveDir 'sample-20260931-020304-control.sav'),[byte[]]@(10,11,12))
    [IO.File]::WriteAllBytes((Join-Path $archiveDir 'undated.sav'),[byte[]]@(13,14,15))
    $snapshot=@(Get-ChildItem $fixture -Recurse -File|ForEach-Object{[string]$_.FullName+'|'+$_.LastWriteTimeUtc.Ticks+'|'+(Get-ReplayFileSha256Hex $_.FullName)})
    $corpus=@(Get-September2026Corpus -ProjectRoot $fixture)
    Require ($corpus.Count-eq2) 'September selection or SHA deduplication is wrong.'
    $primary=@($corpus|Where-Object{$_.sha256-eq(Get-ReplayFileSha256Hex $user)})[0]
    Require ($primary.source_path-eq$user-and$primary.corpus-eq'mandatory_user') 'User corpus must take precedence over archive aliases.'
    Require ($corpus[0].sha256-lt$corpus[1].sha256-and$corpus[0].test_id-eq'S01') 'Anonymous ids must follow sorted SHA.'
    Require ($null-eq(Get-SeptemberRecordedTimeFromName 'sample-20260931-020304-control.sav')) 'Invalid calendar date was accepted.'
    Require ($null-eq(Get-SeptemberRecordedTimeFromName 'undated.sav')) 'Unknown filename date was guessed.'
    $training=@(Get-TrainingAnalysisCorpus -ProjectRoot $fixture)
    Require ($training.Count-eq5-and@($training|Where-Object{$_.in_scope}).Count-eq2) 'Training discovery must retain out-of-scope files and deduplicate sources.'
    $public=Get-TrainingCorpusPublishable $training|ConvertTo-Json -Depth 5
    Require (-not$public.Contains($fixture)-and-not$public.Contains('control.sav')) 'Publishable corpus leaked source paths or file names.'
    $after=@(Get-ChildItem $fixture -Recurse -File|ForEach-Object{[string]$_.FullName+'|'+$_.LastWriteTimeUtc.Ticks+'|'+(Get-ReplayFileSha256Hex $_.FullName)})
    Require (($snapshot-join"`n")-eq($after-join"`n")) 'Discovery modified replay sources.'
    Write-Host '[OK] Replay corpus: actual month selection, SHA deduplication, mandatory precedence, stable anonymous ids, exclusions, privacy and read-only discovery.'
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    if($resolved.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}
}
