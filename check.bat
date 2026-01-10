@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0"
for %%I in ("%ROOT%.") do set "ROOT=%%~fI"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "LOG_ROOT=%ROOT%\logs\check"
if not exist "%LOG_ROOT%" mkdir "%LOG_ROOT%" >nul 2>&1

set /a ASSERT_TOTAL=0
set /a ASSERT_PASS=0
set /a ASSERT_FAIL=0
set "FAIL=0"

set "CURL_EXE=%SystemRoot%\System32\curl.exe"
if not exist "%CURL_EXE%" set "CURL_EXE=curl"
call :require_cmd "%CURL_EXE%"
if errorlevel 1 goto :cleanup
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=powershell"
call :require_cmd "%PS_EXE%"
if errorlevel 1 goto :cleanup

call :load_env "%ROOT%\.env"
if errorlevel 1 goto :cleanup
call :resolve_paths
if errorlevel 1 goto :cleanup

set "BASE_URL=http://127.0.0.1:%API_PORT%"

set "TEMP_DIR=%LOG_ROOT%\temp-%RANDOM%-%RANDOM%"
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" >nul 2>&1
set "CURL_ERR=%TEMP_DIR%\curl.err"

set "LARGE_SIZE=1048576"
call :resolve_large_size "%MAX_UPLOAD_SIZE%" "%LARGE_SIZE%"
if errorlevel 1 goto :cleanup
echo [CHECK] large payload size %LARGE_SIZE% bytes

echo [CHECK] expecting server already running
call :wait_ready
if errorlevel 1 goto :cleanup

echo [CHECK] phase: health
echo [CHECK] request details: GET %BASE_URL%/health
set "HEALTH_BODY=%TEMP_DIR%\health.body"
set "HEALTH_HEADERS=%TEMP_DIR%\health.headers"
set "HEALTH_STATUS=%TEMP_DIR%\health.status"
call :curl_get "%BASE_URL%/health" "%HEALTH_BODY%" "%HEALTH_HEADERS%" "%HEALTH_STATUS%"
if errorlevel 1 goto :cleanup
call :read_status "%HEALTH_STATUS%" HEALTH_CODE
echo [CHECK] response status %HEALTH_CODE%
call :print_body "%HEALTH_BODY%" "health body"
call :assert_status "health status 200" "%HEALTH_CODE%" "200"
if errorlevel 1 goto :cleanup
call :assert_body_equals "health body ok" "%HEALTH_BODY%" "ok"
if errorlevel 1 goto :cleanup

echo [CHECK] phase: upload large payload
set "PAYLOAD_LARGE=%TEMP_DIR%\payload-large.bin"
call :write_payload "%PAYLOAD_LARGE%" "%LARGE_SIZE%" "PARCEL_STREAM"
if errorlevel 1 goto :cleanup
call :file_size "%PAYLOAD_LARGE%" PAYLOAD_LARGE_SIZE
echo [CHECK] payload size %PAYLOAD_LARGE_SIZE% bytes
echo [CHECK] request details: POST %BASE_URL%/upload (upload 1)

set "UPLOAD1_BODY=%TEMP_DIR%\upload1.body"
set "UPLOAD1_HEADERS=%TEMP_DIR%\upload1.headers"
set "UPLOAD1_STATUS=%TEMP_DIR%\upload1.status"
call :curl_upload "%BASE_URL%/upload" "%PAYLOAD_LARGE%" "payload.bin" "application/octet-stream" "%UPLOAD1_BODY%" "%UPLOAD1_HEADERS%" "%UPLOAD1_STATUS%"
if errorlevel 1 goto :cleanup
call :read_status "%UPLOAD1_STATUS%" UPLOAD1_CODE
echo [CHECK] response status %UPLOAD1_CODE%
call :print_body "%UPLOAD1_BODY%" "upload 1 body"
call :assert_status "upload 1 status 201" "%UPLOAD1_CODE%" "201"
if errorlevel 1 goto :cleanup
call :extract_token "%UPLOAD1_BODY%" UPLOAD1_TOKEN
if errorlevel 1 goto :cleanup
call :assert_nonempty "upload 1 token present" "%UPLOAD1_TOKEN%"
if errorlevel 1 goto :cleanup

echo [CHECK] phase: upload second payload
set "PAYLOAD_SMALL=%TEMP_DIR%\payload-small.bin"
call :write_payload "%PAYLOAD_SMALL%" "512" "PARCEL_SMALL"
if errorlevel 1 goto :cleanup
call :file_size "%PAYLOAD_SMALL%" PAYLOAD_SMALL_SIZE
echo [CHECK] payload size %PAYLOAD_SMALL_SIZE% bytes
echo [CHECK] request details: POST %BASE_URL%/upload (upload 2)

set "UPLOAD2_BODY=%TEMP_DIR%\upload2.body"
set "UPLOAD2_HEADERS=%TEMP_DIR%\upload2.headers"
set "UPLOAD2_STATUS=%TEMP_DIR%\upload2.status"
call :curl_upload "%BASE_URL%/upload" "%PAYLOAD_SMALL%" "sample.bin" "application/octet-stream" "%UPLOAD2_BODY%" "%UPLOAD2_HEADERS%" "%UPLOAD2_STATUS%"
if errorlevel 1 goto :cleanup
call :read_status "%UPLOAD2_STATUS%" UPLOAD2_CODE
echo [CHECK] response status %UPLOAD2_CODE%
call :print_body "%UPLOAD2_BODY%" "upload 2 body"
call :assert_status "upload 2 status 201" "%UPLOAD2_CODE%" "201"
if errorlevel 1 goto :cleanup
call :extract_token "%UPLOAD2_BODY%" UPLOAD2_TOKEN
if errorlevel 1 goto :cleanup
call :assert_nonempty "upload 2 token present" "%UPLOAD2_TOKEN%"
if errorlevel 1 goto :cleanup
call :assert_not_equal "upload tokens are unique" "%UPLOAD1_TOKEN%" "%UPLOAD2_TOKEN%"
if errorlevel 1 goto :cleanup
echo [CHECK] upload tokens: %UPLOAD1_TOKEN% , %UPLOAD2_TOKEN%

