#Requires -Version 5.1
<#
.SYNOPSIS
  Reproducible city-level PMTiles pipeline (countries z0-15 + metros z13-19).

.DESCRIPTION
  Downloads Geofabrik extracts (resume-safe), runs Planetiler to produce PMTiles,
  prints resulting sizes, and uploads them to R2 via scripts/map/r2-put.mjs.

  Outputs per source:
    <id>-z0-15.pmtiles    (country, world-covering base tiles)
    <id>-z13-19.pmtiles   (metro clip with building detail)

  R2 keys:
    stable : tiles/<id>-z0-15.pmtiles / tiles/<id>-z13-19.pmtiles
    dated  : tiles/<id>/<date>.pmtiles  (+ server-side copy to the stable key)

  RE-RUN / RESUME:
    Planetiler cannot resume a *partial* run - if <out>.pmtiles exists it is
    kept as-is and the step is skipped, so a re-run continues after the last
    COMPLETED source. Pass -Force to rebuild a completed source from scratch.

  Prerequisites: java (17+) OR docker, node 18+, curl.
  Set R2_ACCOUNT_ID / R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY (or VITE_R2_*
  in the sibling churchonapp/.env) for uploads.

.EXAMPLE
  powershell -File scripts/map/build-city-tiles.ps1 -Cities lusaka,harare
  powershell -File scripts/map/build-city-tiles.ps1 -All -Force -DateStamp 20260924
