# encrypt.ps1 - Encrypt config.env before git commit
# Usage: .\encrypt.ps1 [-InputFile config.env] [-OutputFile config.env.age]

param(
    [string]$InputFile = "config.env",
    [string]$OutputFile = "config.env.age"
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
    Write-Host ""
    Write-Host "Or download from: https://github.com/FiloSottile/age/releases"
    exit 1
}

# Check input file exists
if (-not (Test-Path $InputFile)) {
    Write-Err "Input file not found: $InputFile"
    Write-Host ""
    Write-Host "Create config.env from the example:"
    Write-Host "  Copy-Item config.env.example config.env"
    Write-Host "  notepad config.env"
    exit 1
}

# Find encryption key/recipients
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = Get-Location }

$RecipientsFile = Join-Path $ScriptDir ".age-recipients"
$KeyFile = "$env:USERPROFILE\.age\key.txt"

if (Test-Path $RecipientsFile) {
    # Count non-comment, non-empty lines
    $RecipientCount = (Get-Content $RecipientsFile | Where-Object { $_ -match "^age1" }).Count
    
    if ($RecipientCount -eq 0) {
        Write-Err ".age-recipients file has no valid public keys"
        Write-Host ""
        Write-Host "Add at least one public key (starts with 'age1...')"
        exit 1
    }
    
    Write-Info "Using recipients file with $RecipientCount recipient(s)"
    age -R $RecipientsFile -o $OutputFile $InputFile
}
elseif (Test-Path $KeyFile) {
    Write-Info "Using personal key from: $KeyFile"
    
    # Extract public key from key file
    $PublicKeyLine = Get-Content $KeyFile | Select-String "public key:"
    if (-not $PublicKeyLine) {
        Write-Err "Could not find public key in $KeyFile"
        exit 1
    }
    $PublicKey = $PublicKeyLine.ToString().Split(":")[1].Trim()
    
    age -r $PublicKey -o $OutputFile $InputFile
}
else {
    Write-Err "No encryption key found!"
    Write-Host ""
    Write-Host "Option 1: Create .age-recipients file with public keys"
    Write-Host "  Copy-Item .age-recipients.example .age-recipients"
    Write-Host "  notepad .age-recipients"
    Write-Host ""
    Write-Host "Option 2: Generate a personal key"
    Write-Host "  New-Item -ItemType Directory -Force -Path `"$env:USERPROFILE\.age`""
    Write-Host "  age-keygen -o `"$env:USERPROFILE\.age\key.txt`""
    exit 1
}

if ($LASTEXITCODE -ne 0) {
    Write-Err "Encryption failed!"
    exit 1
}

# Verify output is binary (encrypted)
$FirstBytes = [System.IO.File]::ReadAllBytes($OutputFile)[0..10]
$IsText = $true
foreach ($byte in $FirstBytes) {
    if ($byte -lt 32 -and $byte -notin @(9, 10, 13)) {
        $IsText = $false
        break
    }
}

if ($IsText) {
    Write-Warn "Output file may not be properly encrypted!"
}

Write-Info "Encrypted: $InputFile -> $OutputFile"
Write-Host ""

# Git hints
if (Test-Path ".git") {
    # Check if config.env is in .gitignore
    $GitIgnore = if (Test-Path ".gitignore") { Get-Content ".gitignore" } else { @() }
    if ($GitIgnore -notcontains "config.env") {
        Write-Warn "Make sure 'config.env' is in .gitignore!"
    }
    
    Write-Host "Ready to commit:" -ForegroundColor Cyan
    Write-Host "  git add $OutputFile"
    Write-Host "  git commit -m 'Update encrypted config'"
}
