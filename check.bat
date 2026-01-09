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
for /f "usebackq tokens=1,* delims==" %%A in (`findstr /R /C:"^DATA_DIR=" "%ENV_FILE%"`) do set "DATA_DIR=%%B"
set "API_PORT=%API_PORT:"=%"
set "DATA_DIR=%DATA_DIR:"=%"

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

if not defined DATA_DIR (
  set "DATA_DIR=%ROOT_DIR%apps/api\data"
) else (
  set "DATA_DIR=%DATA_DIR:/=\%"
  if not "%DATA_DIR:~1,1%"==":" if not "%DATA_DIR:~0,1%"=="\\" (
    set "DATA_DIR=%ROOT_DIR%apps/api\%DATA_DIR%"
  )
)
for %%F in ("%DATA_DIR%") do set "DATA_DIR=%%~fF"
set "UPLOADS_DIR=%DATA_DIR%\uploads"
set "INDEX_FILE=%DATA_DIR%\index.jsonl"

set "LOG_DIR=%ROOT_DIR%logs\check"
set "RUN_ID=%RANDOM%%RANDOM%"
set "SERVER_START_COUNT=0"
set "SERVER_LOG="
set "SERVER_ERR="
set "SERVER_PID_FILE="
set "TEMP_DIR=%LOG_DIR%\temp-%RUN_ID%"
set "HEALTH_STATUS_FILE=%TEMP_DIR%\health_status.txt"
set "HEALTH_BODY_FILE=%TEMP_DIR%\health_body.txt"
set "UPLOAD1_STATUS_FILE=%TEMP_DIR%\upload1_status.txt"
set "UPLOAD1_BODY_FILE=%TEMP_DIR%\upload1_body.txt"
set "UPLOAD1_TOKEN_FILE=%TEMP_DIR%\upload1_token.txt"
set "UPLOAD2_STATUS_FILE=%TEMP_DIR%\upload2_status.txt"
set "UPLOAD2_BODY_FILE=%TEMP_DIR%\upload2_body.txt"
set "UPLOAD2_TOKEN_FILE=%TEMP_DIR%\upload2_token.txt"
set "DOWNLOAD1_STATUS_FILE=%TEMP_DIR%\download1_status.txt"
set "DOWNLOAD2_STATUS_FILE=%TEMP_DIR%\download2_status.txt"
set "NEG_STATUS_FILE=%TEMP_DIR%\neg_status.txt"
set "COMPARE1_LOG=%TEMP_DIR%\compare1.log"
set "COMPARE2_LOG=%TEMP_DIR%\compare2.log"
set "INDEX_STATS_FILE=%TEMP_DIR%\index_stats.txt"
set "PAYLOAD_FILE=%TEMP_DIR%\payload.bin"
set "DOWNLOAD_FILE_1=%TEMP_DIR%\download1.bin"
set "DOWNLOAD_FILE_2=%TEMP_DIR%\download2.bin"
set "UPLOAD_PARSE_ERR=%TEMP_DIR%\upload_parse_err.txt"
set "FAIL=0"
set "READY=0"

echo [CHECK] using port %PORT% (from %ENV_FILE%)
echo [CHECK] data dir %DATA_DIR%
echo [CHECK] uploads dir %UPLOADS_DIR%
echo [CHECK] index file %INDEX_FILE%

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

call :start_server
if "%FAIL%"=="1" goto :cleanup
call :wait_ready
if "%FAIL%"=="1" goto :cleanup

echo [CHECK] phase: health
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

echo [CHECK] phase: upload
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

echo [CHECK] request details: POST %BASE_URL%%UPLOAD_PATH% (upload 1)
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%UPLOAD_PATH%' -Method Post -InFile '%PAYLOAD_FILE%' -ContentType 'application/octet-stream' -TimeoutSec 60; [IO.File]::WriteAllText('%UPLOAD1_STATUS_FILE%', [string]$r.StatusCode, [Text.Encoding]::ASCII); [IO.File]::WriteAllText('%UPLOAD1_BODY_FILE%', $r.Content, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] upload 1 request failed
  set "FAIL=1"
  goto :cleanup
)