#>
[CmdletBinding()]
param(
  # Where PBFs and PMTiles live (must have ~40 GB free for a full run).
  [string]$Scratch = 'D:\mapbuild',
  # Country ids from metros.json; 'all' = every country.
  [string[]]$Countries = @('zambia', 'zimbabwe'),
  # Metro ids from metros.json; 'all' = every metro. Empty = no metro builds.
  [string[]]$Cities = @(),
  # Path to planetiler.jar (or set PLANETILER_JAR env). Falls back to docker.
  [string]$PlanetilerJar = $env:PLANETILER_JAR,
  # Use the Docker image instead of a local java/planetiler.jar.
  [switch]$UseDocker,
  [string]$DockerImage = 'ghcr.io/onthegomap/planetiler:latest',
  [int]$CountryHeapGb = 8,
  [int]$CityHeapGb = 6,
  # Skip the Geofabrik download (PBFs already present in $Scratch).
  [switch]$SkipDownload,
  # Build only - do not upload to R2.
  [switch]$SkipUpload,
  # Rebuild sources whose output already exists.
  [switch]$Force,
  # yyyyMMdd stamp -> dated R2 key + copy onto the stable key.
  [string]$DateStamp = '',
  # R2 key prefix.
  [string]$KeyPrefix = 'tiles',
  # Planetiler-only servers: skip water/ne_population/roads-network downloads.
  [switch]$OnlyFetchWays,
  # Extra args appended to every planetiler invocation.
  [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $Here '..\..')
$R2Put = Join-Path $Here 'r2-put.mjs'
$MetrosJson = Join-Path $Here 'metros.json'
$ReportPath = Join-Path $Scratch 'build-report.json'

# ------------------------------------------------------------------- helpers
function Write-Step([string]$msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Skip([string]$msg) { Write-Host "  skip: $msg" -ForegroundColor DarkGray }

function Format-Bytes([long]$n) {
  if ($n -ge 1GB) { return ('{0:N2} GB' -f ($n / 1GB)) }
  if ($n -ge 1MB) { return ('{0:N1} MB' -f ($n / 1MB)) }
  if ($n -ge 1KB) { return ('{0:N1} KB' -f ($n / 1KB)) }
  return "$n B"
}

function Get-BboxCsv([object]$bbox) {
  # metros.json stores [south, west, north, east]; planetiler wants the same order.
  return (@($bbox[0], $bbox[1], $bbox[2], $bbox[3]) -join ',')
}

function Test-Command([string]$name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Get-Pbf {
  param([object]$country)
  $dest = Join-Path $Scratch $country.pbf
  if (-not $SkipDownload) {
    if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt 1MB)) {
      Write-Skip ("already downloaded: {0} ({1})" -f $country.pbf, (Format-Bytes (Get-Item $dest).Length))
    } else {
      Write-Host ("  downloading {0}" -f $country.geofabrik)
      if (-not (Test-Command 'curl.exe')) { throw 'curl.exe is required to download Geofabrik extracts.' }
      # -C - resumes an interrupted download; --retry covers transient 5xx.
      & curl.exe -L -C - --retry 4 --retry-delay 2 -o $dest $country.geofabrik
      if ($LASTEXITCODE -ne 0) { throw "download failed for $($country.geofabrik) (exit $LASTEXITCODE)" }
    }
  }
  if (-not (Test-Path $dest)) { throw "Missing PBF: $dest (re-run without -SkipDownload)" }
  $size = (Get-Item $dest).Length
  if ($size -lt 1MB) { throw "PBF looks truncated ($size bytes): $dest" }
  return $dest
}

function Invoke-Planetiler {
  param(
    [string[]]$Arguments,
    [string]$OutputPath,
    [int]$HeapGb
  )
  $cmdArgs = @($Arguments)
  if ($OnlyFetchWays) { $cmdArgs += '--only_fetch_ways=true' }
  if ($Force) { $cmdArgs += '--force' }
  $cmdArgs += $ExtraArgs

  if ($UseDocker) {
    if (-not (Test-Command 'docker')) { throw 'docker not found but -UseDocker was passed.' }
    # Mount $Scratch at /data and rewrite every absolute scratch path.
    $dockerArgs = @()
    foreach ($a in $cmdArgs) {
      $dockerArgs += ($a -replace [regex]::Escape($Scratch), '/data')
    }
    $dockerArgs += ('--memory={0}g' -f $HeapGb)
    Write-Host ("  docker run {0}" -f $DockerImage)
    & docker run --rm -v "${Scratch}:/data" $DockerImage @dockerArgs
  } else {
    $java = $null
    if (Test-Command 'java') { $java = 'java' }
    if (-not $java) {
      throw "java not found. Install a JRE 17+ or pass -UseDocker (docker image $DockerImage)."
    }
    if (-not $PlanetilerJar -or -not (Test-Path $PlanetilerJar)) {
      throw "planetiler.jar not found at '$PlanetilerJar'. Download it and pass -PlanetilerJar <path>, or use -UseDocker."
    }
    Write-Host ("  java -Xmx{0}g -jar {1}" -f $HeapGb, $PlanetilerJar)
    & $java @("-Xmx${HeapGb}g", '-jar', $PlanetilerJar) @cmdArgs
  }
  if ($LASTEXITCODE -ne 0) { throw "planetiler exited with code $LASTEXITCODE" }
  if (-not (Test-Path $OutputPath)) { throw "planetiler produced no output: $OutputPath" }
}

function Upload-Object {
  param([string]$LocalPath, [string]$Key)
  if ($SkipUpload) { Write-Skip "upload disabled (-SkipUpload): $Key"; return $false }
  if (-not (Test-Command 'node')) { throw 'node is required for R2 uploads (scripts/map/r2-put.mjs).' }
  & node $R2Put $LocalPath $Key
  if ($LASTEXITCODE -ne 0) { throw "r2-put failed for $Key" }
  return $true
}

function Copy-Object {
  param([string]$SourceKey, [string]$DestKey)
  if ($SkipUpload) { return $false }
  if (-not (Test-Command 'node')) { throw 'node is required for R2 uploads (scripts/map/r2-put.mjs).' }
  & node $R2Put --copy $SourceKey $DestKey
  if ($LASTEXITCODE -ne 0) { throw "r2-put --copy failed: $SourceKey -> $DestKey" }
  return $true
}

# Publish one local file: always store the dated snapshot, then promote it to
# the stable key server-side (one client push instead of two).
function Publish-Source {
  param([string]$LocalPath, [string]$Name)
  $key = "$KeyPrefix/$Name.pmtiles"
  if ($DateStamp) {
    $dated = "$KeyPrefix/$Name/$DateStamp.pmtiles"
    Upload-Object $LocalPath $dated | Out-Null
    Copy-Object $dated $key | Out-Null
  } else {
    Upload-Object $LocalPath $key | Out-Null
  }
  return $key
}

# ------------------------------------------------------------------- prepare
if (-not (Test-Path $Scratch)) { New-Item -ItemType Directory -Path $Scratch | Out-Null }
if (-not (Test-Path $MetrosJson)) { throw "metros.json not found: $MetrosJson" }
$meta = Get-Content $MetrosJson -Raw -Encoding UTF8 | ConvertFrom-Json
$stamp = if ($DateStamp) { $DateStamp } else { Get-Date -Format 'yyyyMMdd' }

$countryIds = @($meta.countries | ForEach-Object { $_.id })
$wantedCountries = @($Countries | Where-Object { $_ -ne 'all' })
$selCountries = if ($Countries -contains 'all') { @($meta.countries) } else { @($meta.countries | Where-Object { $wantedCountries -contains $_.id }) }
$wantedCities = @($Cities | Where-Object { $_ -ne 'all' })
$selMetros = if ($Cities -contains 'all') { @($meta.metros) } else { @($meta.metros | Where-Object { $wantedCities -contains $_.id }) }

if ($selCountries.Count -eq 0 -and $selMetros.Count -eq 0) {
  throw "Nothing selected. Known countries: $($countryIds -join ', '). Known metros: $((@($meta.metros | ForEach-Object { $_.id })) -join ', ')"
}

Write-Host "Scratch : $Scratch"
Write-Host "Stamp   : $stamp"
Write-Host "Countries: $(if ($selCountries) { ($selCountries | ForEach-Object { $_.id }) -join ', ' } else { '(none)' })"
Write-Host "Metros  : $(if ($selMetros) { ($selMetros | ForEach-Object { $_.id }) -join ', ' } else { '(none)' })"
Write-Host "Upload  : $(if ($SkipUpload) { 'disabled' } else { 'enabled -> ' + $KeyPrefix })"

$report = New-Object System.Collections.Generic.List[object]
$pbfByCountry = @{}

function Add-Report {
  param([string]$Id, [string]$Label, [object]$Bbox, [int]$MinZ, [int]$MaxZ, [string]$Path)
  $item = [ordered]@{
    id       = $Id
    name     = $Label
    path     = $Path
    bytes    = (Get-Item $Path).Length
    bbox     = @($Bbox[0], $Bbox[1], $Bbox[2], $Bbox[3])
    min_zoom = $MinZ
    max_zoom = $MaxZ
    key      = ''
    url      = ''
    built_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    date     = $stamp
  }
  $script:report.Add([pscustomobject]$item) | Out-Null
}

# ----------------------------------------------------------- 1. country bases
foreach ($c in $selCountries) {
  Write-Step "Country: $($c.name) (z0-15)"
  $pbf = if ($pbfByCountry.ContainsKey($c.id)) { $pbfByCountry[$c.id] } else { Get-Pbf $c }
  $pbfByCountry[$c.id] = $pbf
  $out = Join-Path $Scratch ("{0}-z0-15.pmtiles" -f $c.id)

  if ((Test-Path $out) -and -not $Force) {
    Write-Skip "output exists (use -Force to rebuild): $out"
  } else {
    Invoke-Planetiler -OutputPath $out -HeapGb $CountryHeapGb -Arguments @(
      "--area=$pbf",
      "--bounds=$(Get-BboxCsv $c.bbox)",
      '--minzoom=0',
      '--maxzoom=15',
      "--output=$out"
    )
  }
  Write-Host ("  size: {0}" -f (Format-Bytes (Get-Item $out).Length))

  $key = Publish-Source -LocalPath $out -Name "$($c.id)-z0-15"

  Add-Report -Id $c.id -Label $c.name -Bbox $c.bbox -MinZ 0 -MaxZ 15 -Path $out
  $entry = $report[$report.Count - 1]
  $entry.key = $key
  $entry.url = "https://maps.churchonapp.com/$key"
}

# ------------------------------------------------------------- 2. metro clips
foreach ($m in $selMetros) {
  Write-Step "Metro: $($m.name) (z13-19, country=$($m.country))"
  $parent = $meta.countries | Where-Object { $_.id -eq $m.country } | Select-Object -First 1
  if (-not $parent) { throw "metros.json: metro '$($m.id)' references unknown country '$($m.country)'" }
  if (-not $pbfByCountry.ContainsKey($parent.id)) { $pbfByCountry[$parent.id] = Get-Pbf $parent }
  $pbf = $pbfByCountry[$parent.id]

  $out = Join-Path $Scratch ("{0}-z13-19.pmtiles" -f $m.id)
  if ((Test-Path $out) -and -not $Force) {
    Write-Skip "output exists (use -Force to rebuild): $out"
  } else {
    Invoke-Planetiler -OutputPath $out -HeapGb $CityHeapGb -Arguments @(
      "--area=$pbf",
      "--bounds=$(Get-BboxCsv $m.bbox)",
      '--minzoom=13',
      '--maxzoom=19',
      "--output=$out"
    )
  }
  Write-Host ("  size: {0}" -f (Format-Bytes (Get-Item $out).Length))

  $key = Publish-Source -LocalPath $out -Name "$($m.id)-z13-19"

  Add-Report -Id $m.id -Label $m.name -Bbox $m.bbox -MinZ 13 -MaxZ 19 -Path $out
  $entry = $report[$report.Count - 1]
  $entry.key = $key
  $entry.url = "https://maps.churchonapp.com/$key"
}

# ----------------------------------------------------------------- 3. report
$json = @{ generated_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); date_stamp = $stamp; sources = @($report) } | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($ReportPath, $json, [System.Text.UTF8Encoding]::new($false))
Write-Step "Build report"
Write-Host "  $ReportPath"
foreach ($r in $report) {
  Write-Host ("  {0,-16} z{1}-{2}  {3,-9} {4}" -f $r.name, $r.min_zoom, $r.max_zoom, (Format-Bytes $r.bytes), $r.key)
}

