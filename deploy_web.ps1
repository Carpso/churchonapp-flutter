# ChurchOnApp Flutter Web Deployment Script
# VPS DEPRECATED — now using Cloudflare Pages for all web hosting.
# $VPS_IP = "139.84.227.254"
# $REMOTE_DIR = "/var/www/churchonapp"

Write-Host "Starting Flutter Web Deployment to Cloudflare Pages..." -ForegroundColor Cyan

# 1. Build Web App
Write-Host "Building Flutter Web App..." -ForegroundColor Yellow
flutter build web --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build Failed!" -ForegroundColor Red
    exit
}

# 2. Copy APK into web build folder for direct download links on site
Write-Host "Copying APK to web folder..." -ForegroundColor Yellow
if (Test-Path "build/app/outputs/flutter-apk/app-release.apk") {
    Copy-Item "build/app/outputs/flutter-apk/app-release.apk" "build/web/app-release.apk"
    Write-Host "APK copied to web folder." -ForegroundColor Gray
}

# 3. Copy Pages Functions (OG/SEO meta injection) into build output
Write-Host "Copying Pages Functions..." -ForegroundColor Yellow
Copy-Item -Recurse "web\functions" "build\web\" -Force
if ($LASTEXITCODE -ne 0) {
    Write-Host "Functions copy failed!" -ForegroundColor Red
}

# 4. Deploy to Cloudflare Pages
# NOTE: --cwd build/web is required — wrangler only picks up the `functions/`
# folder relative to the current working directory. Deploying `build/web` from
# the repo root silently skips the Functions folder.
Write-Host "Deploying to Cloudflare Pages..." -ForegroundColor Yellow
npx wrangler pages deploy . --cwd build/web --project-name=churchonapp --branch=main
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Manual alternative: Upload 'build/web' folder via Cloudflare Dashboard" -ForegroundColor Yellow
    Write-Host "  https://dash.cloudflare.com/?to=pages" -ForegroundColor Cyan
}

Write-Host "Deployment Complete! https://churchonapp.com" -ForegroundColor Green