echo [CHECK] phase: layout
call :assert_exists "index.jsonl exists" "%INDEX_FILE%"
if errorlevel 1 goto :cleanup
call :assert_dir_exists "uploads dir exists" "%UPLOADS_DIR%"
if errorlevel 1 goto :cleanup
echo [CHECK] data dir entries (names only)
dir /b "%DATA_DIR_ABS%"
call :count_uploads UPLOAD_COUNT
if errorlevel 1 goto :cleanup
call :assert_minimum "uploads dir contains files" "%UPLOAD_COUNT%" "2"
if errorlevel 1 goto :cleanup
call :index_counts INDEX_TOTAL INDEX_UNIQUE
if errorlevel 1 goto :cleanup
echo [CHECK] index tokens %INDEX_TOTAL% total, %INDEX_UNIQUE% unique
call :assert_equal "index contains distinct tokens" "%INDEX_TOTAL%" "%INDEX_UNIQUE%"
if errorlevel 1 goto :cleanup

echo [CHECK] phase: download
echo [CHECK] request details: GET %BASE_URL%/download/%UPLOAD1_TOKEN%
set "DOWNLOAD1=%TEMP_DIR%\download1.bin"
set "DOWNLOAD1_HEADERS=%TEMP_DIR%\download1.headers"
set "DOWNLOAD1_STATUS=%TEMP_DIR%\download1.status"
call :curl_download "%BASE_URL%/download/%UPLOAD1_TOKEN%" "%DOWNLOAD1%" "%DOWNLOAD1_HEADERS%" "%DOWNLOAD1_STATUS%"
if errorlevel 1 goto :cleanup
call :read_status "%DOWNLOAD1_STATUS%" DOWNLOAD1_CODE
echo [CHECK] response status %DOWNLOAD1_CODE%
call :assert_status "download status 200" "%DOWNLOAD1_CODE%" "200"
if errorlevel 1 goto :cleanup
call :file_size "%DOWNLOAD1%" DOWNLOAD1_SIZE
echo [CHECK] download size %DOWNLOAD1_SIZE% bytes
call :assert_equal "download size matches payload" "%DOWNLOAD1_SIZE%" "%PAYLOAD_LARGE_SIZE%"
if errorlevel 1 goto :cleanup
call :assert_files_equal "payload integrity verified" "%PAYLOAD_LARGE%" "%DOWNLOAD1%"
if errorlevel 1 goto :cleanup

echo [CHECK] phase: token reuse
echo [CHECK] request details: GET %BASE_URL%/download/%UPLOAD1_TOKEN% (reuse)
set "DOWNLOAD1B=%TEMP_DIR%\download1b.bin"
set "DOWNLOAD1B_HEADERS=%TEMP_DIR%\download1b.headers"
set "DOWNLOAD1B_STATUS=%TEMP_DIR%\download1b.status"
call :curl_download "%BASE_URL%/download/%UPLOAD1_TOKEN%" "%DOWNLOAD1B%" "%DOWNLOAD1B_HEADERS%" "%DOWNLOAD1B_STATUS%"
if errorlevel 1 goto :cleanup
call :read_status "%DOWNLOAD1B_STATUS%" DOWNLOAD1B_CODE
echo [CHECK] response status %DOWNLOAD1B_CODE%
call :assert_status "download reuse status 200" "%DOWNLOAD1B_CODE%" "200"
if errorlevel 1 goto :cleanup
call :assert_files_equal "payload integrity verified on reuse" "%PAYLOAD_LARGE%" "%DOWNLOAD1B%"
if errorlevel 1 goto :cleanup

echo [CHECK] phase: inspect baseline
echo [CHECK] request details: GET %BASE_URL%/inspect/%UPLOAD1_TOKEN%
set "INSPECT1_BODY=%TEMP_DIR%\inspect1.body"
set "INSPECT1_HEADERS=%TEMP_DIR%\inspect1.headers"
set "INSPECT1_STATUS=%TEMP_DIR%\inspect1.status"
call :curl_get "%BASE_URL%/inspect/%UPLOAD1_TOKEN%" "%INSPECT1_BODY%" "%INSPECT1_HEADERS%" "%INSPECT1_STATUS%"
if errorlevel 1 goto :cleanup
call :read_status "%INSPECT1_STATUS%" INSPECT1_CODE
echo [CHECK] response status %INSPECT1_CODE%
call :print_body "%INSPECT1_BODY%" "inspect body"
call :assert_status "inspect status 200" "%INSPECT1_CODE%" "200"
if errorlevel 1 goto :cleanup
set "EXPECTED_SANITIZE_REASON=disabled"
if "%PARCEL_STRIP_IMAGE_METADATA%"=="1" set "EXPECTED_SANITIZE_REASON=unsupported_type"
call :assert_inspect "%INSPECT1_BODY%" "application/octet-stream" ".bin" "%PAYLOAD_LARGE_SIZE%" "%EXPECTED_SANITIZE_REASON%" "inspect baseline fields"
if errorlevel 1 goto :cleanup

