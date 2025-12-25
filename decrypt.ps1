# decrypt.ps1 - Decrypt config.env.age to config.env
# Usage: .\decrypt.ps1 [-InputFile config.env.age] [-OutputFile config.env]

param(
    [string]$InputFile = "config.env.age",
    [string]$OutputFile = "config.env"
)

$ErrorActionPreference = "Stop"

function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Check age is installed
if (-not (Get-Command age -ErrorAction SilentlyContinue)) {
    Write-Err "age is not installed"
    Write-Host ""
    Write-Host "Install with one of:"
    Write-Host "  scoop install age"
    Write-Host "  choco install age.portable"  
    Write-Host "  winget install FiloSottile.age"
    exit 1
}

# Check encrypted file exists
if (-not (Test-Path $InputFile)) {
    Write-Err "Encrypted file not found: $InputFile"
    Write-Host ""
    Write-Host "Make sure you have pulled the latest from git:"
    Write-Host "  git pull"
    exit 1
}

# Find private key - check multiple locations
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = Get-Location }

$KeyLocations = @(
    $env:AGE_KEY_FILE,
    "$env:USERPROFILE\.age\key.txt",
    "$env:APPDATA\age\key.txt",
    (Join-Path $ScriptDir ".age-key.txt"),
    ".\.age-key.txt"
) | Where-Object { $_ }

$KeyFile = $null
foreach ($loc in $KeyLocations) {
    if (Test-Path $loc) {
        $KeyFile = $loc
        break
    }
}

if (-not $KeyFile) {
    Write-Err "No age private key found!"
    Write-Host ""
    Write-Host "Searched locations:"
    Write-Host "  - $env:USERPROFILE\.age\key.txt"
    Write-Host "  - $env:APPDATA\age\key.txt"
    Write-Host "  - .\.age-key.txt"
    Write-Host "  - `$env:AGE_KEY_FILE (environment variable)"
    Write-Host ""
    Write-Host "To fix:"
    Write-Host "  1. Copy your private key to: $env:USERPROFILE\.age\key.txt"
    Write-Host "  2. Or set AGE_KEY_FILE environment variable"
    Write-Host ""
    Write-Host "Generate new key (if you don't have one):"
    Write-Host "  age-keygen -o `"$env:USERPROFILE\.age\key.txt`""
    exit 1
}

Write-Info "Using key: $KeyFile"

# Decrypt
Write-Info "Decrypting $InputFile..."

try {
    $result = age -d -i $KeyFile -o $OutputFile $InputFile 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Decryption failed!"
        Write-Host ""
        Write-Host "Possible causes:" -ForegroundColor Yellow
        Write-Host "  - Wrong private key (doesn't match the public key used to encrypt)"
        Write-Host "  - Corrupted encrypted file"
        Write-Host "  - File was encrypted for a different recipient"
        Write-Host ""
        Write-Host "Error output:"
        Write-Host $result
        exit 1
    }
}
catch {
    Write-Err "Decryption failed: $_"
    exit 1
}

Write-Info "Decrypted: $InputFile -> $OutputFile"

# Validate decrypted file has expected content
$RequiredVars = @("CF_API_TOKEN", "CF_ACCOUNT_ID", "CF_ZONE_ID", "CF_DOMAIN")
$Content = Get-Content $OutputFile -Raw
$Missing = @()

foreach ($var in $RequiredVars) {
    if ($Content -notmatch "^$var=" -and $Content -notmatch "`n$var=") {
        $Missing += $var
    }
}

if ($Missing.Count -gt 0) {
    Write-Warn "Config may be incomplete. Missing variables:"
    foreach ($var in $Missing) {
        Write-Host "  - $var" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Info "Config ready! You can now run the installer or copy to target location."
