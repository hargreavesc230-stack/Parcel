@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~dp0"
cd /d "%ROOT_DIR%"

set "ENV_FILE=%ROOT_DIR%.env"
set "BASE_HOST=127.0.0.1"
set "HEALTH_PATH=/health"

if not exist "%ENV_FILE%" (
  echo [FAIL] missing .env at %ENV_FILE%
  exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in (`findstr /R /C:"^API_PORT=" "%ENV_FILE%"`) do set "API_PORT=%%B"
set "API_PORT=%API_PORT:"=%"

if not defined API_PORT (
  echo [FAIL] API_PORT not found in %ENV_FILE%
  exit /b 1
)

echo %API_PORT%| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
  echo [FAIL] API_PORT is not a number: %API_PORT%
  exit /b 1
)

set "PORT=%API_PORT%"
set "BASE_URL=http://%BASE_HOST%:%PORT%"

set "LOG_DIR=%ROOT_DIR%logs\check"
set "TEMP_DIR=%LOG_DIR%\temp-%RANDOM%%RANDOM%"
set "RESP_STATUS=%TEMP_DIR%\response_status.txt"
set "RESP_BODY=%TEMP_DIR%\response_body.txt"
set "FAIL=0"

echo [CHECK] expecting server already running
echo [CHECK] using port %PORT% (from %ENV_FILE%)
echo [CHECK] request details: GET %BASE_URL%%HEALTH_PATH%

if not exist "%LOG_DIR%" (
  mkdir "%LOG_DIR%"
  if errorlevel 1 (
    echo [FAIL] unable to create log directory "%LOG_DIR%"
    exit /b 1
  )
)

if not exist "%TEMP_DIR%" (
  mkdir "%TEMP_DIR%"
  if errorlevel 1 (
    echo [FAIL] unable to create temp directory "%TEMP_DIR%"
    exit /b 1
  )
)

powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $resp = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%HEALTH_PATH%' -Method Get -TimeoutSec 5; [IO.File]::WriteAllText('%RESP_STATUS%', [string]$resp.StatusCode, [Text.Encoding]::ASCII); [IO.File]::WriteAllText('%RESP_BODY%', $resp.Content, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] request failed
  set "FAIL=1"
  goto :cleanup
)

set /p RESP_STATUS=<"%RESP_STATUS%"
set /p RESP_BODY=<"%RESP_BODY%"

set "RESP_BODY_PREVIEW=!RESP_BODY!"
if not "!RESP_BODY:~200!"=="" set "RESP_BODY_PREVIEW=!RESP_BODY:~0,200!... (truncated)"

echo [CHECK] response status !RESP_STATUS!
echo [CHECK] response body !RESP_BODY_PREVIEW!

if "!RESP_STATUS!"=="200" (
  echo [PASS] status 200
) else (
  echo [FAIL] expected status 200 but got !RESP_STATUS!
  set "FAIL=1"
  goto :cleanup
)

if "!RESP_BODY!"=="ok" (
  echo [PASS] body ok
) else (
  echo [FAIL] expected body "ok" but got "!RESP_BODY!"
  set "FAIL=1"
  goto :cleanup
)

:cleanup
if exist "%TEMP_DIR%" (
  rmdir /s /q "%TEMP_DIR%"
)

if "%FAIL%"=="1" (
  exit /b 1
)

echo [PASS] all checks passed
exit /b 0