set /p UPLOAD1_STATUS=<"%UPLOAD1_STATUS_FILE%"
set /p UPLOAD1_BODY=<"%UPLOAD1_BODY_FILE%"

set "UPLOAD1_BODY_PREVIEW=!UPLOAD1_BODY!"
if not "!UPLOAD1_BODY:~200!"=="" set "UPLOAD1_BODY_PREVIEW=!UPLOAD1_BODY:~0,200!... (truncated)"

echo [CHECK] response status !UPLOAD1_STATUS!
echo [CHECK] response body !UPLOAD1_BODY_PREVIEW!

if "!UPLOAD1_STATUS!"=="201" (
  echo [PASS] upload 1 status 201
) else (
  echo [FAIL] expected upload 1 status 201 but got !UPLOAD1_STATUS!
  set "FAIL=1"
  goto :cleanup
)

type nul > "%UPLOAD_PARSE_ERR%"
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $json = Get-Content -Raw '%UPLOAD1_BODY_FILE%'; $obj = $json | ConvertFrom-Json; if ($null -ne $obj.token -and $obj.token -ne '') { [IO.File]::WriteAllText('%UPLOAD1_TOKEN_FILE%', $obj.token, [Text.Encoding]::ASCII); exit 0 } else { exit 1 }" 2> "%UPLOAD_PARSE_ERR%"
if errorlevel 1 (
  echo [FAIL] upload 1 response JSON missing token
  if exist "%UPLOAD_PARSE_ERR%" (
    echo [CHECK] upload 1 parse error (tail^)
    powershell -NoProfile -Command "if (Test-Path '%UPLOAD_PARSE_ERR%') { Get-Content -Path '%UPLOAD_PARSE_ERR%' -Tail 20 }"
  )
  set "FAIL=1"
  goto :cleanup
)

set /p UPLOAD_TOKEN_1=<"%UPLOAD1_TOKEN_FILE%"
if not defined UPLOAD_TOKEN_1 (
  echo [FAIL] upload 1 token empty
  set "FAIL=1"
  goto :cleanup
)

echo [PASS] upload 1 token present

echo [CHECK] request details: POST %BASE_URL%%UPLOAD_PATH% (upload 2)
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%UPLOAD_PATH%' -Method Post -InFile '%PAYLOAD_FILE%' -ContentType 'application/octet-stream' -TimeoutSec 60; [IO.File]::WriteAllText('%UPLOAD2_STATUS_FILE%', [string]$r.StatusCode, [Text.Encoding]::ASCII); [IO.File]::WriteAllText('%UPLOAD2_BODY_FILE%', $r.Content, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] upload 2 request failed
  set "FAIL=1"
  goto :cleanup
)

set /p UPLOAD2_STATUS=<"%UPLOAD2_STATUS_FILE%"
set /p UPLOAD2_BODY=<"%UPLOAD2_BODY_FILE%"

set "UPLOAD2_BODY_PREVIEW=!UPLOAD2_BODY!"
if not "!UPLOAD2_BODY:~200!"=="" set "UPLOAD2_BODY_PREVIEW=!UPLOAD2_BODY:~0,200!... (truncated)"

echo [CHECK] response status !UPLOAD2_STATUS!
echo [CHECK] response body !UPLOAD2_BODY_PREVIEW!

if "!UPLOAD2_STATUS!"=="201" (
  echo [PASS] upload 2 status 201
) else (
  echo [FAIL] expected upload 2 status 201 but got !UPLOAD2_STATUS!
  set "FAIL=1"
  goto :cleanup
)