echo [CHECK] phase: sanitize image upload
set "PNG_FILE=%TEMP_DIR%\fixture.png"
call :write_png "%PNG_FILE%"
if errorlevel 1 goto :cleanup
call :file_size "%PNG_FILE%" PNG_SIZE
echo [CHECK] png payload size %PNG_SIZE% bytes
echo [CHECK] request details: POST %BASE_URL%/upload (png)

set "UPLOAD_PNG_BODY=%TEMP_DIR%\upload-png.body"
set "UPLOAD_PNG_HEADERS=%TEMP_DIR%\upload-png.headers"
set "UPLOAD_PNG_STATUS=%TEMP_DIR%\upload-png.status"
call :curl_upload "%BASE_URL%/upload" "%PNG_FILE%" "fixture.png" "image/png" "%UPLOAD_PNG_BODY%" "%UPLOAD_PNG_HEADERS%" "%UPLOAD_PNG_STATUS%"
if errorlevel 1 goto :cleanup
call :read_status "%UPLOAD_PNG_STATUS%" UPLOAD_PNG_CODE
echo [CHECK] response status %UPLOAD_PNG_CODE%
call :print_body "%UPLOAD_PNG_BODY%" "upload png body"
call :assert_status "upload png status 201" "%UPLOAD_PNG_CODE%" "201"
if errorlevel 1 goto :cleanup
call :extract_token "%UPLOAD_PNG_BODY%" UPLOAD_PNG_TOKEN
if errorlevel 1 goto :cleanup
call :assert_nonempty "upload png token present" "%UPLOAD_PNG_TOKEN%"
if errorlevel 1 goto :cleanup

echo [CHECK] request details: GET %BASE_URL%/download/%UPLOAD_PNG_TOKEN% (png)
set "DOWNLOAD_PNG=%TEMP_DIR%\download-png.bin"
set "DOWNLOAD_PNG_HEADERS=%TEMP_DIR%\download-png.headers"
set "DOWNLOAD_PNG_STATUS=%TEMP_DIR%\download-png.status"
call :curl_download "%BASE_URL%/download/%UPLOAD_PNG_TOKEN%" "%DOWNLOAD_PNG%" "%DOWNLOAD_PNG_HEADERS%" "%DOWNLOAD_PNG_STATUS%"
if errorlevel 1 goto :cleanup
call :read_status "%DOWNLOAD_PNG_STATUS%" DOWNLOAD_PNG_CODE
echo [CHECK] response status %DOWNLOAD_PNG_CODE%
call :assert_status "download png status 200" "%DOWNLOAD_PNG_CODE%" "200"
if errorlevel 1 goto :cleanup
call :file_size "%DOWNLOAD_PNG%" PNG_STORED_SIZE

echo [CHECK] request details: GET %BASE_URL%/inspect/%UPLOAD_PNG_TOKEN%
set "INSPECT_PNG_BODY=%TEMP_DIR%\inspect-png.body"
set "INSPECT_PNG_HEADERS=%TEMP_DIR%\inspect-png.headers"
set "INSPECT_PNG_STATUS=%TEMP_DIR%\inspect-png.status"
call :curl_get "%BASE_URL%/inspect/%UPLOAD_PNG_TOKEN%" "%INSPECT_PNG_BODY%" "%INSPECT_PNG_HEADERS%" "%INSPECT_PNG_STATUS%"
if errorlevel 1 goto :cleanup
call :read_status "%INSPECT_PNG_STATUS%" INSPECT_PNG_CODE
echo [CHECK] response status %INSPECT_PNG_CODE%
call :print_body "%INSPECT_PNG_BODY%" "inspect png body"
call :assert_status "inspect png status 200" "%INSPECT_PNG_CODE%" "200"
if errorlevel 1 goto :cleanup
set "PNG_SANITIZE_EXPECT=disabled"
if "%PARCEL_STRIP_IMAGE_METADATA%"=="1" set "PNG_SANITIZE_EXPECT=applied_or_failed"
call :assert_inspect "%INSPECT_PNG_BODY%" "image/png" ".png" "%PNG_STORED_SIZE%" "%PNG_SANITIZE_EXPECT%" "inspect png fields"
if errorlevel 1 goto :cleanup

