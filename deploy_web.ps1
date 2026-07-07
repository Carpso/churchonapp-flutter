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

# 3. Deploy to Cloudflare Pages
Write-Host "Deploying to Cloudflare Pages..." -ForegroundColor Yellow
npx wrangler pages deploy build/web --project-name=churchonapp --branch=main
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Manual alternative: Upload 'build/web' folder via Cloudflare Dashboard" -ForegroundColor Yellow
    Write-Host "  https://dash.cloudflare.com/?to=pages" -ForegroundColor Cyan
}

Write-Host "Deployment Complete! https://churchonapp.com" -ForegroundColor Green