type nul > "%UPLOAD_PARSE_ERR%"
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $json = Get-Content -Raw '%UPLOAD2_BODY_FILE%'; $obj = $json | ConvertFrom-Json; if ($null -ne $obj.token -and $obj.token -ne '') { [IO.File]::WriteAllText('%UPLOAD2_TOKEN_FILE%', $obj.token, [Text.Encoding]::ASCII); exit 0 } else { exit 1 }" 2> "%UPLOAD_PARSE_ERR%"
if errorlevel 1 (
  echo [FAIL] upload 2 response JSON missing token
  if exist "%UPLOAD_PARSE_ERR%" (
    echo [CHECK] upload 2 parse error (tail^)
    powershell -NoProfile -Command "if (Test-Path '%UPLOAD_PARSE_ERR%') { Get-Content -Path '%UPLOAD_PARSE_ERR%' -Tail 20 }"
  )
  set "FAIL=1"
  goto :cleanup
)

set /p UPLOAD_TOKEN_2=<"%UPLOAD2_TOKEN_FILE%"
if not defined UPLOAD_TOKEN_2 (
  echo [FAIL] upload 2 token empty
  set "FAIL=1"
  goto :cleanup
)

echo [PASS] upload 2 token present
echo [CHECK] upload tokens: !UPLOAD_TOKEN_1! , !UPLOAD_TOKEN_2!
if "!UPLOAD_TOKEN_1!"=="!UPLOAD_TOKEN_2!" (
  echo [FAIL] upload tokens are not unique
  set "FAIL=1"
  goto :cleanup
)

echo [PASS] upload tokens are unique

echo [CHECK] phase: layout
echo [CHECK] verifying data layout
if not exist "%DATA_DIR%" (
  echo [FAIL] data dir missing: %DATA_DIR%
  set "FAIL=1"
  goto :cleanup
)
if not exist "%UPLOADS_DIR%" (
  echo [FAIL] uploads dir missing: %UPLOADS_DIR%
  set "FAIL=1"
  goto :cleanup
)
if not exist "%INDEX_FILE%" (
  echo [FAIL] index file missing: %INDEX_FILE%
  set "FAIL=1"
  goto :cleanup
)

echo [CHECK] data dir entries (names only)
dir /b "%DATA_DIR%"

set "UPLOADS_COUNT=0"
for /f %%C in ('dir /b /a:-d "%UPLOADS_DIR%" ^| find /c /v ""') do set "UPLOADS_COUNT=%%C"
if %UPLOADS_COUNT% GEQ 1 (
  echo [PASS] uploads dir contains files: %UPLOADS_COUNT%
) else (
  echo [FAIL] uploads dir has no files
  set "FAIL=1"
  goto :cleanup
)

powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $lines = Get-Content -Path '%INDEX_FILE%' | Where-Object { $_.Trim() -ne '' }; $tokens = @(); foreach ($line in $lines) { $obj = $line | ConvertFrom-Json; if (-not $obj.token -or -not $obj.storage_id) { throw 'missing fields' }; $tokens += $obj.token }; $unique = $tokens | Select-Object -Unique; if ($tokens.Count -ne $unique.Count) { exit 2 }; if ($tokens -notcontains '%UPLOAD_TOKEN_1%' -or $tokens -notcontains '%UPLOAD_TOKEN_2%') { exit 3 }; [IO.File]::WriteAllText('%INDEX_STATS_FILE%', "$($tokens.Count)|$($unique.Count)", [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] index file validation failed
  set "FAIL=1"
  goto :cleanup
)

for /f "usebackq tokens=1,2 delims=|" %%A in ("%INDEX_STATS_FILE%") do (
  set "INDEX_TOTAL=%%A"
  set "INDEX_UNIQUE=%%B"
)

echo [CHECK] index tokens %INDEX_TOTAL% total, %INDEX_UNIQUE% unique
echo [PASS] index contains distinct tokens

