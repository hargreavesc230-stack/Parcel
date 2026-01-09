@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~dp0"
cd /d "%ROOT_DIR%"

set "ENV_FILE=%ROOT_DIR%.env"
set "BASE_HOST=127.0.0.1"
set "HEALTH_PATH=/health"
set "UPLOAD_PATH=/upload"
set "DOWNLOAD_PATH=/download"
set "NEGATIVE_TOKEN=this_token_should_not_exist_123"
set "PAYLOAD_BYTES=2097152"
set "READINESS_ATTEMPTS=30"

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
set "SERVER_LOG=%LOG_DIR%\server-%RUN_ID%.log"
set "SERVER_ERR=%LOG_DIR%\server-%RUN_ID%.err.log"
set "SERVER_PID_FILE=%LOG_DIR%\server-%RUN_ID%.pid"
set "TEMP_DIR=%LOG_DIR%\temp-%RUN_ID%"
set "HEALTH_STATUS_FILE=%TEMP_DIR%\health_status.txt"
set "HEALTH_BODY_FILE=%TEMP_DIR%\health_body.txt"
set "UPLOAD_STATUS_FILE=%TEMP_DIR%\upload_status.txt"
set "UPLOAD_BODY_FILE=%TEMP_DIR%\upload_body.txt"
set "UPLOAD_TOKEN_FILE=%TEMP_DIR%\upload_token.txt"
set "DOWNLOAD_STATUS_FILE=%TEMP_DIR%\download_status.txt"
set "NEG_STATUS_FILE=%TEMP_DIR%\neg_status.txt"
set "COMPARE_LOG=%TEMP_DIR%\compare.log"
set "PAYLOAD_FILE=%TEMP_DIR%\payload.bin"
set "DOWNLOAD_FILE=%TEMP_DIR%\download.bin"
set "UPLOAD_PARSE_ERR=%TEMP_DIR%\upload_parse_err.txt"
set "FAIL=0"
set "READY=0"

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

echo [CHECK] starting server
echo [CHECK] server command: bun --cwd %ROOT_DIR%apps/api run dev
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $out = '%SERVER_LOG%'; $err = '%SERVER_ERR%'; $p = Start-Process -FilePath 'bun' -ArgumentList '--cwd','%ROOT_DIR%apps/api','run','dev' -WorkingDirectory '%ROOT_DIR%' -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -NoNewWindow; [IO.File]::WriteAllText('%SERVER_PID_FILE%', [string]$p.Id, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] failed to start server
  set "FAIL=1"
  goto :cleanup
)

if not exist "%SERVER_PID_FILE%" (
  echo [FAIL] server pid file missing
  set "FAIL=1"
  goto :cleanup
)

set /p SERVER_PID=<"%SERVER_PID_FILE%"
if not defined SERVER_PID (
  echo [FAIL] server PID not captured
  set "FAIL=1"
  goto :cleanup
)

echo [CHECK] server PID %SERVER_PID%
echo [CHECK] server log %SERVER_LOG%
echo [CHECK] server err %SERVER_ERR%
echo [CHECK] waiting for readiness

for /l %%I in (1,1,%READINESS_ATTEMPTS%) do (
  echo [CHECK] readiness attempt %%I/%READINESS_ATTEMPTS%
  powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%HEALTH_PATH%' -Method Get -TimeoutSec 2; if ($r.StatusCode -eq 200 -and $r.Content -eq 'ok') { exit 0 } else { exit 1 }"
  if !errorlevel! EQU 0 (
    set "READY=1"
    goto :ready
  )
  call :is_process_running %SERVER_PID%
  if "!PROCESS_RUNNING!"=="0" (
    echo [FAIL] server process exited before readiness
    set "FAIL=1"
    goto :cleanup
  )
  timeout /t 1 /nobreak >nul
)

