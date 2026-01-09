@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~dp0"
cd /d "%ROOT_DIR%"

set "ENV_FILE=%ROOT_DIR%.env"
set "BASE_HOST=127.0.0.1"
set "HEALTH_PATH=/health"
set "UPLOAD_PATH=/upload"
set "READINESS_ATTEMPTS=30"

set "LOG_DIR=%ROOT_DIR%logs\check"
set "RUN_ID=%RANDOM%%RANDOM%"
set "TEMP_DIR=%LOG_DIR%\temp-%RUN_ID%"

set "HEALTH_STATUS_FILE=%TEMP_DIR%\health_status.txt"
set "HEALTH_BODY_FILE=%TEMP_DIR%\health_body.txt"

set "UPLOAD_TOO_LARGE_STATUS_FILE=%TEMP_DIR%\upload_too_large_status.txt"
set "UPLOAD_TOO_LARGE_BODY_FILE=%TEMP_DIR%\upload_too_large_body.txt"
set "UPLOAD_PARSE_ERR=%TEMP_DIR%\upload_parse_err.txt"

set "PAYLOAD_TOO_LARGE_FILE=%TEMP_DIR%\payload-too-large.bin"

set "INDEX_COUNT_BEFORE_FILE=%TEMP_DIR%\index_count_before.txt"
set "INDEX_COUNT_AFTER_FILE=%TEMP_DIR%\index_count_after.txt"
set "UPLOADS_COUNT_BEFORE_FILE=%TEMP_DIR%\uploads_count_before.txt"
set "UPLOADS_COUNT_AFTER_FILE=%TEMP_DIR%\uploads_count_after.txt"

set "FAIL=0"
set "READY=0"

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

call :load_env
if "%FAIL%"=="1" goto :cleanup

if %MAX_UPLOAD_SIZE% LEQ 0 (
  echo [FAIL] MAX_UPLOAD_SIZE must be greater than 0 for this check
  set "FAIL=1"
  goto :cleanup
)

set /a PAYLOAD_TOO_LARGE_BYTES=%MAX_UPLOAD_SIZE%+1024

echo [CHECK] expecting server already running
echo [CHECK] using port %PORT% (from %ENV_FILE%)
echo [CHECK] data dir %DATA_DIR%
echo [CHECK] uploads dir %UPLOADS_DIR%
echo [CHECK] index file %INDEX_FILE%
echo [CHECK] MAX_UPLOAD_SIZE=%MAX_UPLOAD_SIZE%

call :wait_ready
if "%FAIL%"=="1" goto :cleanup

call :check_health
if "%FAIL%"=="1" goto :cleanup

call :record_index_count "%INDEX_COUNT_BEFORE_FILE%"
if "%FAIL%"=="1" goto :cleanup
call :record_uploads_count "%UPLOADS_COUNT_BEFORE_FILE%"
if "%FAIL%"=="1" goto :cleanup

