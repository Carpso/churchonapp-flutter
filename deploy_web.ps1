# ChurchOnApp Flutter Web Deployment Script
$VPS_IP = "139.84.227.254"
$REMOTE_DIR = "/var/www/churchonapp"

Write-Host "Starting Flutter Web Deployment to Kingdom Server ($VPS_IP)..." -ForegroundColor Cyan

# 1. Build Web App
Write-Host "Building Flutter Web App..." -ForegroundColor Yellow
flutter build web --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build Failed!" -ForegroundColor Red
    exit
}



# 2. Package build
Write-Host "Packaging build..." -ForegroundColor Yellow
if (Test-Path "site_release.zip") { Remove-Item "site_release.zip" }
# Copy APK into web build folder for direct download links on site
if (Test-Path "build/app/outputs/flutter-apk/app-release.apk") {
    Copy-Item "build/app/outputs/flutter-apk/app-release.apk" "build/web/app-release.apk"
    Write-Host "APK copied to web folder." -ForegroundColor Gray
}
Compress-Archive -Path build/web/* -DestinationPath site_release.zip


# 3. Upload Zip
Write-Host "Uploading site_release.zip to VPS..." -ForegroundColor Yellow
scp -o BatchMode=yes -o StrictHostKeyChecking=no site_release.zip root@${VPS_IP}:/tmp/site_release.zip

# 4. Extract and Deploy
Write-Host "Extracting on VPS..." -ForegroundColor Yellow
$extractCmd = "mkdir -p $REMOTE_DIR/dist_flutter && rm -rf $REMOTE_DIR/dist_flutter/* && unzip -o /tmp/site_release.zip -d $REMOTE_DIR/dist_flutter && rm /tmp/site_release.zip && ([ -d $REMOTE_DIR/dist ] && (rm -rf $REMOTE_DIR/dist_old && mv $REMOTE_DIR/dist $REMOTE_DIR/dist_old) || true) && mv $REMOTE_DIR/dist_flutter $REMOTE_DIR/dist && chown -R www-data:www-data $REMOTE_DIR/dist"
ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@$VPS_IP $extractCmd


Write-Host "Deployment Complete! https://churchonapp.com" -ForegroundColor Green