:ready
if "%READY%"=="0" (
  echo [FAIL] server did not become ready
  set "FAIL=1"
  goto :cleanup
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

echo [CHECK] generating payload file
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $size = %PAYLOAD_BYTES%; $pattern = [Text.Encoding]::ASCII.GetBytes('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'); $buffer = New-Object byte[] 65536; for ($i = 0; $i -lt $buffer.Length; $i++) { $buffer[$i] = $pattern[$i %% $pattern.Length] }; $remaining = $size; $fs = [IO.File]::Open('%PAYLOAD_FILE%', [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None); try { while ($remaining -gt 0) { $toWrite = [Math]::Min($remaining, $buffer.Length); $fs.Write($buffer, 0, $toWrite); $remaining -= $toWrite } } finally { $fs.Close() }"
if errorlevel 1 (
  echo [FAIL] unable to generate payload file
  set "FAIL=1"
  goto :cleanup
)

for %%F in ("%PAYLOAD_FILE%") do set "UPLOAD_SIZE=%%~zF"
if not defined UPLOAD_SIZE (
  echo [FAIL] unable to determine payload size
  set "FAIL=1"
  goto :cleanup
)

echo [CHECK] payload size !UPLOAD_SIZE! bytes

echo [CHECK] request details: POST %BASE_URL%%UPLOAD_PATH%
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%UPLOAD_PATH%' -Method Post -InFile '%PAYLOAD_FILE%' -ContentType 'application/octet-stream' -TimeoutSec 60; [IO.File]::WriteAllText('%UPLOAD_STATUS_FILE%', [string]$r.StatusCode, [Text.Encoding]::ASCII); [IO.File]::WriteAllText('%UPLOAD_BODY_FILE%', $r.Content, [Text.Encoding]::ASCII)"
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

echo [CHECK] request details: GET %BASE_URL%%DOWNLOAD_PATH%/!UPLOAD_TOKEN!
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%DOWNLOAD_PATH%/!UPLOAD_TOKEN!' -Method Get -OutFile '%DOWNLOAD_FILE%' -TimeoutSec 60; [IO.File]::WriteAllText('%DOWNLOAD_STATUS_FILE%', [string]$r.StatusCode, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] download request failed
  set "FAIL=1"
  goto :cleanup
)

set /p DOWNLOAD_STATUS=<"%DOWNLOAD_STATUS_FILE%"
echo [CHECK] response status !DOWNLOAD_STATUS!
if "!DOWNLOAD_STATUS!"=="200" (
  echo [PASS] download status 200
) else (
  echo [FAIL] expected download status 200 but got !DOWNLOAD_STATUS!
  set "FAIL=1"
  goto :cleanup
)

for %%F in ("%DOWNLOAD_FILE%") do set "DOWNLOAD_SIZE=%%~zF"
if not defined DOWNLOAD_SIZE (
  echo [FAIL] unable to determine download size
  set "FAIL=1"
  goto :cleanup
)

echo [CHECK] upload size !UPLOAD_SIZE! bytes
echo [CHECK] download size !DOWNLOAD_SIZE! bytes

fc /b "%PAYLOAD_FILE%" "%DOWNLOAD_FILE%" > "%COMPARE_LOG%"
if errorlevel 2 (
  echo [FAIL] byte comparison failed
  set "FAIL=1"
  goto :cleanup
)
if errorlevel 1 (
  echo [FAIL] payload mismatch
  echo [CHECK] diff (tail^)
  powershell -NoProfile -Command "if (Test-Path '%COMPARE_LOG%') { Get-Content -Path '%COMPARE_LOG%' -Tail 20 }"
  set "FAIL=1"
  goto :cleanup
)

echo [PASS] payload integrity verified

echo [CHECK] request details: GET %BASE_URL%%DOWNLOAD_PATH%/%NEGATIVE_TOKEN%
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; try { $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%DOWNLOAD_PATH%/%NEGATIVE_TOKEN%' -Method Get -TimeoutSec 10; $status = [int]$r.StatusCode } catch { if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode } else { throw } }; [IO.File]::WriteAllText('%NEG_STATUS_FILE%', [string]$status, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] negative download request failed
  set "FAIL=1"
  goto :cleanup
)

set /p NEG_STATUS=<"%NEG_STATUS_FILE%"
echo [CHECK] response status !NEG_STATUS!
if "!NEG_STATUS!"=="404" (
  echo [PASS] download 404 for missing token
) else (
  echo [FAIL] expected 404 for missing token but got !NEG_STATUS!
  set "FAIL=1"
  goto :cleanup
)

:cleanup
if defined SERVER_PID (
  echo [CLEANUP] shutting down server %SERVER_PID%
  taskkill /PID %SERVER_PID% /T /F >nul 2>&1
  call :is_process_running %SERVER_PID%
  if "!PROCESS_RUNNING!"=="0" (
    echo [CLEANUP] process ended
  ) else (
    echo [CLEANUP] process still running
    set "FAIL=1"
  )
)

if exist "%SERVER_LOG%" (
  echo [CLEANUP] server log (tail^)
  powershell -NoProfile -Command "Get-Content -Path '%SERVER_LOG%' -Tail 40"
)

if exist "%SERVER_ERR%" (
  echo [CLEANUP] server err (tail^)
  powershell -NoProfile -Command "Get-Content -Path '%SERVER_ERR%' -Tail 40"
)

if exist "%TEMP_DIR%" (
  rmdir /s /q "%TEMP_DIR%"
)

if "%FAIL%"=="1" (
  exit /b 1
)

echo [PASS] all checks passed
exit /b 0

:is_process_running
set "PROCESS_RUNNING=0"
tasklist /fi "PID eq %~1" | findstr /i "%~1" >nul
if not errorlevel 1 set "PROCESS_RUNNING=1"
exit /b 0