echo [CHECK] phase: upload too large
if "%MAX_UPLOAD_SIZE%"=="0" (
  echo [CHECK] skipping upload too large test (MAX_UPLOAD_SIZE=0)
) else (
  call :count_index INDEX_BEFORE_TOO_LARGE
  call :count_uploads UPLOADS_BEFORE_TOO_LARGE
  if errorlevel 1 goto :cleanup

  set /a TOO_LARGE_SIZE=%MAX_UPLOAD_SIZE%+1024
  set "PAYLOAD_TOO_LARGE=%TEMP_DIR%\payload-too-large.bin"
  call :write_payload "%PAYLOAD_TOO_LARGE%" "%TOO_LARGE_SIZE%" "LIMIT_FAIL"
  if errorlevel 1 goto :cleanup
  call :file_size "%PAYLOAD_TOO_LARGE%" TOO_LARGE_SIZE
  echo [CHECK] payload size %TOO_LARGE_SIZE% bytes
  echo [CHECK] request details: POST %BASE_URL%/upload (too large)

  set "UPLOAD_TOO_LARGE_BODY=%TEMP_DIR%\upload-too-large.body"
  set "UPLOAD_TOO_LARGE_HEADERS=%TEMP_DIR%\upload-too-large.headers"
  set "UPLOAD_TOO_LARGE_STATUS=%TEMP_DIR%\upload-too-large.status"
  call :curl_upload "%BASE_URL%/upload" "%PAYLOAD_TOO_LARGE%" "too-large.bin" "application/octet-stream" "%UPLOAD_TOO_LARGE_BODY%" "%UPLOAD_TOO_LARGE_HEADERS%" "%UPLOAD_TOO_LARGE_STATUS%"
  if errorlevel 1 goto :cleanup
  call :read_status "%UPLOAD_TOO_LARGE_STATUS%" UPLOAD_TOO_LARGE_CODE
  echo [CHECK] response status %UPLOAD_TOO_LARGE_CODE%
  call :print_body "%UPLOAD_TOO_LARGE_BODY%" "upload too large body"
  call :assert_error_response "upload too large" "%UPLOAD_TOO_LARGE_CODE%" "413" "%UPLOAD_TOO_LARGE_BODY%" "%UPLOAD_TOO_LARGE_HEADERS%" "payload_too_large"
  if errorlevel 1 goto :cleanup

  call :count_index INDEX_AFTER_TOO_LARGE
  call :count_uploads UPLOADS_AFTER_TOO_LARGE
  call :assert_equal "index not appended on 413" "%INDEX_AFTER_TOO_LARGE%" "%INDEX_BEFORE_TOO_LARGE%"
  if errorlevel 1 goto :cleanup
  call :assert_equal "no partial upload files on 413" "%UPLOADS_AFTER_TOO_LARGE%" "%UPLOADS_BEFORE_TOO_LARGE%"
  if errorlevel 1 goto :cleanup
)

echo [CHECK] phase: malformed upload
echo [CHECK] request details: POST %BASE_URL%/upload (bad request)
set "UPLOAD_BAD_BODY=%TEMP_DIR%\upload-bad.body"
set "UPLOAD_BAD_HEADERS=%TEMP_DIR%\upload-bad.headers"
set "UPLOAD_BAD_STATUS=%TEMP_DIR%\upload-bad.status"
call :curl_post_raw "%BASE_URL%/upload" "%UPLOAD_BAD_BODY%" "%UPLOAD_BAD_HEADERS%" "%UPLOAD_BAD_STATUS%"
if errorlevel 1 goto :cleanup
call :read_status "%UPLOAD_BAD_STATUS%" UPLOAD_BAD_CODE
echo [CHECK] response status %UPLOAD_BAD_CODE%
call :print_body "%UPLOAD_BAD_BODY%" "upload bad body"
call :assert_error_response "upload bad request" "%UPLOAD_BAD_CODE%" "400" "%UPLOAD_BAD_BODY%" "%UPLOAD_BAD_HEADERS%" "bad_request"
if errorlevel 1 goto :cleanup

echo [CHECK] phase: download unknown token
echo [CHECK] request details: GET %BASE_URL%/download/this_token_should_not_exist_123
set "DOWNLOAD_UNKNOWN_BODY=%TEMP_DIR%\download-unknown.body"
set "DOWNLOAD_UNKNOWN_HEADERS=%TEMP_DIR%\download-unknown.headers"
set "DOWNLOAD_UNKNOWN_STATUS=%TEMP_DIR%\download-unknown.status"
call :curl_get "%BASE_URL%/download/this_token_should_not_exist_123" "%DOWNLOAD_UNKNOWN_BODY%" "%DOWNLOAD_UNKNOWN_HEADERS%" "%DOWNLOAD_UNKNOWN_STATUS%"
if errorlevel 1 goto :cleanup
call :read_status "%DOWNLOAD_UNKNOWN_STATUS%" DOWNLOAD_UNKNOWN_CODE
echo [CHECK] response status %DOWNLOAD_UNKNOWN_CODE%
call :print_body "%DOWNLOAD_UNKNOWN_BODY%" "download unknown body"
call :assert_error_response "download unknown token" "%DOWNLOAD_UNKNOWN_CODE%" "404" "%DOWNLOAD_UNKNOWN_BODY%" "%DOWNLOAD_UNKNOWN_HEADERS%" "not_found"
if errorlevel 1 goto :cleanup

echo [CHECK] phase: inspect unknown token
echo [CHECK] request details: GET %BASE_URL%/inspect/this_token_should_not_exist_123
set "INSPECT_UNKNOWN_BODY=%TEMP_DIR%\inspect-unknown.body"
set "INSPECT_UNKNOWN_HEADERS=%TEMP_DIR%\inspect-unknown.headers"
set "INSPECT_UNKNOWN_STATUS=%TEMP_DIR%\inspect-unknown.status"
call :curl_get "%BASE_URL%/inspect/this_token_should_not_exist_123" "%INSPECT_UNKNOWN_BODY%" "%INSPECT_UNKNOWN_HEADERS%" "%INSPECT_UNKNOWN_STATUS%"
if errorlevel 1 goto :cleanup
call :read_status "%INSPECT_UNKNOWN_STATUS%" INSPECT_UNKNOWN_CODE
echo [CHECK] response status %INSPECT_UNKNOWN_CODE%
call :print_body "%INSPECT_UNKNOWN_BODY%" "inspect unknown body"
call :assert_error_response "inspect unknown token" "%INSPECT_UNKNOWN_CODE%" "404" "%INSPECT_UNKNOWN_BODY%" "%INSPECT_UNKNOWN_HEADERS%" "not_found"
if errorlevel 1 goto :cleanup

goto :cleanup

