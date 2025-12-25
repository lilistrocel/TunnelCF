@echo off
REM decrypt.bat - Simple wrapper to decrypt config.env.age
REM Usage: decrypt.bat

setlocal

set INPUT_FILE=config.env.age
set OUTPUT_FILE=config.env
set KEY_FILE=%USERPROFILE%\.age\key.txt

REM Check age is installed
where age >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] age is not installed
    echo.
    echo Install with: scoop install age
    echo Or download from: https://github.com/FiloSottile/age/releases
    exit /b 1
)

REM Check encrypted file exists
if not exist "%INPUT_FILE%" (
    echo [ERROR] %INPUT_FILE% not found
    echo.
    echo Make sure you have the encrypted config:
    echo   git pull
    exit /b 1
)

REM Check key exists
if not exist "%KEY_FILE%" (
    echo [ERROR] Private key not found: %KEY_FILE%
    echo.
    echo Copy your key file to: %KEY_FILE%
    echo.
    echo Or generate a new one (if you encrypted with your own key):
    echo   mkdir "%USERPROFILE%\.age"
    echo   age-keygen -o "%KEY_FILE%"
    exit /b 1
)

echo [INFO] Using key: %KEY_FILE%
echo [INFO] Decrypting %INPUT_FILE%...

age -d -i "%KEY_FILE%" -o "%OUTPUT_FILE%" "%INPUT_FILE%"

if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Decryption failed!
    echo.
    echo Possible causes:
    echo   - Wrong private key
    echo   - Corrupted file
    echo   - File encrypted for different recipient
    exit /b 1
)

echo [INFO] Decrypted: %INPUT_FILE% -^> %OUTPUT_FILE%
echo.
echo Config ready!
