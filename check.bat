@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~dp0"
cd /d "%ROOT_DIR%"

set "ENV_FILE=%ROOT_DIR%.env"
set "BASE_HOST=127.0.0.1"
set "HEALTH_PATH=/health"
set "UPLOAD_PATH=/upload"
set "DOWNLOAD_PATH=/download"
set "INSPECT_PATH=/inspect"
set "READINESS_ATTEMPTS=30"

set "LOG_DIR=%ROOT_DIR%logs\check"
set "RUN_ID=%RANDOM%%RANDOM%"
set "TEMP_DIR=%LOG_DIR%\temp-%RUN_ID%"
set "HEALTH_STATUS_FILE=%TEMP_DIR%\health_status.txt"
set "HEALTH_BODY_FILE=%TEMP_DIR%\health_body.txt"

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

echo [CHECK] expecting server already running
echo [CHECK] using port %PORT% (from %ENV_FILE%)
echo [CHECK] data dir %DATA_DIR%
echo [CHECK] uploads dir %UPLOADS_DIR%
echo [CHECK] index file %INDEX_FILE%
echo [CHECK] MAX_UPLOAD_SIZE=%MAX_UPLOAD_SIZE%
echo [CHECK] PARCEL_STRIP_IMAGE_METADATA=%PARCEL_STRIP_IMAGE_METADATA%

call :wait_ready
if "%FAIL%"=="1" goto :cleanup

call :check_health
if "%FAIL%"=="1" goto :cleanup

call :phase_baseline
if "%FAIL%"=="1" goto :cleanup

call :phase_sanitize
if "%FAIL%"=="1" goto :cleanup

:cleanup
if exist "%TEMP_DIR%" (
  echo [CLEANUP] removing temp files
  rmdir /s /q "%TEMP_DIR%"
)

if "%FAIL%"=="1" (
  exit /b 1
)

echo [PASS] all checks passed
exit /b 0

:phase_baseline
echo [CHECK] phase: baseline (upload/download/inspect)
call :compute_payload_size
if "%FAIL%"=="1" exit /b 0

set "PAYLOAD_FILE=%TEMP_DIR%\payload-main.bin"
set "DOWNLOAD_FILE=%TEMP_DIR%\download-main.bin"
set "UPLOAD_STATUS_FILE=%TEMP_DIR%\upload_main_status.txt"
set "UPLOAD_BODY_FILE=%TEMP_DIR%\upload_main_body.txt"
set "UPLOAD_TOKEN_FILE=%TEMP_DIR%\upload_main_token.txt"
set "INSPECT_STATUS_FILE=%TEMP_DIR%\inspect_main_status.txt"
set "INSPECT_BODY_FILE=%TEMP_DIR%\inspect_main_body.txt"
set "INSPECT_PARSED_FILE=%TEMP_DIR%\inspect_main_parsed.txt"
set "DOWNLOAD_STATUS_FILE=%TEMP_DIR%\download_main_status.txt"

echo [CHECK] generating payload file %PAYLOAD_FILE%
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $size = %PAYLOAD_MAIN_BYTES%; $pattern = [Text.Encoding]::ASCII.GetBytes('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'); $buffer = New-Object byte[] 65536; for ($i = 0; $i -lt $buffer.Length; $i++) { $buffer[$i] = $pattern[$i %% $pattern.Length] }; $remaining = $size; $fs = [IO.File]::Open('%PAYLOAD_FILE%', [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None); try { while ($remaining -gt 0) { $toWrite = [Math]::Min($remaining, $buffer.Length); $fs.Write($buffer, 0, $toWrite); $remaining -= $toWrite } } finally { $fs.Close() }"
if errorlevel 1 (
  echo [FAIL] unable to generate payload file
  set "FAIL=1"
  exit /b 0
)

for %%F in ("%PAYLOAD_FILE%") do set "PAYLOAD_SIZE=%%~zF"
if not defined PAYLOAD_SIZE (
  echo [FAIL] unable to determine payload size
  set "FAIL=1"
  exit /b 0
)
echo [CHECK] payload size !PAYLOAD_SIZE! bytes

echo [CHECK] request details: POST %BASE_URL%%UPLOAD_PATH% (baseline)
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%UPLOAD_PATH%' -Method Post -InFile '%PAYLOAD_FILE%' -ContentType 'application/octet-stream' -TimeoutSec 60; [IO.File]::WriteAllText('%UPLOAD_STATUS_FILE%', [string]$r.StatusCode, [Text.Encoding]::ASCII); [IO.File]::WriteAllText('%UPLOAD_BODY_FILE%', $r.Content, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] baseline upload request failed
  set "FAIL=1"
  exit /b 0
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
  exit /b 0
)

