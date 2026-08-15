# restore_secrets.ps1 — Restores the encrypted secrets backup to a folder.
# Usage:  powershell -File tools\restore_secrets.ps1 -BackupFile <path.bin> [-OutDir <dir>]
param(
    [Parameter(Mandatory = $true)][string]$BackupFile,
    [string]$Passphrase,
    [string]$OutDir = (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "COA-Security\restored")
)
$ErrorActionPreference = "Stop"

$data = [IO.File]::ReadAllBytes($BackupFile)
$magic = $data[0..5]
if (-not ($magic -join ",") -eq "67,79,65,66,75,49") { throw "Not a COA backup file" }
$salt = $data[6..21]
$iv = $data[22..37]
$cipher = $data[38..($data.Length - 1)]

if ([string]::IsNullOrWhiteSpace($Passphrase)) {
    $securePass = Read-Host -AsSecureString "Passphrase for the backup"
    $passBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
    $passText = [Runtime.InteropServices.Marshal]::PtrToStringAuto($passBstr)
    $cleanup = $true
} else {
    $passText = $Passphrase
    $cleanup = $false
}
$kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($passText, $salt, 600000)
$key = $kdf.GetBytes(32)

$aes = [Security.Cryptography.Aes]::Create()
$aes.Mode = [Security.Cryptography.CipherMode]::CBC
$aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
$dec = $aes.CreateDecryptor($key, $iv)
$payload = $dec.TransformFinalBlock($cipher, 0, $cipher.Length)
if ($cleanup -eq $true) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passBstr)
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$i = 0
while ($i -lt $payload.Length) {
    $colon = [Array]::IndexOf($payload, [byte]58, $i)          # ':'
    if ($colon -lt 0) { break }
    $len = [int]([Text.Encoding]::UTF8.GetString($payload[$i..($colon - 1)]))
    $nul = $colon + 1
    $name = [Text.Encoding]::UTF8.GetString($payload[$nul..([Array]::IndexOf($payload, [byte]0, $nul) - 1)])
    $start = [Array]::IndexOf($payload, [byte]0, $nul) + 1
    $bytes = $payload[$start..($start + $len - 1)]
    $target = Join-Path $OutDir $name
    [IO.File]::WriteAllBytes($target, $bytes)
    Write-Host "Restored: $target"
    $i = $start + $len
}
Write-Host "Done. Restored to $OutDir"