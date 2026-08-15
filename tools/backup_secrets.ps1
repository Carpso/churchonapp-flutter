# backup_secrets.ps1 — Encrypts all critical keys/secrets into one AES-256 file.
# Usage:  powershell -File tools\backup_secrets.ps1 [-Passphrase <text>]
#         (without -Passphrase it prompts; store it in your password manager)
# Output: <Documents>\COA-Security\COA-secrets-backup-YYYYMMDD-HHmm.bin + manifest.txt
param([string]$Passphrase)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

$items = @(
    @{ Name = "upload-keystore.jks";     Path = "$root\android\app\upload-keystore.jks" },
    @{ Name = "key.properties";          Path = "$root\android\key.properties" },
    @{ Name = "google-services.json";    Path = "$root\android\app\google-services.json" },
    @{ Name = "play-service-account.json"; Path = "$env:USERPROFILE\Downloads\KINGDOM SPONSOR\studio-7483333628-db257-83fdec92dc9a_kingdomsponsor.json" },
    @{ Name = "env";                     Path = "$root\.env" }
)

$outDir = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "COA-Security"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmm"
$outFile = Join-Path $outDir "COA-secrets-backup-$stamp.bin"

if ([string]::IsNullOrWhiteSpace($Passphrase)) {
    $pass = Read-Host -AsSecureString "Passphrase for the backup (use a strong one, store it in your password manager)"
    $passBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
    $passTextWasSecure = $true
    $passText = [Runtime.InteropServices.Marshal]::PtrToStringAuto($passBstr)
} else {
    $passText = $Passphrase
    $passTextWasSecure = $false
}
if ([string]::IsNullOrWhiteSpace($passText)) { throw "Empty passphrase" }

$payload = New-Object System.Collections.Generic.List[byte]
$manifest = @("COA secrets backup $stamp", "Created by backup_secrets.ps1", "")
foreach ($it in $items) {
    if (-not (Test-Path -LiteralPath $it.Path)) { $manifest += "MISSING: $($it.Name)"; continue }
    $bytes = [IO.File]::ReadAllBytes($it.Path)
    $header = [byte[]]([Text.Encoding]::UTF8.GetBytes($it.Name) + [byte[]](0))  # name + NUL
    $payload.AddRange([Text.Encoding]::UTF8.GetBytes([string]$bytes.Length + ":"))  # len:
    $payload.AddRange($header)
    $payload.AddRange($bytes)
    $manifest += "OK: $($it.Name) ($($bytes.Length) bytes)"
}
$payloadBytes = $payload.ToArray()

$salt = New-Object byte[] 16
[Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($salt)
$iv = New-Object byte[] 16
[Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($iv)
$kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($passText, $salt, 600000)
$key = $kdf.GetBytes(32)

$aes = [Security.Cryptography.Aes]::Create()
$aes.Mode = [Security.Cryptography.CipherMode]::CBC
$aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
$enc = $aes.CreateEncryptor($key, $iv)
$cipher = $enc.TransformFinalBlock($payloadBytes, 0, $payloadBytes.Length)

$final = New-Object System.Collections.Generic.List[byte]
$final.AddRange([byte[]](67, 79, 65, 66, 75, 49))   # magic "COABK1"
$final.AddRange($salt); $final.AddRange($iv)
$final.AddRange($cipher)
[IO.File]::WriteAllBytes($outFile, $final.ToArray())

$manifest += ""
$manifest += "OUTPUT: $outFile"
[IO.File]::WriteAllLines((Join-Path $outDir "manifest-$stamp.txt"), $manifest)
if ($passTextWasSecure -eq $true) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passBstr)
}
Write-Host ""
Write-Host "Backup written: $outFile"
Write-Host "Manifest:       $outDir\manifest-$stamp.txt"
Write-Host "IMPORTANT: save the passphrase in your password manager. Without it the backup cannot be restored."
Write-Host "Restore with: powershell -File $root\tools\restore_secrets.ps1"