echo [CHECK] generating payload file %PAYLOAD_TOO_LARGE_FILE%
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $size = %PAYLOAD_TOO_LARGE_BYTES%; $pattern = [Text.Encoding]::ASCII.GetBytes('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'); $buffer = New-Object byte[] 65536; for ($i = 0; $i -lt $buffer.Length; $i++) { $buffer[$i] = $pattern[$i %% $pattern.Length] }; $remaining = $size; $fs = [IO.File]::Open('%PAYLOAD_TOO_LARGE_FILE%', [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None); try { while ($remaining -gt 0) { $toWrite = [Math]::Min($remaining, $buffer.Length); $fs.Write($buffer, 0, $toWrite); $remaining -= $toWrite } } finally { $fs.Close() }"
if errorlevel 1 (
  echo [FAIL] unable to generate payload file
  set "FAIL=1"
  goto :cleanup
)

for %%F in ("%PAYLOAD_TOO_LARGE_FILE%") do set "PAYLOAD_SIZE=%%~zF"
if not defined PAYLOAD_SIZE (
  echo [FAIL] unable to determine payload size
  set "FAIL=1"
  goto :cleanup
)

echo [CHECK] payload size !PAYLOAD_SIZE! bytes

echo [CHECK] request details: POST %BASE_URL%%UPLOAD_PATH% (too large)
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; try { $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%UPLOAD_PATH%' -Method Post -InFile '%PAYLOAD_TOO_LARGE_FILE%' -ContentType 'application/octet-stream' -TimeoutSec 60; $status = [int]$r.StatusCode; $content = $r.Content } catch { if ($_.Exception.Response) { $resp = $_.Exception.Response; $status = [int]$resp.StatusCode; try { $reader = New-Object IO.StreamReader($resp.GetResponseStream()); $content = $reader.ReadToEnd() } catch { $content = '' } } else { throw } }; [IO.File]::WriteAllText('%UPLOAD_TOO_LARGE_STATUS_FILE%', [string]$status, [Text.Encoding]::ASCII); [IO.File]::WriteAllText('%UPLOAD_TOO_LARGE_BODY_FILE%', $content, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] upload too large request failed
  set "FAIL=1"
  goto :cleanup
)

set /p UPLOAD_TOO_LARGE_STATUS=<"%UPLOAD_TOO_LARGE_STATUS_FILE%"
set /p UPLOAD_TOO_LARGE_BODY=<"%UPLOAD_TOO_LARGE_BODY_FILE%"

set "UPLOAD_TOO_LARGE_BODY_PREVIEW=!UPLOAD_TOO_LARGE_BODY!"
if not "!UPLOAD_TOO_LARGE_BODY:~200!"=="" set "UPLOAD_TOO_LARGE_BODY_PREVIEW=!UPLOAD_TOO_LARGE_BODY:~0,200!... (truncated)"

echo [CHECK] response status !UPLOAD_TOO_LARGE_STATUS!
echo [CHECK] response body !UPLOAD_TOO_LARGE_BODY_PREVIEW!

if "!UPLOAD_TOO_LARGE_STATUS!"=="413" (
  echo [PASS] upload too large status 413
) else (
  echo [FAIL] expected upload too large status 413 but got !UPLOAD_TOO_LARGE_STATUS!
  set "FAIL=1"
  goto :cleanup
)

echo !UPLOAD_TOO_LARGE_BODY! | findstr /i "token" >nul
if not errorlevel 1 (
  echo [FAIL] upload too large response includes token
  set "FAIL=1"
  goto :cleanup
)

echo !UPLOAD_TOO_LARGE_BODY! | findstr /i "uploads index.jsonl data" >nul
if not errorlevel 1 (
  echo [FAIL] upload too large response leaks internal paths
  set "FAIL=1"
  goto :cleanup
)

call :record_index_count "%INDEX_COUNT_AFTER_FILE%"
if "%FAIL%"=="1" goto :cleanup
call :record_uploads_count "%UPLOADS_COUNT_AFTER_FILE%"
if "%FAIL%"=="1" goto :cleanup

set /p INDEX_COUNT_BEFORE=<"%INDEX_COUNT_BEFORE_FILE%"
set /p INDEX_COUNT_AFTER=<"%INDEX_COUNT_AFTER_FILE%"
set /p UPLOADS_COUNT_BEFORE=<"%UPLOADS_COUNT_BEFORE_FILE%"
set /p UPLOADS_COUNT_AFTER=<"%UPLOADS_COUNT_AFTER_FILE%"

echo [CHECK] index count before !INDEX_COUNT_BEFORE! after !INDEX_COUNT_AFTER!
if "!INDEX_COUNT_BEFORE!"=="!INDEX_COUNT_AFTER!" (
  echo [PASS] index count unchanged after rejected upload
) else (
  echo [FAIL] index count changed after rejected upload
  set "FAIL=1"
  goto :cleanup
)

echo [CHECK] uploads count before !UPLOADS_COUNT_BEFORE! after !UPLOADS_COUNT_AFTER!
if "!UPLOADS_COUNT_BEFORE!"=="!UPLOADS_COUNT_AFTER!" (
  echo [PASS] uploads dir unchanged after rejected upload
) else (
  echo [FAIL] uploads dir changed after rejected upload
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

:load_env
if not exist "%ENV_FILE%" (
  echo [FAIL] missing .env at %ENV_FILE%
  set "FAIL=1"
  exit /b 0
)

set "API_PORT="
set "DATA_DIR="
set "MAX_UPLOAD_SIZE="

for /f "usebackq tokens=1,* delims==" %%A in (`findstr /R /C:"^API_PORT=" "%ENV_FILE%"`) do set "API_PORT=%%B"
for /f "usebackq tokens=1,* delims==" %%A in (`findstr /R /C:"^DATA_DIR=" "%ENV_FILE%"`) do set "DATA_DIR=%%B"
for /f "usebackq tokens=1,* delims==" %%A in (`findstr /R /C:"^MAX_UPLOAD_SIZE=" "%ENV_FILE%"`) do set "MAX_UPLOAD_SIZE=%%B"

set "API_PORT=%API_PORT:"=%"
set "DATA_DIR=%DATA_DIR:"=%"
set "MAX_UPLOAD_SIZE=%MAX_UPLOAD_SIZE:"=%"

if not defined API_PORT (
  echo [FAIL] API_PORT not found in %ENV_FILE%
  set "FAIL=1"
  exit /b 0
)

if not defined DATA_DIR (
  echo [FAIL] DATA_DIR not found in %ENV_FILE%
  set "FAIL=1"
  exit /b 0
)

if not defined MAX_UPLOAD_SIZE (
  echo [FAIL] MAX_UPLOAD_SIZE not found in %ENV_FILE%
  set "FAIL=1"
  exit /b 0
)

echo %API_PORT%| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
  echo [FAIL] API_PORT is not a number: %API_PORT%
  set "FAIL=1"
  exit /b 0
)

echo %MAX_UPLOAD_SIZE%| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
  echo [FAIL] MAX_UPLOAD_SIZE is not a non-negative number: %MAX_UPLOAD_SIZE%
  set "FAIL=1"
  exit /b 0
)

