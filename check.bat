@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~dp0"
cd /d "%ROOT_DIR%"

set "ENV_FILE=%ROOT_DIR%.env"
set "BASE_HOST=127.0.0.1"
set "HEALTH_PATH=/health"
set "UPLOAD_PATH=/upload"
set "UPLOAD_PAYLOAD=hello parcel"

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
set "RUN_ID=%RANDOM%%RANDOM%"
set "TEMP_DIR=%LOG_DIR%\temp-%RUN_ID%"
set "HEALTH_STATUS_FILE=%TEMP_DIR%\health_status.txt"
set "HEALTH_BODY_FILE=%TEMP_DIR%\health_body.txt"
set "UPLOAD_STATUS_FILE=%TEMP_DIR%\upload_status.txt"
set "UPLOAD_BODY_FILE=%TEMP_DIR%\upload_body.txt"
set "UPLOAD_TOKEN_FILE=%TEMP_DIR%\upload_token.txt"
set "UPLOAD_SIZE_FILE=%TEMP_DIR%\upload_size.txt"
set "UPLOAD_PARSE_ERR=%TEMP_DIR%\upload_parse_err.txt"
set "FAIL=0"

echo [CHECK] expecting server already running
echo [CHECK] using port %PORT% (from %ENV_FILE%)

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

echo [CHECK] request details: GET %BASE_URL%%HEALTH_PATH%
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%HEALTH_PATH%' -Method Get -TimeoutSec 5; [IO.File]::WriteAllText('%HEALTH_STATUS_FILE%', [string]$r.StatusCode, [Text.Encoding]::ASCII); [IO.File]::WriteAllText('%HEALTH_BODY_FILE%', $r.Content, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] health request failed
  set "FAIL=1"
  goto :cleanup
)

set /p HEALTH_STATUS=<"%HEALTH_STATUS_FILE%"
set /p HEALTH_BODY=<"%HEALTH_BODY_FILE%"

set "HEALTH_BODY_PREVIEW=!HEALTH_BODY!"
if not "!HEALTH_BODY:~200!"=="" set "HEALTH_BODY_PREVIEW=!HEALTH_BODY:~0,200!... (truncated)"

echo [CHECK] response status !HEALTH_STATUS!
echo [CHECK] response body !HEALTH_BODY_PREVIEW!

if "!HEALTH_STATUS!"=="200" (
  echo [PASS] health status 200
) else (
  echo [FAIL] expected health status 200 but got !HEALTH_STATUS!
  set "FAIL=1"
  goto :cleanup
)

if "!HEALTH_BODY!"=="ok" (
  echo [PASS] health body ok
) else (
  echo [FAIL] expected health body "ok" but got "!HEALTH_BODY!"
  set "FAIL=1"
  goto :cleanup
)

type nul > "%UPLOAD_SIZE_FILE%"
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $payload = '%UPLOAD_PAYLOAD%'; [IO.File]::WriteAllText('%UPLOAD_SIZE_FILE%', [string][Text.Encoding]::UTF8.GetByteCount($payload), [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] unable to compute upload payload size
  set "FAIL=1"
  goto :cleanup
)

set "UPLOAD_SIZE="
set /p UPLOAD_SIZE=<"%UPLOAD_SIZE_FILE%"

echo [CHECK] request details: POST %BASE_URL%%UPLOAD_PATH%
echo [CHECK] payload size !UPLOAD_SIZE! bytes
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $bytes = [Text.Encoding]::UTF8.GetBytes('%UPLOAD_PAYLOAD%'); $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%UPLOAD_PATH%' -Method Post -Body $bytes -ContentType 'application/octet-stream' -TimeoutSec 10; [IO.File]::WriteAllText('%UPLOAD_STATUS_FILE%', [string]$r.StatusCode, [Text.Encoding]::ASCII); [IO.File]::WriteAllText('%UPLOAD_BODY_FILE%', $r.Content, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] upload request failed
  set "FAIL=1"
  goto :cleanup
)

set /p UPLOAD_STATUS=<"%UPLOAD_STATUS_FILE%"
set /p UPLOAD_BODY=<"%UPLOAD_BODY_FILE%"

set "UPLOAD_BODY_PREVIEW=!UPLOAD_BODY!"
if not "!UPLOAD_BODY:~200!"=="" set "UPLOAD_BODY_PREVIEW=!UPLOAD_BODY:~0,200!... (truncated)"

echo [CHECK] response status !UPLOAD_STATUS!
echo [CHECK] response body !UPLOAD_BODY_PREVIEW!

if "!UPLOAD_STATUS!"=="201" (
  echo [PASS] upload status 201
) else (
  echo [FAIL] expected upload status 201 but got !UPLOAD_STATUS!
  set "FAIL=1"
  goto :cleanup
)

type nul > "%UPLOAD_PARSE_ERR%"
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $json = Get-Content -Raw '%UPLOAD_BODY_FILE%'; $obj = $json | ConvertFrom-Json; if ($null -ne $obj.token -and $obj.token -ne '') { [IO.File]::WriteAllText('%UPLOAD_TOKEN_FILE%', $obj.token, [Text.Encoding]::ASCII); exit 0 } else { exit 1 }" 2> "%UPLOAD_PARSE_ERR%"
if errorlevel 1 (
  echo [FAIL] upload response JSON missing token
  if exist "%UPLOAD_PARSE_ERR%" (
    echo [CHECK] upload parse error (tail^)
    powershell -NoProfile -Command "if (Test-Path '%UPLOAD_PARSE_ERR%') { Get-Content -Path '%UPLOAD_PARSE_ERR%' -Tail 20 }"
  )
  set "FAIL=1"
  goto :cleanup
)

set /p UPLOAD_TOKEN=<"%UPLOAD_TOKEN_FILE%"
if not defined UPLOAD_TOKEN (
  echo [FAIL] upload token empty
  set "FAIL=1"
  goto :cleanup
)

echo [PASS] upload token present

:cleanup
if exist "%TEMP_DIR%" (
  rmdir /s /q "%TEMP_DIR%"
)

if "%FAIL%"=="1" (
  exit /b 1
)

echo [PASS] all checks passed
exit /b 0
