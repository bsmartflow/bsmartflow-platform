@echo off
setlocal enabledelayedexpansion
title BsmartFlow ACC Auto-Heal Diagnostic & Redeploy Utility

echo ======================================================
echo  BsmartFlow ACC Auto-Heal and Health Validator
echo ======================================================
echo Project: bsmartflow-474718
echo Region : asia-south1
echo ------------------------------------------------------

:: Core Variables
set PROJECT=bsmartflow-474718
set REGION=asia-south1
set SERVICE=bsmartflow-acc
set BRIDGE_SA=bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.com
set ACC_URL=https://bsmartflow-acc-147849918817.asia-south1.run.app
set LOGFILE=acc_autoheal_log.txt
set RETRY_DELAY=60

echo [INIT] Started at %date% %time% > %LOGFILE%

:CHECK_HEALTH
echo.
echo Checking ACC health endpoint...
for /f "delims=" %%I in ('curl -s -o nul -w "%%{http_code}" %ACC_URL%/health') do set STATUS=%%I

echo [%time%] HTTP %STATUS% >> %LOGFILE%

if "%STATUS%"=="200" (
    echo ACC service healthy. Code: %STATUS%
    echo [OK] ACC service healthy. >> %LOGFILE%
    goto VERIFY_EXEC
) else (
    echo ACC unhealthy (Code %STATUS%). Redeploying... >> %LOGFILE%
    goto REDEPLOY
)

:REDEPLOY
echo ------------------------------------------------------
echo Redeploying ACC service now...
echo ------------------------------------------------------
gcloud run deploy %SERVICE% ^
  --source . ^
  --region=%REGION% ^
  --project=%PROJECT% ^
  --memory=1Gi ^
  --timeout=900s ^
  --concurrency=80 ^
  --service-account=bsmartflow-474718@appspot.gserviceaccount.com ^
  --quiet >> %LOGFILE% 2>&1

echo Redeployment done at %time%.
echo Waiting %RETRY_DELAY%s for service to stabilize...
timeout /t %RETRY_DELAY% > nul
goto CHECK_HEALTH

:VERIFY_EXEC
echo.
echo Verifying Bridge to ACC communication...
for /f "delims=" %%I in ('gcloud auth print-identity-token --impersonate-service-account=%BRIDGE_SA% --project=%PROJECT%') do set TOKEN=%%I

curl -s -X POST %ACC_URL%/execute_task ^
  -H "Authorization: Bearer %TOKEN%" ^
  -H "Content-Type: application/json" ^
  -d "{\"ping\":\"autoheal_check\"}" ^
  > response.json

findstr /C:"ACC executed successfully" response.json > nul
if %errorlevel%==0 (
    echo ACC communication verified OK!
    echo [SUCCESS] Verified. Auto-heal completed. >> %LOGFILE%
    del response.json
    echo.
    echo System Healthy and Stable.
    pause
    exit /b
) else (
    echo ACC endpoint failed verification.
    echo [FAIL] Communication check failed. Redeploying again... >> %LOGFILE%
    del response.json
    timeout /t %RETRY_DELAY% > nul
    goto REDEPLOY
)