call :extract_token "%UPLOAD_BODY_FILE%" "%UPLOAD_TOKEN_FILE%"
if "%FAIL%"=="1" exit /b 0
set /p TOKEN_MAIN=<"%UPLOAD_TOKEN_FILE%"
if not defined TOKEN_MAIN (
  echo [FAIL] upload token missing
  set "FAIL=1"
  exit /b 0
)
echo [PASS] upload token present
echo [CHECK] upload token !TOKEN_MAIN!

echo [CHECK] request details: GET %BASE_URL%%INSPECT_PATH%/!TOKEN_MAIN!
call :request_get_text "%BASE_URL%%INSPECT_PATH%/!TOKEN_MAIN!" "%INSPECT_STATUS_FILE%" "%INSPECT_BODY_FILE%"
if "%FAIL%"=="1" exit /b 0

set /p INSPECT_STATUS=<"%INSPECT_STATUS_FILE%"
set /p INSPECT_BODY=<"%INSPECT_BODY_FILE%"
set "INSPECT_BODY_PREVIEW=!INSPECT_BODY!"
if not "!INSPECT_BODY:~200!"=="" set "INSPECT_BODY_PREVIEW=!INSPECT_BODY:~0,200!... (truncated)"
echo [CHECK] response status !INSPECT_STATUS!
echo [CHECK] response body !INSPECT_BODY_PREVIEW!

if "!INSPECT_STATUS!"=="200" (
  echo [PASS] inspect status 200
) else (
  echo [FAIL] expected inspect status 200 but got !INSPECT_STATUS!
  set "FAIL=1"
  exit /b 0
)

call :parse_inspect "%INSPECT_BODY_FILE%"
if "%FAIL%"=="1" exit /b 0

set "EXPECTED_BYTE_SIZE=!PAYLOAD_SIZE!"
set "EXPECTED_CONTENT_TYPE=application/octet-stream"
call :assert_inspect_common
if "%FAIL%"=="1" exit /b 0
if "%PARCEL_STRIP_IMAGE_METADATA%"=="0" (
  call :assert_sanitize_disabled
  if "%FAIL%"=="1" exit /b 0
) else (
  call :assert_sanitize_unsupported_type
  if "%FAIL%"=="1" exit /b 0
)

echo [CHECK] request details: GET %BASE_URL%%DOWNLOAD_PATH%/!TOKEN_MAIN! (baseline)
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; try { $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%DOWNLOAD_PATH%/!TOKEN_MAIN!' -Method Get -OutFile '%DOWNLOAD_FILE%' -TimeoutSec 60 -PassThru; $status = [int]$r.StatusCode } catch { if ($_.Exception.Response) { $resp = $_.Exception.Response; $status = [int]$resp.StatusCode } else { throw } }; [IO.File]::WriteAllText('%DOWNLOAD_STATUS_FILE%', [string]$status, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] download request failed
  set "FAIL=1"
  exit /b 0
)

set /p DOWNLOAD_STATUS=<"%DOWNLOAD_STATUS_FILE%"
echo [CHECK] response status !DOWNLOAD_STATUS!
if "!DOWNLOAD_STATUS!"=="200" (
  echo [PASS] download status 200
) else (
  echo [FAIL] expected download status 200 but got !DOWNLOAD_STATUS!
  set "FAIL=1"
  exit /b 0
)

for %%F in ("%DOWNLOAD_FILE%") do set "DOWNLOAD_SIZE=%%~zF"
echo [CHECK] source size !PAYLOAD_SIZE! bytes
echo [CHECK] download size !DOWNLOAD_SIZE! bytes