:cleanup
if defined TEMP_DIR if exist "%TEMP_DIR%" (
  echo [CLEANUP] removing temp files
  rmdir /s /q "%TEMP_DIR%" >nul 2>&1
)
echo [SUMMARY] assertions total=%ASSERT_TOTAL% pass=%ASSERT_PASS% fail=%ASSERT_FAIL%
if %ASSERT_FAIL% GTR 0 exit /b 1
if "%FAIL%"=="1" exit /b 1
exit /b 0

:require_cmd
if exist "%~1" exit /b 0
where /q "%~1"
if errorlevel 1 (
  echo [FAIL] required command not found: %~1
  set "FAIL=1"
  set /a ASSERT_FAIL+=1
  set /a ASSERT_TOTAL+=1
  exit /b 1
)
exit /b 0

:load_env
set "ENV_FILE=%~1"
if not exist "%ENV_FILE%" (
  echo [FAIL] .env not found at %ENV_FILE%
  set "FAIL=1"
  set /a ASSERT_FAIL+=1
  set /a ASSERT_TOTAL+=1
  exit /b 1
)
for /f "usebackq tokens=1* delims==" %%A in ("%ENV_FILE%") do (
  set "KEY=%%~A"
  set "VAL=%%~B"
  if defined KEY if not "!KEY!"=="" if not "!KEY:~0,1!"=="#" (
    set "!KEY!=!VAL!"
  )
)
if not defined API_PORT (
  echo [FAIL] API_PORT missing from .env
  set "FAIL=1"
  exit /b 1
)
if not defined DATA_DIR (
  echo [FAIL] DATA_DIR missing from .env
  set "FAIL=1"
  exit /b 1
)
if not defined MAX_UPLOAD_SIZE (
  echo [FAIL] MAX_UPLOAD_SIZE missing from .env
  set "FAIL=1"
  exit /b 1
)
if not defined PARCEL_STRIP_IMAGE_METADATA (
  echo [FAIL] PARCEL_STRIP_IMAGE_METADATA missing from .env
  set "FAIL=1"
  exit /b 1
)
exit /b 0

:resolve_paths
set "DATA_DIR_ABS=%DATA_DIR%"
if not "%DATA_DIR:~1,1%"==":" if not "%DATA_DIR:~0,2%"=="\\" (
  set "DATA_DIR_ABS=%ROOT%\%DATA_DIR%"
)
for %%I in ("%DATA_DIR_ABS%") do set "DATA_DIR_ABS=%%~fI"
set "UPLOADS_DIR=%DATA_DIR_ABS%\uploads"
set "INDEX_FILE=%DATA_DIR_ABS%\index.jsonl"
echo [CHECK] using port %API_PORT% (from %ROOT%\.env)
echo [CHECK] data dir %DATA_DIR_ABS%
echo [CHECK] uploads dir %UPLOADS_DIR%
echo [CHECK] index file %INDEX_FILE%
echo [CHECK] MAX_UPLOAD_SIZE=%MAX_UPLOAD_SIZE%
echo [CHECK] PARCEL_STRIP_IMAGE_METADATA=%PARCEL_STRIP_IMAGE_METADATA%
exit /b 0

:resolve_large_size
set "RAW_MAX=%~1"
set "TARGET_SIZE=%~2"
echo %RAW_MAX%| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
  echo [FAIL] MAX_UPLOAD_SIZE must be a non-negative number
  set "FAIL=1"
  exit /b 1
)
if "%RAW_MAX%"=="0" (
  set "LARGE_SIZE=%TARGET_SIZE%"
  exit /b 0
)
set /a MAX_NUM=%RAW_MAX%
set /a TARGET_NUM=%TARGET_SIZE%
if %MAX_NUM% LSS %TARGET_NUM% (
  echo [CHECK] MAX_UPLOAD_SIZE is %MAX_NUM%; adjusting large payload to %MAX_NUM% bytes
  set "LARGE_SIZE=%MAX_NUM%"
  exit /b 0
)
set "LARGE_SIZE=%TARGET_NUM%"
exit /b 0

:wait_ready
echo [CHECK] waiting for readiness
set "READY_URL=%BASE_URL%/health"
echo [CHECK] readiness url %READY_URL%
set "READY=0"
for /l %%I in (1,1,30) do (
  echo [CHECK] readiness attempt %%I/30
  set "READY_BODY=%TEMP_DIR%\ready.body"
  set "READY_HEADERS=%TEMP_DIR%\ready.headers"
  set "READY_STATUS=%TEMP_DIR%\ready.status"
  call :curl_get_soft "!READY_URL!" "!READY_BODY!" "!READY_HEADERS!" "!READY_STATUS!"
  if not errorlevel 1 (
    call :read_status "!READY_STATUS!" READY_CODE
    echo [CHECK] readiness status !READY_CODE!
    if "!READY_CODE!"=="200" (
      for /f "usebackq delims=" %%B in (`%PS_EXE% -NoProfile -Command "(Get-Content -Raw '!READY_BODY!').Trim()"`) do set "READY_TEXT=%%B"
      if "!READY_TEXT!"=="ok" (
        set "READY=1"
        goto :ready_done
      )
    )
  ) else (
    echo [CHECK] readiness request failed
    if exist "%CURL_ERR%" type "%CURL_ERR%"
  )
  %PS_EXE% -NoProfile -Command "Start-Sleep -Seconds 1" >nul 2>&1
)
:ready_done
if "%READY%"=="1" exit /b 0
echo [FAIL] server did not become ready
set "FAIL=1"
exit /b 1

