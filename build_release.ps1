param(
  [ValidateSet("apk", "aab")]
  [string]$Type = "aab"
)

$yaml = "pubspec.yaml"
$content = Get-Content $yaml -Raw

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