set "PORT=%API_PORT%"
set "BASE_URL=http://%BASE_HOST%:%PORT%"

set "DATA_DIR=%DATA_DIR:/=\%"
if not "%DATA_DIR:~1,1%"==":" if not "%DATA_DIR:~0,1%"=="\\" (
  set "DATA_DIR=%ROOT_DIR%%DATA_DIR%"
)
for %%F in ("%DATA_DIR%") do set "DATA_DIR=%%~fF"
set "UPLOADS_DIR=%DATA_DIR%\uploads"
set "INDEX_FILE=%DATA_DIR%\index.jsonl"
exit /b 0

:wait_ready
echo [CHECK] waiting for readiness
set "READY=0"
for /l %%I in (1,1,%READINESS_ATTEMPTS%) do (
  echo [CHECK] readiness attempt %%I/%READINESS_ATTEMPTS%
  powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%HEALTH_PATH%' -Method Get -TimeoutSec 2; if ($r.StatusCode -eq 200 -and $r.Content -eq 'ok') { exit 0 } else { exit 1 }"
  if !errorlevel! EQU 0 (
    set "READY=1"
    goto :ready_done
  )
  timeout /t 1 /nobreak >nul
)

:ready_done
if "%READY%"=="0" (
  echo [FAIL] server did not become ready
  set "FAIL=1"
)
exit /b 0

:check_health
echo [CHECK] phase: health
echo [CHECK] request details: GET %BASE_URL%%HEALTH_PATH%
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%HEALTH_PATH%' -Method Get -TimeoutSec 5; [IO.File]::WriteAllText('%HEALTH_STATUS_FILE%', [string]$r.StatusCode, [Text.Encoding]::ASCII); [IO.File]::WriteAllText('%HEALTH_BODY_FILE%', $r.Content, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] health request failed
  set "FAIL=1"
  exit /b 0
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
  exit /b 0
)

if "!HEALTH_BODY!"=="ok" (
  echo [PASS] health body ok
) else (
  echo [FAIL] expected health body "ok" but got "!HEALTH_BODY!"
  set "FAIL=1"
)
exit /b 0

:record_index_count
set "COUNT_FILE=%~1"
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; if (Test-Path '%INDEX_FILE%') { $count = (Get-Content -Path '%INDEX_FILE%' | Where-Object { $_.Trim() -ne '' }).Count } else { $count = 0 }; [IO.File]::WriteAllText('%COUNT_FILE%', [string]$count, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] unable to count index lines
  set "FAIL=1"
)
exit /b 0

:record_uploads_count
set "COUNT_FILE=%~1"
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; if (Test-Path '%UPLOADS_DIR%') { $count = (Get-ChildItem -Path '%UPLOADS_DIR%' -File | Measure-Object).Count } else { $count = 0 }; [IO.File]::WriteAllText('%COUNT_FILE%', [string]$count, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] unable to count uploads files
  set "FAIL=1"
)
exit /b 0
