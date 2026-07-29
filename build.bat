#!/usr/bin/env /usr/bin/powershell -Command

# Church On App APK Build Script

# Change to project directory
$PROJECT_DIR = "D:\\Explorer\\MAYUNDO\\KEY PROJECTS\\churchonapp_flutter"
Set-Location $PROJECT_DIR

function Write-Header($text) {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  $text                                                   " -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step($text) {
    Write-Host "─" -ForegroundColor Gray
    Write-Host "► $text" -ForegroundColor White
}

function Write-Success($text) {
    Write-Host "✓ $text" -ForegroundColor Green
}

function Write-Error($text) {
    Write-Host "✗ $text" -ForegroundColor Red
}

# Display welcome message
Write-Header "Church On App APK Build Script"
Write-Host "This script builds the Android APK for the Church On App project."
Write-Host ""

# Validate build type parameter
if ($Type -notin @("apk", "aab")) {
    Write-Error "Invalid build type: $Type"
    Write-Host "Usage: powershell -File build.bat [Type]"
    Write-Host "  Type can be 'apk' or 'aab'"
    exit 1
}

# Validate build tool availability
Write-Step "Checking Flutter availability..."
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter not found in PATH"
    Write-Host "Please ensure Flutter is installed and added to PATH."
    exit 1
}

# Check if pubspec.yaml exists
Write-Step "Loading project configuration..."
if (-not (Test-Path "pubspec.yaml")) {
    Write-Error "pubspec.yaml not found!"
    Write-Host "Please run this script from the project root directory."
    exit 1
}

# Get current version and build number
Write-Step "Reading version information..."
$content = Get-Content "pubspec.yaml" -Raw
if ($content -match "version:\s*([\d.]+)\+(\d+)") {
    $version = $Matches[1]
    $build = [int]$Matches[2]
    $build = $build + 1
    Write-Host "Current version: $version+$build"
    $content = $content -replace "version:\s*[\d.]+\+\d+", "version: $version+$build"
    Set-Content "pubspec.yaml" -Value $content -NoNewline
}

# Save the modified pubspec.yaml
Set-Content "pubspec.yaml" -Value $content -NoNewline

Write-Success "Updated version to $version+$build"

# Validate build type
Write-Step "Preparing to build $Type..."

# Build the APK/AAB
try {
    if ($Type -eq "aab") {
        Write-Step "Building Android App Bundle (AAB)..."
        $result = flutter build appbundle --release
    } else {
        Write-Step "Building APK..."
        $result = flutter build apk --release
    }
    
    Write-Step "Build completed successfully!"
    
    # Check if build output exists
    $outputPath = "build\\app\\outputs\\$Type\\release"
    if (Test-Path $outputPath) {
        $files = Get-ChildItem $outputPath
        Write-Success "Found build artifacts:"
        $files | ForEach { Write-Host "  • $($_.Name)" }
    }
    
    if ($Type -eq "apk") {
        $apkFile = Get-ChildItem "build\\app\\outputs\\flutter-apk\\app-release.apk"
        if ($apkFile) {
            Write-Success "APK generated successfully: $($apkFile.FullName)"
            Write-Host "Size: $([math]::Round($apkFile.Length / 1MB, 2)) MB"
        }
    } elseif ($Type -eq "aab") {
        $aabFile = Get-ChildItem "build\\app\\outputs\\bundle\\release\\Church On App.aab"
        if ($aabFile) {
            Write-Success "AAB generated successfully: $($aabFile.FullName)"
            Write-Host "Size: $([math]::Round($aabFile.Length / 1MB, 2)) MB"
        }
    }
    
    Write-Header "Build Complete!"
    Write-Host "The $Type has been successfully built."
    Write-Host ""
    Write-Host "Files location:"
    Write-Host "  Android Binaries: $outputPath"
    Write-Host ""
    Write-Host "Next Steps:"
    Write-Host "  1. Install the APK on an Android device or emulator"
    Write-Host "  uddtryk 2. Upload to Google Play Console (for AAB)"
    Write-Host "  3. Distribute the APK directly (for APK)"
}

catch {
    Write-Error "Build failed with error: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Please check the output above for more details."
    Write-Host "Common issues:"
    Write-Host "  - Network connectivity problems"
    Write-Host "  - Insufficient disk space"
    Write-Host "  - Missing Android SDK or build tools"
    exit 1
}