:curl_get
set "URL=%~1"
set "BODY=%~2"
set "HEADERS=%~3"
set "STATUS=%~4"
"%CURL_EXE%" -s -S --noproxy 127.0.0.1 --connect-timeout 2 --max-time 10 -D "%HEADERS%" -o "%BODY%" -w "%%{http_code}" "%URL%" > "%STATUS%" 2> "%CURL_ERR%"
if errorlevel 1 (
  echo [FAIL] request failed: %URL%
  set "FAIL=1"
  exit /b 1
)
exit /b 0

:curl_get_soft
set "URL=%~1"
set "BODY=%~2"
set "HEADERS=%~3"
set "STATUS=%~4"
if "%URL%"=="" (
  echo [FAIL] readiness URL missing
  exit /b 1
)
echo [CHECK] readiness curl url %URL%
"%CURL_EXE%" -s -S --noproxy 127.0.0.1 --connect-timeout 2 --max-time 2 -D "%HEADERS%" -o "%BODY%" -w "%%{http_code}" "%URL%" > "%STATUS%" 2> "%CURL_ERR%"
if errorlevel 1 exit /b 1
exit /b 0

:curl_download
set "URL=%~1"
set "OUT_FILE=%~2"
set "HEADERS=%~3"
set "STATUS=%~4"
"%CURL_EXE%" -s -S --noproxy 127.0.0.1 -D "%HEADERS%" -o "%OUT_FILE%" -w "%%{http_code}" "%URL%" > "%STATUS%" 2> "%CURL_ERR%"
if errorlevel 1 (
  echo [FAIL] download failed: %URL%
  set "FAIL=1"
  exit /b 1
)
exit /b 0

:curl_upload
set "URL=%~1"
set "UPLOAD_FILE=%~2"
set "UPLOAD_NAME=%~3"
set "UPLOAD_TYPE=%~4"
set "BODY=%~5"
set "HEADERS=%~6"
set "STATUS=%~7"
"%CURL_EXE%" -s -S --noproxy 127.0.0.1 -D "%HEADERS%" -o "%BODY%" -w "%%{http_code}" -F "file=@%UPLOAD_FILE%;filename=%UPLOAD_NAME%;type=%UPLOAD_TYPE%" "%URL%" > "%STATUS%" 2> "%CURL_ERR%"
if errorlevel 1 (
  echo [FAIL] upload failed: %URL%
  set "FAIL=1"
  exit /b 1
)
exit /b 0

:curl_post_raw
set "URL=%~1"
set "BODY=%~2"
set "HEADERS=%~3"
set "STATUS=%~4"
"%CURL_EXE%" -s -S --noproxy 127.0.0.1 -D "%HEADERS%" -o "%BODY%" -w "%%{http_code}" -H "Content-Type: text/plain" --data "bad" "%URL%" > "%STATUS%" 2> "%CURL_ERR%"
if errorlevel 1 (
  echo [FAIL] request failed: %URL%
  set "FAIL=1"
  exit /b 1
)
exit /b 0

:read_status
set "STATUS_FILE=%~1"
set "OUT_VAR=%~2"
set "%OUT_VAR%="
for /f "usebackq delims=" %%S in ("%STATUS_FILE%") do set "%OUT_VAR%=%%S"
exit /b 0

:print_body
set "BODY_FILE=%~1"
set "LABEL=%~2"
for /f "usebackq delims=" %%B in (`%PS_EXE% -NoProfile -Command "$text = Get-Content -Raw '%BODY_FILE%'; if ($text.Length -gt 200) { $text.Substring(0,200) + '... (truncated)' } else { $text }"`) do (
  echo [CHECK] %LABEL% %%B
)
exit /b 0

:file_size
set "FILE_PATH=%~1"
set "OUT_VAR=%~2"
for %%A in ("%FILE_PATH%") do set "%OUT_VAR%=%%~zA"
exit /b 0

:write_payload
set "FILE_PATH=%~1"
set "SIZE=%~2"
set "PATTERN=%~3"
%PS_EXE% -NoProfile -Command "$pattern = [System.Text.Encoding]::ASCII.GetBytes('%PATTERN%'); $size = %SIZE%; $stream = [System.IO.File]::Open('%FILE_PATH%', [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write); try { $written = 0; while ($written -lt $size) { $remaining = $size - $written; if ($remaining -lt $pattern.Length) { $stream.Write($pattern, 0, $remaining); $written += $remaining; } else { $stream.Write($pattern, 0, $pattern.Length); $written += $pattern.Length; } } } finally { $stream.Close() }"
if errorlevel 1 (
  echo [FAIL] failed to generate payload %FILE_PATH%
  set "FAIL=1"
  exit /b 1
)
exit /b 0

:write_png
set "FILE_PATH=%~1"
%PS_EXE% -NoProfile -Command "$b64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5nG8kAAAAASUVORK5CYII='; [System.IO.File]::WriteAllBytes('%FILE_PATH%', [Convert]::FromBase64String($b64))"
if errorlevel 1 (
  echo [FAIL] failed to write png fixture
  set "FAIL=1"
  exit /b 1
)
exit /b 0

:extract_token
set "BODY_FILE=%~1"
set "OUT_VAR=%~2"
for /f "usebackq delims=" %%T in (`%PS_EXE% -NoProfile -Command "$ErrorActionPreference='Stop'; $obj = Get-Content -Raw '%BODY_FILE%' | ConvertFrom-Json; if (-not $obj.token) { exit 1 }; Write-Output $obj.token"`) do set "%OUT_VAR%=%%T"
if not defined %OUT_VAR% (
  echo [FAIL] response JSON missing token
  set "FAIL=1"
  exit /b 1
)
exit /b 0