echo [CHECK] phase: download (pre-restart)
echo [CHECK] request details: GET %BASE_URL%%DOWNLOAD_PATH%/!UPLOAD_TOKEN_1! (pre-restart)
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%DOWNLOAD_PATH%/!UPLOAD_TOKEN_1!' -Method Get -OutFile '%DOWNLOAD_FILE_1%' -PassThru -TimeoutSec 60; [IO.File]::WriteAllText('%DOWNLOAD1_STATUS_FILE%', [string]$r.StatusCode, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] download pre-restart request failed
  set "FAIL=1"
  goto :cleanup
)

set /p DOWNLOAD1_STATUS=<"%DOWNLOAD1_STATUS_FILE%"
echo [CHECK] response status !DOWNLOAD1_STATUS!
if "!DOWNLOAD1_STATUS!"=="200" (
  echo [PASS] download pre-restart status 200
) else (
  echo [FAIL] expected download pre-restart status 200 but got !DOWNLOAD1_STATUS!
  set "FAIL=1"
  goto :cleanup
)

for %%F in ("%DOWNLOAD_FILE_1%") do set "DOWNLOAD1_SIZE=%%~zF"
if not defined DOWNLOAD1_SIZE (
  echo [FAIL] unable to determine pre-restart download size
  set "FAIL=1"
  goto :cleanup
)

echo [CHECK] upload size !UPLOAD_SIZE! bytes
echo [CHECK] pre-restart download size !DOWNLOAD1_SIZE! bytes

fc /b "%PAYLOAD_FILE%" "%DOWNLOAD_FILE_1%" > "%COMPARE1_LOG%"
if errorlevel 2 (
  echo [FAIL] byte comparison failed
  set "FAIL=1"
  goto :cleanup
)
if errorlevel 1 (
  echo [FAIL] payload mismatch before restart
  echo [CHECK] diff (tail^)
  powershell -NoProfile -Command "if (Test-Path '%COMPARE1_LOG%') { Get-Content -Path '%COMPARE1_LOG%' -Tail 20 }"
  set "FAIL=1"
  goto :cleanup
)

echo [PASS] payload integrity verified before restart

echo [CHECK] phase: restart
echo [CHECK] restarting server
call :stop_server
if "%FAIL%"=="1" goto :cleanup
call :start_server
if "%FAIL%"=="1" goto :cleanup
call :wait_ready
if "%FAIL%"=="1" goto :cleanup

echo [CHECK] phase: download (post-restart)
echo [CHECK] request details: GET %BASE_URL%%DOWNLOAD_PATH%/!UPLOAD_TOKEN_1! (post-restart)
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%DOWNLOAD_PATH%/!UPLOAD_TOKEN_1!' -Method Get -OutFile '%DOWNLOAD_FILE_2%' -PassThru -TimeoutSec 60; [IO.File]::WriteAllText('%DOWNLOAD2_STATUS_FILE%', [string]$r.StatusCode, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] download post-restart request failed
  set "FAIL=1"
  goto :cleanup
)

set /p DOWNLOAD2_STATUS=<"%DOWNLOAD2_STATUS_FILE%"
echo [CHECK] response status !DOWNLOAD2_STATUS!
if "!DOWNLOAD2_STATUS!"=="200" (
  echo [PASS] download post-restart status 200
) else (
  echo [FAIL] expected download post-restart status 200 but got !DOWNLOAD2_STATUS!
  set "FAIL=1"
  goto :cleanup
)

for %%F in ("%DOWNLOAD_FILE_2%") do set "DOWNLOAD2_SIZE=%%~zF"
if not defined DOWNLOAD2_SIZE (
  echo [FAIL] unable to determine post-restart download size
  set "FAIL=1"
  goto :cleanup
)

echo [CHECK] post-restart download size !DOWNLOAD2_SIZE! bytes

fc /b "%PAYLOAD_FILE%" "%DOWNLOAD_FILE_2%" > "%COMPARE2_LOG%"
if errorlevel 2 (
  echo [FAIL] byte comparison failed
  set "FAIL=1"
  goto :cleanup
)
if errorlevel 1 (
  echo [FAIL] payload mismatch after restart
  echo [CHECK] diff (tail^)
  powershell -NoProfile -Command "if (Test-Path '%COMPARE2_LOG%') { Get-Content -Path '%COMPARE2_LOG%' -Tail 20 }"
  set "FAIL=1"
  goto :cleanup
)

