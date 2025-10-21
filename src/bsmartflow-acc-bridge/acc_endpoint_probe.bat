@echo off
setlocal enabledelayedexpansion

echo ======================================================
echo 🔍 Starting ACC Endpoint Diagnostic Probe...
echo ======================================================

set PROJECT_ID=bsmartflow-474718
set REGION=asia-south1
set ACC_URL=https://bsmartflow-acc-147849918817.asia-south1.run.app

echo.
echo 🪪 Generating ID token for authorized access...
for /f "tokens=* USEBACKQ" %%F in (`gcloud auth print-identity-token`) do set TOKEN=%%F

if "%TOKEN%"=="" (
    echo ❌ Failed to generate identity token.
    exit /b 1
)

echo.
echo 🧩 Testing common ACC endpoints...
set FOUND=0

for %%E in (/
    /api
    /api/connect
    /connect
    /execute_task
    /acc-connect
    /gpt-connect
    /ping
    /health
    /status
    /acc/health
    /acc/test
    /acc/api
    /task/execute
) do (
    echo ------------------------------------------------------
    echo 🌐 Testing: %ACC_URL%%%E
    curl -s -o nul -w "%%{http_code}" -H "Authorization: Bearer %TOKEN%" "%ACC_URL%%%E"
    echo.
    for /f %%S in ('curl -s -o nul -w "%%{http_code}" -H "Authorization: Bearer %TOKEN%" "%ACC_URL%%%E"') do (
        if "%%S"=="200" (
            echo ✅ Found working endpoint: %ACC_URL%%%E
            set FOUND=1
            set GOOD_URL=%ACC_URL%%%E
            goto :FOUND
        )
    )
)

:FOUND
if "%FOUND%"=="1" (
    echo ======================================================
    echo ✅ SUCCESS: ACC endpoint found!
    echo Endpoint: %GOOD_URL%
    echo ======================================================
) else (
    echo ======================================================
    echo ❌ No valid ACC endpoints responded with 200 OK.
    echo Please verify the routes in your ACC service code.
    echo ======================================================
)

pause
endlocal