:assert_status
set "LABEL=%~1"
set "ACTUAL=%~2"
set "EXPECTED=%~3"
set /a ASSERT_TOTAL+=1
if "%ACTUAL%"=="%EXPECTED%" (
  echo [PASS] %LABEL%
  set /a ASSERT_PASS+=1
  exit /b 0
)
echo [FAIL] %LABEL% expected %EXPECTED% but got %ACTUAL%
set /a ASSERT_FAIL+=1
exit /b 1

:assert_body_equals
set "LABEL=%~1"
set "BODY_FILE=%~2"
set "EXPECTED=%~3"
for /f "usebackq delims=" %%B in (`%PS_EXE% -NoProfile -Command "(Get-Content -Raw '%BODY_FILE%').Trim()"`) do set "ACTUAL=%%B"
set /a ASSERT_TOTAL+=1
if "%ACTUAL%"=="%EXPECTED%" (
  echo [PASS] %LABEL%
  set /a ASSERT_PASS+=1
  exit /b 0
)
echo [FAIL] %LABEL% expected %EXPECTED% but got %ACTUAL%
set /a ASSERT_FAIL+=1
exit /b 1

:assert_nonempty
set "LABEL=%~1"
set "VALUE=%~2"
set /a ASSERT_TOTAL+=1
if not "%VALUE%"=="" (
  echo [PASS] %LABEL%
  set /a ASSERT_PASS+=1
  exit /b 0
)
echo [FAIL] %LABEL%
set /a ASSERT_FAIL+=1
exit /b 1

:assert_not_equal
set "LABEL=%~1"
set "A=%~2"
set "B=%~3"
set /a ASSERT_TOTAL+=1
if not "%A%"=="%B%" (
  echo [PASS] %LABEL%
  set /a ASSERT_PASS+=1
  exit /b 0
)
echo [FAIL] %LABEL% (values are equal)
set /a ASSERT_FAIL+=1
exit /b 1

:assert_equal
set "LABEL=%~1"
set "A=%~2"
set "B=%~3"
set /a ASSERT_TOTAL+=1
if "%A%"=="%B%" (
  echo [PASS] %LABEL%
  set /a ASSERT_PASS+=1
  exit /b 0
)
echo [FAIL] %LABEL% expected %B% but got %A%
set /a ASSERT_FAIL+=1
exit /b 1

:assert_minimum
set "LABEL=%~1"
set "ACTUAL=%~2"
set "MINIMUM=%~3"
set /a ASSERT_TOTAL+=1
set /a ACTUAL_NUM=%ACTUAL%
set /a MIN_NUM=%MINIMUM%
if %ACTUAL_NUM% GEQ %MIN_NUM% (
  echo [PASS] %LABEL%: %ACTUAL%
  set /a ASSERT_PASS+=1
  exit /b 0
)
echo [FAIL] %LABEL% expected at least %MINIMUM% but got %ACTUAL%
set /a ASSERT_FAIL+=1
exit /b 1

:assert_exists
set "LABEL=%~1"
set "PATH=%~2"
set /a ASSERT_TOTAL+=1
if exist "%PATH%" (
  echo [PASS] %LABEL%
  set /a ASSERT_PASS+=1
  exit /b 0
)
echo [FAIL] %LABEL% missing at %PATH%
set /a ASSERT_FAIL+=1
exit /b 1

:assert_dir_exists
set "LABEL=%~1"
set "PATH=%~2"
set /a ASSERT_TOTAL+=1
if exist "%PATH%\." (
  echo [PASS] %LABEL%
  set /a ASSERT_PASS+=1
  exit /b 0
)
echo [FAIL] %LABEL% missing at %PATH%
set /a ASSERT_FAIL+=1
exit /b 1

:assert_files_equal
set "LABEL=%~1"
set "FILE_A=%~2"
set "FILE_B=%~3"
set /a ASSERT_TOTAL+=1
%PS_EXE% -NoProfile -Command "$ErrorActionPreference='Stop'; $a = Get-FileHash -Algorithm SHA256 '%FILE_A%'; $b = Get-FileHash -Algorithm SHA256 '%FILE_B%'; if ($a.Hash -ne $b.Hash) { exit 1 }"
if errorlevel 1 (
  echo [FAIL] %LABEL%
  set /a ASSERT_FAIL+=1
  exit /b 1
)
echo [PASS] %LABEL%
set /a ASSERT_PASS+=1
exit /b 0

:assert_error_response
set "LABEL=%~1"
set "STATUS=%~2"
set "EXPECTED_STATUS=%~3"
set "BODY_FILE=%~4"
set "HEADERS_FILE=%~5"
set "ERROR_CODE=%~6"
call :assert_status "%LABEL% status %EXPECTED_STATUS%" "%STATUS%" "%EXPECTED_STATUS%"
if errorlevel 1 exit /b 1
call :assert_error_json "%LABEL% json" "%BODY_FILE%" "%ERROR_CODE%"
if errorlevel 1 exit /b 1
call :assert_header_json "%LABEL% content-type json" "%HEADERS_FILE%"
if errorlevel 1 exit /b 1
exit /b 0

:assert_error_json
set "LABEL=%~1"
set "BODY_FILE=%~2"
set "ERROR_CODE=%~3"
%PS_EXE% -NoProfile -Command "$ErrorActionPreference='Stop'; $obj = Get-Content -Raw '%BODY_FILE%' | ConvertFrom-Json; $names = $obj.PSObject.Properties.Name; if ($names.Count -ne 1 -or -not ($names -contains 'error')) { exit 1 }; if ($obj.error -ne '%ERROR_CODE%') { exit 1 }"
set /a ASSERT_TOTAL+=1
if errorlevel 1 (
  echo [FAIL] %LABEL%
  set /a ASSERT_FAIL+=1
  exit /b 1
)
echo [PASS] %LABEL%
set /a ASSERT_PASS+=1
exit /b 0

