#Requires -Version 5.1
<#
.SYNOPSIS
  Scheduled map refresh: rebuild sources, publish a dated snapshot, promote the
  stable keys, and upload tiles/latest.json for the app + dashboard to read.

.DESCRIPTION
  Thin orchestrator around build-city-tiles.ps1. The build writes
  <Scratch>\build-report.json; this script copies it to tiles/latest.json (so
  every consumer sees one stable URL listing what is live) and prints the
  scheduling commands for a VM.

  Dated snapshots accumulate under tiles/<name>/<yyyyMMdd>.pmtiles so an
  app update can roll back to any previous build by repointing MAPS_*_URL.

.SCHEDULE (pick one)

  Windows (Task Scheduler, weekly Sunday 03:00):
    schtasks /Create /TN "ChurchOnApp-TileRefresh" `
            /SC WEEKLY /D SUN /ST 03:00 `
            /TR "powershell -NoProfile -ExecutionPolicy Bypass -File \"D:\Explorer\MAYUNDO\KEY PROJECTS\churchonapp_flutter\scripts\map\refresh-maps.ps1\"" `
            /F

    Run now:   schtasks /Run /TN "ChurchOnApp-TileRefresh"
    Remove:    schtasks /Delete /TN "ChurchOnApp-TileRefresh" /F

  Linux/macOS VM (cron, weekly Sunday 03:00):
    crontab -e
    0 3 * * 0 /opt/churchonapp_flutter/scripts/map/refresh-maps.sh \
              --scratch /var/tiles >> /var/log/tile-refresh.log 2>&1

  NOTE: a full country rebuild takes 20-60 min and ~2-4 GB RAM; a metro clip
  takes 5-20 min. Give the job 4 GB+ and enough disk (~40 GB free for all 4
  countries + 6 metros).

.EXAMPLE
  powershell -File scripts/map/refresh-maps.ps1 -Countries zambia -Cities lusaka,harare
#>
[CmdletBinding()]
param(
  [string]$Scratch = 'D:\mapbuild',
  [string[]]$Countries = @('zambia', 'zimbabwe'),
  [string[]]$Cities = @(),
  [switch]$Force,
  [switch]$SkipBuild,
  [switch]$SkipUpload,
  [switch]$UseDocker,
  [string]$DateStamp = '',
  [string]$KeyPrefix = 'tiles',
  [string]$ManifestKey = 'latest.json'
)

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildScript = Join-Path $Here 'build-city-tiles.ps1'
$R2Put = Join-Path $Here 'r2-put.mjs'
$Stamp = if ($DateStamp) { $DateStamp } else { Get-Date -Format 'yyyyMMdd' }
$ReportPath = Join-Path $Scratch 'build-report.json'

if (-not $SkipBuild) {
  Write-Host "=== Building (stamp $Stamp) ===" -ForegroundColor Cyan
  $buildArgs = @{
    Scratch    = $Scratch
    Countries  = $Countries
    Cities     = $Cities
    DateStamp  = $Stamp
    KeyPrefix  = $KeyPrefix
  }
  if ($Force)      { $buildArgs.Force = $true }
  if ($SkipUpload) { $buildArgs.SkipUpload = $true }
  if ($UseDocker)  { $buildArgs.UseDocker = $true }

  & $BuildScript @buildArgs
  if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "build-city-tiles failed ($LASTEXITCODE)" }
}

if (-not (Test-Path $ReportPath)) {
  throw "No build report at $ReportPath - run without -SkipBuild first."
}

Write-Host "`n=== Publishing manifest ===" -ForegroundColor Cyan
$report = Get-Content $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$manifest = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  date_stamp   = $Stamp
  bucket       = 'church-on-app-maps'
  base_url     = 'https://maps.churchonapp.com/'
  # Stable keys the app reads today. The app resolves which one to use from
  # bbox + zoom (see lib/core/widgets/maps/map_sources.dart).
  sources      = @($report.sources | ForEach-Object {
      # Dated snapshot layout written by build-city-tiles: tiles/<stem>/<stamp>.pmtiles
      $stem = [System.IO.Path]::GetFileNameWithoutExtension($_.key)
      $dir  = [System.IO.Path]::GetDirectoryName($_.key)
      [ordered]@{
        id       = $_.id
        name     = $_.name
        url      = "https://maps.churchonapp.com/$($_.key)"
        bbox     = $_.bbox          # [south, west, north, east]
        min_zoom = $_.min_zoom
        max_zoom = $_.max_zoom
        bytes    = $_.bytes
        key      = $_.key
        dated    = "https://maps.churchonapp.com/$dir/$stem/$Stamp.pmtiles"
        built_at = $_.built_at
      }
    })
}

$manifestPath = Join-Path $Scratch 'latest.json'
$json = $manifest | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($manifestPath, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "  local : $manifestPath"
Write-Host ("  entries: {0}" -f $manifest.sources.Count)

if (-not $SkipUpload) {
  if (-not (Get-Command 'node' -ErrorAction SilentlyContinue)) { throw 'node is required for R2 uploads.' }
  $key = "$KeyPrefix/$ManifestKey"
  & node $R2Put $manifestPath $key
  if ($LASTEXITCODE -ne 0) { throw "r2-put failed for $key" }
  Write-Host "  remote: https://maps.churchonapp.com/$key" -ForegroundColor Green
} else {
  Write-Host '  upload skipped (-SkipUpload)' -ForegroundColor DarkGray
}

Write-Host "`n=== Scheduling ===" -ForegroundColor Cyan
Write-Host @"
  Windows (weekly Sun 03:00):
    schtasks /Create /TN "ChurchOnApp-TileRefresh" /SC WEEKLY /D SUN /ST 03:00 /TR "powershell -NoProfile -ExecutionPolicy Bypass -File \`"$BuildScript\`"" /F
    schtasks /Run /TN "ChurchOnApp-TileRefresh"      # run now
    schtasks /Delete /TN "ChurchOnApp-TileRefresh" /F # remove

  Linux/macOS VM (cron, weekly Sun 03:00):
    0 3 * * 0 /opt/churchonapp_flutter/scripts/map/refresh-maps.sh --scratch /var/tiles >> /var/log/tile-refresh.log 2>&1

  Roll back: repoint MAPS_ZAMBIA_URL / MAPS_EXTRA_SOURCES in .env at a dated
  URL (tiles/<name>/<yyyyMMdd>.pmtiles) and redeploy - no rebuild needed.
"@
