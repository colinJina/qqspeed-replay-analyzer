# Definition-only, local corpus discovery shared by the real gates and training tools.
# File names select the recording month for acceptance only; they never select a parser.
# The user's replay/ set takes precedence over content-identical archive copies.
# Empty discovery stays empty. Real gates keep their required corpus/evidence assertions.

function Get-ReplayFileSha256Hex {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
}

function Get-SeptemberRecordedTimeFromName {
    param([Parameter(Mandatory=$true)][string]$Path)
    $name=[IO.Path]::GetFileName($Path)
    $match=[regex]::Match($name,'^.+-(\d{8})-(\d{6})-.+\.sav$',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if(-not$match.Success){return $null}
    $recorded=[datetime]::MinValue
    if([datetime]::TryParseExact(($match.Groups[1].Value+$match.Groups[2].Value),'yyyyMMddHHmmss',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$recorded)){
        return $recorded
    }
    return $null
}

function Get-September2026Corpus {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [string]$UserCorpusDir='',
        [string]$ArchiveDir=''
    )
    if([string]::IsNullOrWhiteSpace($UserCorpusDir)){$UserCorpusDir=Join-Path $ProjectRoot 'replay'}
    if([string]::IsNullOrWhiteSpace($ArchiveDir)){$ArchiveDir=Join-Path $ProjectRoot 'Data\ReplayArchive'}
    $candidates=New-Object System.Collections.Generic.List[object]
    if(Test-Path -LiteralPath $UserCorpusDir -PathType Container){
        foreach($f in @(Get-ChildItem -LiteralPath $UserCorpusDir -File -Filter '*.sav' | Sort-Object FullName)){
            $candidates.Add([pscustomobject]@{file=$f;corpus='mandatory_user'})
        }
    }
    if(Test-Path -LiteralPath $ArchiveDir -PathType Container){
        foreach($f in @(Get-ChildItem -LiteralPath $ArchiveDir -Recurse -File -Filter '*.sav' | Sort-Object FullName)){
            $candidates.Add([pscustomobject]@{file=$f;corpus='archive_extension'})
        }
    }
    $bySha=@{}
    foreach($c in $candidates){
        $recorded=Get-SeptemberRecordedTimeFromName $c.file.FullName
        if($null-eq$recorded -or $recorded.ToString('yyyy-MM')-ne'2026-09'){continue}
        $sha=Get-ReplayFileSha256Hex $c.file.FullName
        if($bySha.ContainsKey($sha)){continue}
        $bySha[$sha]=[pscustomobject][ordered]@{
            test_id='';sha256=$sha;sha16=$sha.Substring(0,16)
            size_bytes=[long]$c.file.Length;corpus=$c.corpus
            recorded_at=$recorded.ToString('s');recorded_at_source='replay_filename_convention'
            source_path=$c.file.FullName
        }
    }
    $index=0
    foreach($sha in @($bySha.Keys|Sort-Object)){
        $index++;$entry=$bySha[$sha];$entry.test_id=('S{0:D2}' -f $index);$entry
    }
}