if "!PAYLOAD_SIZE!"=="!DOWNLOAD_SIZE!" (
  fc /b "%PAYLOAD_FILE%" "%DOWNLOAD_FILE%" >nul
  if errorlevel 1 (
    echo [FAIL] payload integrity check failed
    set "FAIL=1"
    exit /b 0
  ) else (
    echo [PASS] payload integrity verified
  )
) else (
  echo [FAIL] download size does not match upload size
  set "FAIL=1"
  exit /b 0
)

exit /b 0

:phase_sanitize
echo [CHECK] phase: sanitization (PARCEL_STRIP_IMAGE_METADATA=%PARCEL_STRIP_IMAGE_METADATA%)

set "PNG_FILE=%TEMP_DIR%\fixture.png"
set "UPLOAD_STATUS_FILE=%TEMP_DIR%\upload_png_off_status.txt"
set "UPLOAD_BODY_FILE=%TEMP_DIR%\upload_png_off_body.txt"
set "UPLOAD_TOKEN_FILE=%TEMP_DIR%\upload_png_off_token.txt"
set "INSPECT_STATUS_FILE=%TEMP_DIR%\inspect_png_off_status.txt"
set "INSPECT_BODY_FILE=%TEMP_DIR%\inspect_png_off_body.txt"
set "INSPECT_PARSED_FILE=%TEMP_DIR%\inspect_png_off_parsed.txt"

echo [CHECK] generating PNG fixture %PNG_FILE%
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $b64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBAp8G0sQAAAAASUVORK5CYII='; [IO.File]::WriteAllBytes('%PNG_FILE%', [Convert]::FromBase64String($b64))"
if errorlevel 1 (
  echo [FAIL] unable to generate PNG fixture
  set "FAIL=1"
  exit /b 0
)

for %%F in ("%PNG_FILE%") do set "PNG_SIZE=%%~zF"
if not defined PNG_SIZE (
  echo [FAIL] unable to determine PNG size
  set "FAIL=1"
  exit /b 0
)
echo [CHECK] PNG fixture size !PNG_SIZE! bytes

if %MAX_UPLOAD_SIZE% GTR 0 if !PNG_SIZE! GTR %MAX_UPLOAD_SIZE% (
  echo [FAIL] MAX_UPLOAD_SIZE is too small for PNG fixture
  set "FAIL=1"
  exit /b 0
)

echo [CHECK] request details: POST %BASE_URL%%UPLOAD_PATH% (png fixture)
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%BASE_URL%%UPLOAD_PATH%' -Method Post -InFile '%PNG_FILE%' -ContentType 'image/png' -TimeoutSec 60; [IO.File]::WriteAllText('%UPLOAD_STATUS_FILE%', [string]$r.StatusCode, [Text.Encoding]::ASCII); [IO.File]::WriteAllText('%UPLOAD_BODY_FILE%', $r.Content, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] png upload request failed
  set "FAIL=1"
  exit /b 0
)

set /p UPLOAD_STATUS=<"%UPLOAD_STATUS_FILE%"
set /p UPLOAD_BODY=<"%UPLOAD_BODY_FILE%"
set "UPLOAD_BODY_PREVIEW=!UPLOAD_BODY!"
if not "!UPLOAD_BODY:~200!"=="" set "UPLOAD_BODY_PREVIEW=!UPLOAD_BODY:~0,200!... (truncated)"
echo [CHECK] response status !UPLOAD_STATUS!
echo [CHECK] response body !UPLOAD_BODY_PREVIEW!

if "!UPLOAD_STATUS!"=="201" (
  echo [PASS] upload png status 201
) else (
  echo [FAIL] expected upload png status 201 but got !UPLOAD_STATUS!
  set "FAIL=1"
  exit /b 0
)

call :extract_token "%UPLOAD_BODY_FILE%" "%UPLOAD_TOKEN_FILE%"
if "%FAIL%"=="1" exit /b 0
set /p TOKEN_PNG_OFF=<"%UPLOAD_TOKEN_FILE%"
if not defined TOKEN_PNG_OFF (
  echo [FAIL] upload png token missing
  set "FAIL=1"
  exit /b 0
)
echo [PASS] upload png token present
echo [CHECK] upload png token !TOKEN_PNG_OFF!

