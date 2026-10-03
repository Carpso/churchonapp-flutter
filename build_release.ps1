param(
  [ValidateSet("apk", "aab")]
  [string]$Type = "aab",

  # Optional: forces users below this build to update (non-dismissible prompt).
  # Bump ONLY when an old build genuinely cannot work against current servers.
  [int]$MinSupportedBuild = 0,

  # Shown in the update prompt. Defaults to a generic line.
  [string]$UpdateMessage = "",

  # Multi-line bullet list shown under the message in the prompt.
  [string]$ReleaseNotes = ""
)

$yaml = "pubspec.yaml"
$content = Get-Content $yaml -Raw
$version = "0.0.0"; $build = 0

if ($content -match 'version:\s*([\d.]+)\+(\d+)') {
  $version = $Matches[1]
  $build = [int]$Matches[2] + 1
  Write-Host "Bumping build number: $($Matches[2]) -> $build"
  $content = $content -replace 'version:\s*[\d.]+\+\d+', "version: $version+$build"
  Set-Content $yaml -Value $content -NoNewline
  Write-Host "Building $Type with version $version+$build ..."
}

if ($Type -eq "aab") {
  flutter build appbundle --release --no-tree-shake-icons
} else {
  flutter build apk --release --no-tree-shake-icons
}

if ($LASTEXITCODE -ne 0) {
  Write-Host "BUILD FAILED - not publishing release metadata" -ForegroundColor Red
  exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Publish the release so every installed app self-triggers an update.
#
# This is the step that makes "the app tells users to update" automatic: bump the
# build, run this script, and every install below the new number is prompted on
# its next launch (Home screen) or next resume.
#
# It runs ONLY after a successful build, so a failed build can never leave
# users pointed at an artifact that does not exist.
# ---------------------------------------------------------------------------
if ($MinSupportedBuild -eq 0) { $MinSupportedBuild = [Math]::Max(1, $build - 60) }
if ([string]::IsNullOrWhiteSpace($UpdateMessage)) {
  $UpdateMessage = "Church On App $version is available with improvements and bug fixes."
}

$notesArg = $ReleaseNotes.Replace("'", "''")

Write-Host "Publishing app_release_config (latest_build=$build, min_supported=$MinSupportedBuild) ..."

$sql = @"
SELECT public.publish_app_release(
  $build,
  '$version',
  $MinSupportedBuild,
  '$($UpdateMessage.Replace("'", "''"))',
  '$notesArg',
  'https://play.google.com/store/apps/details?id=com.churchonapp.churchonapp',
  'https://media.churchonapp.com/builds/latest/ChurchOnApp.apk',
  'https://media.churchonapp.com/builds/latest/ChurchOnApp.aab',
  'build_release.ps1'
) AS published;
"@

$tmp = Join-Path $env:TEMP "release_publish.sql"
$sql | Out-File -FilePath $tmp -Encoding utf8

supabase db query --linked --file $tmp

if ($LASTEXITCODE -ne 0) {
  Write-Host "WARNING: build succeeded but app_release_config was NOT published." -ForegroundColor Yellow
  Write-Host "Users will not be prompted to update until you run:" -ForegroundColor Yellow
  Write-Host "  supabase db query --linked --file $tmp" -ForegroundColor Yellow
} else {
  Write-Host "Release published. Installs below build $MinSupportedBuild are force-updated;" -ForegroundColor Green
  Write-Host "installs below $build get a dismissible update prompt." -ForegroundColor Green
}
