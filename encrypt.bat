@echo off
REM encrypt.bat - Simple wrapper to encrypt config.env
REM Usage: encrypt.bat

setlocal enabledelayedexpansion

set INPUT_FILE=config.env
set OUTPUT_FILE=config.env.age
set KEY_FILE=%USERPROFILE%\.age\key.txt
set RECIPIENTS_FILE=.age-recipients

REM Check age is installed
where age >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] age is not installed
    echo.
    echo Install with: scoop install age
    echo Or download from: https://github.com/FiloSottile/age/releases
    exit /b 1
)

REM Check input file exists
if not exist "%INPUT_FILE%" (
    echo [ERROR] %INPUT_FILE% not found
    echo.
    echo Create it from the example:
    echo   copy config.env.example config.env
    echo   notepad config.env
    exit /b 1
)

REM Try recipients file first, then personal key
if exist "%RECIPIENTS_FILE%" (
    echo [INFO] Using recipients file: %RECIPIENTS_FILE%
    age -R "%RECIPIENTS_FILE%" -o "%OUTPUT_FILE%" "%INPUT_FILE%"
) else if exist "%KEY_FILE%" (
    echo [INFO] Using personal key: %KEY_FILE%
    
    REM Extract public key from key file
    for /f "tokens=3" %%a in ('findstr /C:"public key:" "%KEY_FILE%"') do (
        set PUBLIC_KEY=%%a
    )
    
    if "!PUBLIC_KEY!"=="" (
        echo [ERROR] Could not extract public key from %KEY_FILE%
        exit /b 1
    )
    
    age -r !PUBLIC_KEY! -o "%OUTPUT_FILE%" "%INPUT_FILE%"
) else (
    echo [ERROR] No encryption key found!
    echo.
    echo Create a key with:
    echo   mkdir "%USERPROFILE%\.age"
    echo   age-keygen -o "%KEY_FILE%"
    exit /b 1
)

if %ERRORLEVEL% neq 0 (
    echo [ERROR] Encryption failed!
    exit /b 1
)

echo [INFO] Encrypted: %INPUT_FILE% -^> %OUTPUT_FILE%
echo.
echo Ready to commit:
echo   git add %OUTPUT_FILE%
echo   git commit -m "Update encrypted config"