echo [CHECK] request details: GET %BASE_URL%%INSPECT_PATH%/!TOKEN_PNG_OFF!
call :request_get_text "%BASE_URL%%INSPECT_PATH%/!TOKEN_PNG_OFF!" "%INSPECT_STATUS_FILE%" "%INSPECT_BODY_FILE%"
if "%FAIL%"=="1" exit /b 0

set /p INSPECT_STATUS=<"%INSPECT_STATUS_FILE%"
set /p INSPECT_BODY=<"%INSPECT_BODY_FILE%"
set "INSPECT_BODY_PREVIEW=!INSPECT_BODY!"
if not "!INSPECT_BODY:~200!"=="" set "INSPECT_BODY_PREVIEW=!INSPECT_BODY:~0,200!... (truncated)"
echo [CHECK] response status !INSPECT_STATUS!
echo [CHECK] response body !INSPECT_BODY_PREVIEW!

if "!INSPECT_STATUS!"=="200" (
  echo [PASS] inspect png status 200
) else (
  echo [FAIL] expected inspect png status 200 but got !INSPECT_STATUS!
  set "FAIL=1"
  exit /b 0
)

call :parse_inspect "%INSPECT_BODY_FILE%"
if "%FAIL%"=="1" exit /b 0

set "EXPECTED_CONTENT_TYPE=image/png"
if "%PARCEL_STRIP_IMAGE_METADATA%"=="0" (
  set "EXPECTED_BYTE_SIZE=!PNG_SIZE!"
) else (
  set "EXPECTED_BYTE_SIZE="
)
call :assert_inspect_common
if "%FAIL%"=="1" exit /b 0
if "%PARCEL_STRIP_IMAGE_METADATA%"=="0" (
  call :assert_sanitize_disabled
  if "%FAIL%"=="1" exit /b 0
) else (
  call :assert_sanitize_on
  if "%FAIL%"=="1" exit /b 0
)

exit /b 0

:compute_payload_size
set /a PAYLOAD_MAIN_BYTES=1048576
if %MAX_UPLOAD_SIZE% GTR 0 (
  set /a SAFE_LIMIT=%MAX_UPLOAD_SIZE%-1024
  if !SAFE_LIMIT! LSS 1024 set /a SAFE_LIMIT=%MAX_UPLOAD_SIZE%
  if !SAFE_LIMIT! LSS 1 set /a SAFE_LIMIT=1
  if !SAFE_LIMIT! LSS !PAYLOAD_MAIN_BYTES! set /a PAYLOAD_MAIN_BYTES=!SAFE_LIMIT!
)
echo [CHECK] payload target size !PAYLOAD_MAIN_BYTES! bytes
exit /b 0

:request_get_text
set "REQ_URL=%~1"
set "REQ_STATUS_FILE=%~2"
set "REQ_BODY_FILE=%~3"
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $r = Invoke-WebRequest -UseBasicParsing -Uri '%REQ_URL%' -Method Get -TimeoutSec 30; [IO.File]::WriteAllText('%REQ_STATUS_FILE%', [string]$r.StatusCode, [Text.Encoding]::ASCII); [IO.File]::WriteAllText('%REQ_BODY_FILE%', $r.Content, [Text.Encoding]::ASCII)"
if errorlevel 1 (
  echo [FAIL] request failed: %REQ_URL%
  set "FAIL=1"
)
exit /b 0

:extract_token
set "BODY_FILE=%~1"
set "TOKEN_FILE=%~2"
if exist "%TOKEN_FILE%" del /f /q "%TOKEN_FILE%" >nul 2>nul
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $json = Get-Content -Raw -LiteralPath '%BODY_FILE%'; $obj = ConvertFrom-Json -InputObject $json; $token = $obj.token; if (-not $token) { $token = '' }; $token" > "%TOKEN_FILE%"
if errorlevel 1 (
  echo [FAIL] failed to parse upload token
  set "FAIL=1"
)
if not exist "%TOKEN_FILE%" (
  echo [FAIL] token output missing at %TOKEN_FILE%
  set "FAIL=1"
)
exit /b 0