:assert_header_json
set "LABEL=%~1"
set "HEADERS_FILE=%~2"
%PS_EXE% -NoProfile -Command "$ErrorActionPreference='Stop'; $line = Get-Content -Path '%HEADERS_FILE%' | Where-Object { $_ -match '^(?i)Content-Type:' } | Select-Object -First 1; if (-not $line) { exit 1 }; $value = $line.Split(':',2)[1].Trim().ToLowerInvariant(); if (-not $value.StartsWith('application/json')) { exit 1 }"
set /a ASSERT_TOTAL+=1
if errorlevel 1 (
  echo [FAIL] %LABEL%
  set /a ASSERT_FAIL+=1
  exit /b 1
)
echo [PASS] %LABEL%
set /a ASSERT_PASS+=1
exit /b 0

:assert_inspect
set "BODY_FILE=%~1"
set "EXPECTED_CONTENT=%~2"
set "EXPECTED_EXT=%~3"
set "EXPECTED_SIZE=%~4"
set "EXPECTED_REASON=%~5"
set "LABEL=%~6"
%PS_EXE% -NoProfile -Command "$ErrorActionPreference='Stop'; $obj = Get-Content -Raw '%BODY_FILE%' | ConvertFrom-Json; $required = @('created_at','byte_size','content_type','file_extension','upload_complete','sanitized','sanitize_reason','sanitize_error'); $missing = $required | Where-Object { -not $obj.PSObject.Properties.Name -contains $_ }; if ($missing.Count -gt 0) { exit 1 }; $forbidden = @('token','storage_id','storageId','path','file_path'); $present = $forbidden | Where-Object { $obj.PSObject.Properties.Name -contains $_ }; if ($present.Count -gt 0) { exit 1 }; if ('%EXPECTED_CONTENT%' -ne '' -and $obj.content_type -ne '%EXPECTED_CONTENT%') { exit 1 }; if ('%EXPECTED_EXT%' -ne '' -and $obj.file_extension -ne '%EXPECTED_EXT%') { exit 1 }; if ('%EXPECTED_SIZE%' -ne '' -and [string]$obj.byte_size -ne '%EXPECTED_SIZE%') { exit 1 }; if ($obj.upload_complete -ne $true) { exit 1 }; $expected = '%EXPECTED_REASON%'; if ($expected -eq 'applied_or_failed') { if ($obj.sanitize_reason -ne 'applied' -and $obj.sanitize_reason -ne 'failed') { exit 1 }; if ($obj.sanitize_reason -eq 'applied' -and $obj.sanitized -ne $true) { exit 1 }; if ($obj.sanitize_reason -eq 'failed') { if ($obj.sanitized -ne $false) { exit 1 }; if ($obj.sanitize_error -ne 'sanitize_failed') { exit 1 } } else { if ($null -ne $obj.sanitize_error) { exit 1 } } } else { if ($obj.sanitize_reason -ne $expected) { exit 1 }; if ($obj.sanitized -ne $false) { exit 1 }; if ($null -ne $obj.sanitize_error) { exit 1 } }"
set /a ASSERT_TOTAL+=1
if errorlevel 1 (
  echo [FAIL] %LABEL%
  set /a ASSERT_FAIL+=1
  exit /b 1
)
echo [PASS] %LABEL%
set /a ASSERT_PASS+=1
exit /b 0

:count_uploads
set "OUT_VAR=%~1"
for /f "usebackq delims=" %%C in (`%PS_EXE% -NoProfile -Command "(Get-ChildItem -File -Path '%UPLOADS_DIR%' -ErrorAction SilentlyContinue | Measure-Object).Count"`) do set "%OUT_VAR%=%%C"
if not defined %OUT_VAR% set "%OUT_VAR%=0"
exit /b 0

:count_index
set "OUT_VAR=%~1"
for /f "usebackq delims=" %%C in (`%PS_EXE% -NoProfile -Command "if (Test-Path '%INDEX_FILE%') { (Get-Content -Path '%INDEX_FILE%' | Where-Object { $_ -match '\\S' }).Count } else { 0 }"`) do set "%OUT_VAR%=%%C"
if not defined %OUT_VAR% set "%OUT_VAR%=0"
exit /b 0

:index_counts
set "OUT_TOTAL=%~1"
set "OUT_UNIQUE=%~2"
set "INDEX_COUNTS_FILE=%TEMP_DIR%\index-counts.txt"
%PS_EXE% -NoProfile -Command "$path = '%INDEX_FILE%'; $out = '%INDEX_COUNTS_FILE%'; if (-not (Test-Path $path)) { [System.IO.File]::WriteAllText($out, '0,0'); exit } $text = Get-Content -Raw -Path $path; $matches = [regex]::Matches($text, '\"token\"\\s*:\\s*\"([^\"]+)\"'); $set = New-Object 'System.Collections.Generic.HashSet[string]'; $total = 0; foreach ($m in $matches) { $total++; [void]$set.Add($m.Groups[1].Value) }; [System.IO.File]::WriteAllText($out, ($total.ToString() + ',' + $set.Count.ToString()))"
for /f "usebackq tokens=1,2 delims=," %%A in ("%INDEX_COUNTS_FILE%") do (
  set "%OUT_TOTAL%=%%A"
  set "%OUT_UNIQUE%=%%B"
)
exit /b 0





