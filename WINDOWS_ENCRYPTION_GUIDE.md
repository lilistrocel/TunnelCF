# Encrypting Secrets on Windows

Guide for encrypting config.env on Windows before syncing to git.

---

## Option 1: age with PowerShell (Recommended)

### Install age

**Using Scoop (easiest):**
```powershell
# Install scoop if you don't have it
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

# Install age
scoop install age
```

**Using Chocolatey:**
```powershell
choco install age.portable
```

**Using winget:**
```powershell
winget install FiloSottile.age
```

**Manual download:**
1. Go to https://github.com/FiloSottile/age/releases
2. Download `age-v*-windows-amd64.zip`
3. Extract to `C:\Tools\age\` (or any folder)
4. Add to PATH: System Properties → Environment Variables → Path → Add `C:\Tools\age`

### Verify Installation

```powershell
age --version
# Output: v1.1.1 (or similar)
```

---

## Generate Your Key Pair

```powershell
# Create directory for keys
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.age"

# Generate key pair
age-keygen -o "$env:USERPROFILE\.age\key.txt"

# View your public key (you'll need this)
Get-Content "$env:USERPROFILE\.age\key.txt" | Select-String "public key"
```

Output looks like:
```
# created: 2024-01-15T10:30:00Z
# public key: age1abc123def456ghi789jkl012mno345pqr678stu901vwx234yza567
AGE-SECRET-KEY-1QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ
```

**Save your public key** - you'll add it to `.age-recipients`

---

## PowerShell Helper Scripts

### encrypt.ps1

```powershell
# encrypt.ps1 - Encrypt config.env before git commit

param(
    [string]$InputFile = "config.env",
    [string]$OutputFile = "config.env.age"
)

$ErrorActionPreference = "Stop"