echo [PASS] payload integrity verified after restart

echo [CHECK] phase: negative download
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
call :stop_server

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

:start_server
set "READY=0"
set "SERVER_PID="
set /a SERVER_START_COUNT+=1
set "SERVER_LOG=%LOG_DIR%\server-%RUN_ID%-%SERVER_START_COUNT%.log"
set "SERVER_ERR=%LOG_DIR%\server-%RUN_ID%-%SERVER_START_COUNT%.err.log"
set "SERVER_PID_FILE=%LOG_DIR%\server-%RUN_ID%-%SERVER_START_COUNT%.pid"

echo [CHECK] verifying port %PORT% is free
set "PORT_PID="
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%PORT% .*LISTENING"') do (
  if not defined PORT_PID set "PORT_PID=%%P"
)
if defined PORT_PID (
  echo [FAIL] port %PORT% already in use by PID %PORT_PID%
  set "FAIL=1"
  exit /b 0
)

echo [CHECK] starting server
echo [CHECK] server command: bun run dev (cwd=%ROOT_DIR%apps/api)
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $out = '%SERVER_LOG%'; $err = '%SERVER_ERR%'; $p = Start-Process -FilePath 'bun' -ArgumentList 'run','dev' -WorkingDirectory '%ROOT_DIR%apps/api' -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -NoNewWindow; [IO.File]::WriteAllText('%SERVER_PID_FILE%', [string]$p.Id, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] failed to start server
  set "FAIL=1"
  exit /b 0
)

if not exist "%SERVER_PID_FILE%" (
  echo [FAIL] server pid file missing
  set "FAIL=1"
  exit /b 0
)

set /p SERVER_PID=<"%SERVER_PID_FILE%"
if not defined SERVER_PID (
  echo [FAIL] server PID not captured
  set "FAIL=1"
  exit /b 0
)

echo [CHECK] server PID %SERVER_PID%
echo [CHECK] server log %SERVER_LOG%
echo [CHECK] server err %SERVER_ERR%
exit /b 0

:wait_ready
echo [CHECK] waiting for readiness
for /l %%I in (1,1,%READINESS_ATTEMPTS%) do (
  echo [CHECK] readiness attempt %%I/%READINESS_ATTEMPTS%
  powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%HEALTH_PATH%' -Method Get -TimeoutSec 2; if ($r.StatusCode -eq 200 -and $r.Content -eq 'ok') { exit 0 } else { exit 1 }"
  if !errorlevel! EQU 0 (
    set "READY=1"
    goto :ready_done
  )
  if defined SERVER_PID (
    call :is_process_running %SERVER_PID%
    if "!PROCESS_RUNNING!"=="0" (
      echo [FAIL] server process exited before readiness
      set "FAIL=1"
      goto :ready_done
    )
  )
  timeout /t 1 /nobreak >nul
)

:ready_done
if "%READY%"=="0" (
  echo [FAIL] server did not become ready
  set "FAIL=1"
)
exit /b 0

:stop_server
if not defined SERVER_PID exit /b 0
echo [CLEANUP] shutting down server %SERVER_PID%
taskkill /PID %SERVER_PID% /T /F >nul 2>&1
call :is_process_running %SERVER_PID%
if "!PROCESS_RUNNING!"=="0" (
  echo [CLEANUP] process ended
) else (
  echo [CLEANUP] process still running
  set "FAIL=1"
)
set "SERVER_PID="
exit /b 0

:is_process_running
set "PROCESS_RUNNING=0"
tasklist /fi "PID eq %~1" | findstr /i "%~1" >nul
if not errorlevel 1 set "PROCESS_RUNNING=1"
exit /b 0