:parse_inspect
set "BODY_FILE=%~1"
set "INSPECT_MISSING_COUNT="
set "INSPECT_MISSING_NAMES="
set "INSPECT_HAS_STORAGE_ID="
set "INSPECT_HAS_TOKEN="
set "INSPECT_HAS_PATH="
set "INSPECT_CREATED_AT="
set "INSPECT_BYTE_SIZE="
set "INSPECT_CONTENT_TYPE="
set "INSPECT_UPLOAD_COMPLETE="
set "INSPECT_SANITIZED="
set "INSPECT_SANITIZE_REASON="
set "INSPECT_SANITIZE_ERROR="

for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; $json = Get-Content -Raw -LiteralPath '%BODY_FILE%'; $obj = ConvertFrom-Json -InputObject $json; $props = $obj.PSObject.Properties.Name; $required = @('created_at','byte_size','content_type','upload_complete','sanitized','sanitize_reason','sanitize_error'); $missing = @($required | Where-Object { $props -notcontains $_ }); $out = @(); $out += 'INSPECT_MISSING_COUNT=' + $missing.Count; $out += 'INSPECT_MISSING_NAMES=' + ($missing -join ','); $out += 'INSPECT_HAS_STORAGE_ID=' + ($props -contains 'storage_id'); $out += 'INSPECT_HAS_TOKEN=' + ($props -contains 'token'); $out += 'INSPECT_HAS_PATH=' + ($props -contains 'path'); $out += 'INSPECT_CREATED_AT=' + $obj.created_at; $out += 'INSPECT_BYTE_SIZE=' + $obj.byte_size; $out += 'INSPECT_CONTENT_TYPE=' + $obj.content_type; $out += 'INSPECT_UPLOAD_COMPLETE=' + $obj.upload_complete; $out += 'INSPECT_SANITIZED=' + $obj.sanitized; $out += 'INSPECT_SANITIZE_REASON=' + $obj.sanitize_reason; $out += 'INSPECT_SANITIZE_ERROR=' + $obj.sanitize_error; $out"`) do (
  set "%%A"
)
exit /b 0

:assert_inspect_common
if not "%INSPECT_MISSING_COUNT%"=="0" (
  echo [FAIL] inspect response missing keys: %INSPECT_MISSING_NAMES%
  set "FAIL=1"
  exit /b 0
)

if /i "%INSPECT_HAS_STORAGE_ID%"=="True" (
  echo [FAIL] inspect response includes storage_id
  set "FAIL=1"
  exit /b 0
)

if /i "%INSPECT_HAS_TOKEN%"=="True" (
  echo [FAIL] inspect response echoes token
  set "FAIL=1"
  exit /b 0
)

if /i "%INSPECT_HAS_PATH%"=="True" (
  echo [FAIL] inspect response exposes internal path
  set "FAIL=1"
  exit /b 0
)

if /i not "%INSPECT_UPLOAD_COMPLETE%"=="True" (
  echo [FAIL] inspect upload_complete is not true
  set "FAIL=1"
  exit /b 0
)

echo %INSPECT_BYTE_SIZE%| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
  echo [FAIL] inspect byte_size is not numeric
  set "FAIL=1"
  exit /b 0
)

if defined EXPECTED_BYTE_SIZE if not "%INSPECT_BYTE_SIZE%"=="%EXPECTED_BYTE_SIZE%" (
  echo [FAIL] inspect byte_size %INSPECT_BYTE_SIZE% does not match expected %EXPECTED_BYTE_SIZE%
  set "FAIL=1"
  exit /b 0
)

if defined EXPECTED_CONTENT_TYPE if not "%INSPECT_CONTENT_TYPE%"=="%EXPECTED_CONTENT_TYPE%" (
  echo [FAIL] inspect content_type "%INSPECT_CONTENT_TYPE%" does not match expected "%EXPECTED_CONTENT_TYPE%"
  set "FAIL=1"
  exit /b 0
)

echo [PASS] inspect includes required keys and safe fields only
exit /b 0

:assert_sanitize_disabled
if /i not "%INSPECT_SANITIZED%"=="False" (
  echo [FAIL] expected sanitized=false but got %INSPECT_SANITIZED%
  set "FAIL=1"
  exit /b 0
)

if not "%INSPECT_SANITIZE_REASON%"=="disabled" (
  echo [FAIL] expected sanitize_reason=disabled but got %INSPECT_SANITIZE_REASON%
  set "FAIL=1"
  exit /b 0
)