# Paste-ready MAPS_EXTRA_SOURCES (city archives only — the base is already
# covered by MAPS_ZAMBIA_URL) so the app switches to them at z16+.
$cities = @($report | Where-Object { $_.min_zoom -gt 0 })
if ($cities.Count -gt 0) {
  # Build real objects and let ConvertTo-Json escape them — hand-rolled JSON
  # breaks on PowerShell 5.1 (no \" escape; -f would eat the braces).
  $extra = @($cities | ForEach-Object {
      [ordered]@{
        name    = $_.id
        bbox    = @($_.bbox[0], $_.bbox[1], $_.bbox[2], $_.bbox[3])
        minZoom = 16
        maxZoom = $_.max_zoom
        url     = $_.url
      }
    })
  $sourcesLine = ($extra | ConvertTo-Json -Depth 4 -Compress)
  # ConvertTo-Json emits a bare object for a single-element array.
  if ($extra.Count -eq 1) { $sourcesLine = "[$sourcesLine]" }
  $sourcesPath = Join-Path $Scratch 'map_sources_extra.txt'
  [System.IO.File]::WriteAllText($sourcesPath, "MAPS_EXTRA_SOURCES=$sourcesLine`n", [System.Text.UTF8Encoding]::new($false))
  Write-Host "`n  Paste-ready MAPS_EXTRA_SOURCES (also in $sourcesPath):" -ForegroundColor Green
  Write-Host "  MAPS_EXTRA_SOURCES=$sourcesLine"
}
if (-not $SkipUpload) {
  Write-Host "`nNext: run scripts/map/refresh-maps.ps1 to publish the latest.json manifest." -ForegroundColor Green
}
