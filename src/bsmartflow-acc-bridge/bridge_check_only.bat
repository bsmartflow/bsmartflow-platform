@echo off
setlocal enabledelayedexpansion
title 🔍 BsmartFlow Bridge ↔ ACC Health Check

echo.
echo ===========================================================
echo     🩺 BsmartFlow ACC + Bridge Live Health Validator
echo ===========================================================
echo.

REM ====== CONFIGURATION ======
set PROJECT_ID=bsmartflow-474718
set REGION=asia-south1
set ACC_SERVICE_NAME=bsmartflow-acc
set BRIDGE_SERVICE_ACCOUNT=bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.com
set ACC_URL=https://bsmartflow-acc-147849918817.asia-south1.run.app
set BRIDGE_URL=https://bsmartflow-acc-bridge-147849918817.asia-south1.run.app
set AUTH_TOKEN=8ed1029a16d4ad46e680db41d327b6447995c3c57eca6fa67b0783a33a5c3d66

echo [INFO] Project ID: %PROJECT_ID%
echo [INFO] Region: %REGION%
echo [INFO] ACC URL: %ACC_URL%
echo [INFO] Bridge URL: %BRIDGE_URL%
echo.

REM ====== STEP 1: ACC HEALTH TEST ======
echo [CHECK] Testing ACC health endpoint...
for /f "delims=" %%i in ('gcloud auth print-identity-token --impersonate-service-account=%BRIDGE_SERVICE_ACCOUNT% --audiences=%ACC_URL%') do set TOKEN=%%i

for /f "delims=" %%a in ('curl -s -H "Authorization: Bearer !TOKEN!" !ACC_URL!/') do set ACC_RESPONSE=%%a

if "!ACC_RESPONSE!"=="" (
    echo [ERROR] ❌ ACC health endpoint not responding.
) else (
    echo [RESULT] ACC Response:
    echo !ACC_RESPONSE!
)
echo.

REM ====== STEP 2: BRIDGE RELAY TEST ======
echo [CHECK] Testing Bridge -> ACC relay task...
for /f "delims=" %%i in ('gcloud auth print-identity-token --impersonate-service-account=%BRIDGE_SERVICE_ACCOUNT% --audiences=%BRIDGE_URL%') do set BRIDGE_TOKEN=%%i

for /f "delims=" %%r in ('curl -s -X POST %BRIDGE_URL%/relay_task -H "Authorization: Bearer !BRIDGE_TOKEN!" -H "Content-Type: application/json" -d "{\"initiator\":\"admin@bsmartflow.com\",\"command\":\"system_status_check\",\"parameters\":{\"mode\":\"live\"},\"auth_token\":\"%AUTH_TOKEN%\"}"') do set RELAY_RESPONSE=%%r

if "!RELAY_RESPONSE!"=="" (
    echo [ERROR] ⚠️ Bridge relay failed to get a valid response.
) else (
    echo [RESULT] Bridge Relay Response:
    echo !RELAY_RESPONSE!
)
echo.

REM ====== STEP 3: FINAL SUMMARY ======
echo ===========================================================
if "!ACC_RESPONSE!"=="" (
    echo ❌ ACC Offline or Unreachable
) else if "!RELAY_RESPONSE!"=="" (
    echo ⚠️ ACC OK, Bridge Relay Failed (Check Logs)
) else (
    echo ✅ FULL SYSTEM PASS — ACC ↔ Bridge verified successfully.
)
echo ===========================================================
echo.
pause