if defined INSPECT_SANITIZE_ERROR if not "%INSPECT_SANITIZE_ERROR%"=="" (
  echo [FAIL] expected sanitize_error empty but got %INSPECT_SANITIZE_ERROR%
  set "FAIL=1"
  exit /b 0
)

echo [PASS] sanitize disabled fields verified
exit /b 0

:assert_sanitize_unsupported_type
if /i not "%INSPECT_SANITIZED%"=="False" (
  echo [FAIL] expected sanitized=false but got %INSPECT_SANITIZED%
  set "FAIL=1"
  exit /b 0
)

if not "%INSPECT_SANITIZE_REASON%"=="unsupported_type" (
  echo [FAIL] expected sanitize_reason=unsupported_type but got %INSPECT_SANITIZE_REASON%
  set "FAIL=1"
  exit /b 0
)

if defined INSPECT_SANITIZE_ERROR if not "%INSPECT_SANITIZE_ERROR%"=="" (
  echo [FAIL] expected sanitize_error empty but got %INSPECT_SANITIZE_ERROR%
  set "FAIL=1"
  exit /b 0
)

echo [PASS] sanitize unsupported_type fields verified
exit /b 0

:assert_sanitize_on
if "%INSPECT_SANITIZE_REASON%"=="applied" (
  if /i "%INSPECT_SANITIZED%"=="True" (
    if defined INSPECT_SANITIZE_ERROR if not "%INSPECT_SANITIZE_ERROR%"=="" (
      echo [FAIL] sanitize_error should be empty when applied
      set "FAIL=1"
      exit /b 0
    )
    echo [PASS] sanitize applied fields verified
    exit /b 0
  ) else (
    echo [FAIL] sanitize_reason applied but sanitized is %INSPECT_SANITIZED%
    set "FAIL=1"
    exit /b 0
  )
)

if "%INSPECT_SANITIZE_REASON%"=="failed" (
  if /i "%INSPECT_SANITIZED%"=="False" (
    if not "%INSPECT_SANITIZE_ERROR%"=="sanitize_failed" (
      echo [FAIL] sanitize_error should be sanitize_failed when failed
      set "FAIL=1"
      exit /b 0
    )
    echo [PASS] sanitize failed fields verified
    exit /b 0
  ) else (
    echo [FAIL] sanitize_reason failed but sanitized is %INSPECT_SANITIZED%
    set "FAIL=1"
    exit /b 0
  )
)

echo [FAIL] sanitize_reason must be applied or failed when stripping is on
set "FAIL=1"
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
set "PARCEL_STRIP_IMAGE_METADATA="

for /f "usebackq tokens=1,* delims==" %%A in (`findstr /R /C:"^API_PORT=" "%ENV_FILE%"`) do set "API_PORT=%%B"
for /f "usebackq tokens=1,* delims==" %%A in (`findstr /R /C:"^DATA_DIR=" "%ENV_FILE%"`) do set "DATA_DIR=%%B"
for /f "usebackq tokens=1,* delims==" %%A in (`findstr /R /C:"^MAX_UPLOAD_SIZE=" "%ENV_FILE%"`) do set "MAX_UPLOAD_SIZE=%%B"
for /f "usebackq tokens=1,* delims==" %%A in (`findstr /R /C:"^PARCEL_STRIP_IMAGE_METADATA=" "%ENV_FILE%"`) do set "PARCEL_STRIP_IMAGE_METADATA=%%B"

set "API_PORT=%API_PORT:"=%"
set "DATA_DIR=%DATA_DIR:"=%"
set "MAX_UPLOAD_SIZE=%MAX_UPLOAD_SIZE:"=%"
set "PARCEL_STRIP_IMAGE_METADATA=%PARCEL_STRIP_IMAGE_METADATA:"=%"

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

if not defined PARCEL_STRIP_IMAGE_METADATA (
  echo [FAIL] PARCEL_STRIP_IMAGE_METADATA not found in %ENV_FILE%
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

if not "%PARCEL_STRIP_IMAGE_METADATA%"=="0" if not "%PARCEL_STRIP_IMAGE_METADATA%"=="1" (
  echo [FAIL] PARCEL_STRIP_IMAGE_METADATA must be 0 or 1
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