# Check age is installed
if (-not (Get-Command age -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: age is not installed" -ForegroundColor Red
    Write-Host ""
    Write-Host "Install with:"
    Write-Host "  scoop install age"
    Write-Host "  choco install age.portable"
    Write-Host "  winget install FiloSottile.age"
    exit 1
}

# Check input file exists
if (-not (Test-Path $InputFile)) {
    Write-Host "ERROR: Input file not found: $InputFile" -ForegroundColor Red
    exit 1
}

# Find encryption key/recipients
$RecipientsFile = ".age-recipients"
$KeyFile = "$env:USERPROFILE\.age\key.txt"

if (Test-Path $RecipientsFile) {
    Write-Host "[INFO] Using recipients file: $RecipientsFile" -ForegroundColor Green
    age -R $RecipientsFile -o $OutputFile $InputFile
}
elseif (Test-Path $KeyFile) {
    Write-Host "[INFO] Using personal key from: $KeyFile" -ForegroundColor Green
    $PublicKey = (Get-Content $KeyFile | Select-String "public key:").ToString().Split(":")[1].Trim()
    age -r $PublicKey -o $OutputFile $InputFile
}
else {
    Write-Host "ERROR: No encryption key found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Either:"
    Write-Host "  1. Create .age-recipients file with public keys"
    Write-Host "  2. Generate a personal key: age-keygen -o $KeyFile"
    exit 1
}

Write-Host "[INFO] Encrypted: $InputFile -> $OutputFile" -ForegroundColor Green
Write-Host ""
Write-Host "Ready to commit:" -ForegroundColor Cyan
Write-Host "  git add $OutputFile"
Write-Host "  git commit -m 'Update encrypted config'"
```

### decrypt.ps1

```powershell
# decrypt.ps1 - Decrypt config.env.age

param(
    [string]$InputFile = "config.env.age",
    [string]$OutputFile = "config.env"
)

$ErrorActionPreference = "Stop"

# Check age is installed
if (-not (Get-Command age -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: age is not installed" -ForegroundColor Red
    exit 1
}

# Check encrypted file exists
if (-not (Test-Path $InputFile)) {
    Write-Host "ERROR: Encrypted file not found: $InputFile" -ForegroundColor Red
    exit 1
}

# Find private key
$KeyLocations = @(
    $env:AGE_KEY_FILE,
    "$env:USERPROFILE\.age\key.txt",
    ".\.age-key.txt"
) | Where-Object { $_ -and (Test-Path $_) }

if ($KeyLocations.Count -eq 0) {
    Write-Host "ERROR: No age private key found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Searched locations:"
    Write-Host "  - $env:USERPROFILE\.age\key.txt"
    Write-Host "  - .\.age-key.txt"
    Write-Host "  - `$env:AGE_KEY_FILE"
    exit 1
}

$KeyFile = $KeyLocations[0]
Write-Host "[INFO] Using key: $KeyFile" -ForegroundColor Green

# Decrypt
age -d -i $KeyFile -o $OutputFile $InputFile

if ($LASTEXITCODE -eq 0) {
    Write-Host "[INFO] Decrypted: $InputFile -> $OutputFile" -ForegroundColor Green
}
else {
    Write-Host "ERROR: Decryption failed!" -ForegroundColor Red
    exit 1
}
```

---

## Quick Workflow

### First Time Setup

```powershell
# 1. Install age
scoop install age

# 2. Generate key pair
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.age"
age-keygen -o "$env:USERPROFILE\.age\key.txt"

# 3. Copy your public key
Get-Content "$env:USERPROFILE\.age\key.txt" | Select-String "public key"

# 4. Add to .age-recipients (create this file in your repo)
# Paste your public key there
```

### Daily Workflow

```powershell
# Edit your config
notepad config.env

# Encrypt before commit
.\encrypt.ps1

# Commit encrypted version
git add config.env.age
git commit -m "Update config"
git push
```

### On Fresh Clone

```powershell
git clone your-repo
cd cf-tunnel-service

# Decrypt (needs your private key)
.\decrypt.ps1
```

---

## Option 2: Using WSL (If You Have It)

If you use WSL, you can use the Linux scripts directly:

```powershell
# From PowerShell, run in WSL
wsl ./encrypt.sh
wsl ./decrypt.sh
```

Or work entirely in WSL:
```bash
# In WSL terminal
cd /mnt/c/Users/YourName/projects/cf-tunnel-service
./encrypt.sh
```

---

## Option 3: Using Git Bash

Git Bash (comes with Git for Windows) can run the shell scripts:

```bash
# In Git Bash
./encrypt.sh
./decrypt.sh
```

You may need to install age in Git Bash's environment:
```bash
# Download age for Windows and extract to a PATH location
# Or use the Windows binary from PowerShell
```

---

## Transferring Keys to Raspberry Pi

### Using SCP (from PowerShell)

```powershell
# If you have OpenSSH client installed (Windows 10+)
scp "$env:USERPROFILE\.age\key.txt" pi@192.168.1.100:~/.age/key.txt
```

### Using PuTTY/PSCP

```powershell
pscp "%USERPROFILE%\.age\key.txt" pi@192.168.1.100:/home/pi/.age/key.txt
```

### Using WinSCP

1. Connect to your Pi
2. Navigate to `/home/pi/`
3. Create `.age` directory
4. Upload `key.txt` from `C:\Users\YourName\.age\`

### Manual Copy

1. Open the key file: `notepad "$env:USERPROFILE\.age\key.txt"`
2. SSH into Pi: `ssh pi@192.168.1.100`
3. Create directory: `mkdir -p ~/.age`
4. Create file: `nano ~/.age/key.txt`
5. Paste the content
6. Save and set permissions: `chmod 600 ~/.age/key.txt`

---

## VS Code Integration

Add tasks to `.vscode/tasks.json`:

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Encrypt Config",
            "type": "shell",
            "command": "powershell",
            "args": ["-ExecutionPolicy", "Bypass", "-File", "${workspaceFolder}/encrypt.ps1"],
            "group": "build",
            "presentation": {
                "echo": true,
                "reveal": "always"
            }
        },
        {
            "label": "Decrypt Config",
            "type": "shell", 
            "command": "powershell",
            "args": ["-ExecutionPolicy", "Bypass", "-File", "${workspaceFolder}/decrypt.ps1"],
            "group": "build",
            "presentation": {
                "echo": true,
                "reveal": "always"
            }
        }
    ]
}
```

Then use `Ctrl+Shift+P` → "Tasks: Run Task" → "Encrypt Config"

---

## Batch File Alternative

If you prefer `.bat` files:

### encrypt.bat

```batch
@echo off
setlocal

set INPUT_FILE=config.env
set OUTPUT_FILE=config.env.age
set KEY_FILE=%USERPROFILE%\.age\key.txt

if not exist "%INPUT_FILE%" (
    echo ERROR: %INPUT_FILE% not found
    exit /b 1
)

if exist ".age-recipients" (
    echo Using recipients file...
    age -R .age-recipients -o %OUTPUT_FILE% %INPUT_FILE%
) else if exist "%KEY_FILE%" (
    echo Using personal key...
    for /f "tokens=3" %%a in ('findstr "public key:" "%KEY_FILE%"') do set PUBLIC_KEY=%%a
    age -r %PUBLIC_KEY% -o %OUTPUT_FILE% %INPUT_FILE%
) else (
    echo ERROR: No encryption key found
    exit /b 1
)

echo Encrypted successfully: %OUTPUT_FILE%
echo.
echo Run: git add %OUTPUT_FILE%
```

### decrypt.bat

```batch
@echo off
setlocal

set INPUT_FILE=config.env.age
set OUTPUT_FILE=config.env
set KEY_FILE=%USERPROFILE%\.age\key.txt

if not exist "%INPUT_FILE%" (
    echo ERROR: %INPUT_FILE% not found
    exit /b 1
)

if not exist "%KEY_FILE%" (
    echo ERROR: Key file not found: %KEY_FILE%
    exit /b 1
)

age -d -i "%KEY_FILE%" -o %OUTPUT_FILE% %INPUT_FILE%

if %ERRORLEVEL% equ 0 (
    echo Decrypted successfully: %OUTPUT_FILE%
) else (
    echo ERROR: Decryption failed
    exit /b 1
)
```

---

## Summary

| Task | Command |
|------|---------|
| Install age | `scoop install age` |
| Generate key | `age-keygen -o "$env:USERPROFILE\.age\key.txt"` |
| View public key | `Get-Content "$env:USERPROFILE\.age\key.txt" \| Select-String "public"` |
| Encrypt | `.\encrypt.ps1` or `age -R .age-recipients -o config.env.age config.env` |
| Decrypt | `.\decrypt.ps1` or `age -d -i $env:USERPROFILE\.age\key.txt config.env.age > config.env` |
| Copy key to Pi | `scp "$env:USERPROFILE\.age\key.txt" pi@IP:~/.age/key.txt` |
