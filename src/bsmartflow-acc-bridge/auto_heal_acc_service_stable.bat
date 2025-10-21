@echo off
title BsmartFlow ACC Auto-Heal (Stable Mode)
echo =====================================================
echo  BsmartFlow ACC Auto-Heal and Health Validator
echo =====================================================
echo Project: bsmartflow-474718
echo Region : asia-south1
echo -----------------------------------------------------

set PROJECT=bsmartflow-474718
set REGION=asia-south1
set SERVICE=bsmartflow-acc
set BRIDGE_SA=bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.com
set ACC_URL=https://bsmartflow-acc-147849918817.asia-south1.run.app
set LOGFILE=acc_autoheal_log.txt
set RETRY_DELAY=60

echo [INIT] Started at %date% %time% > "%LOGFILE%"

:LOOP
echo.
echo Checking ACC health endpoint...
for /f %%a in ('curl -s -o nul -w "%%{http_code}" %ACC_URL%/health') do set STATUS=%%a
echo Status Code: %STATUS%

if "%STATUS%"=="200" (
    echo [%time%] ACC healthy >> "%LOGFILE%"
    echo ACC service is healthy. Verifying bridge communication...
    goto VERIFY
) else (
    echo [%time%] ACC unhealthy (%STATUS%), redeploying... >> "%LOGFILE%"
    echo ACC unhealthy. Redeploying now...
    gcloud run deploy %SERVICE% --source . --region=%REGION% --project=%PROJECT% --memory=1Gi --timeout=900s --concurrency=80 --service-account=bsmartflow-474718@appspot.gserviceaccount.com --quiet >> "%LOGFILE%" 2>&1
    echo Redeploy complete. Waiting %RETRY_DELAY%s for stabilization...
    timeout /t %RETRY_DELAY% >nul
    goto LOOP
)

:VERIFY
echo Getting Bridge service token...
for /f %%b in ('gcloud auth print-identity-token --impersonate-service-account=%BRIDGE_SA% --project=%PROJECT%') do set TOKEN=%%b

curl -s -X POST %ACC_URL%/execute_task -H "Authorization: Bearer %TOKEN%" -H "Content-Type: application/json" -d "{\"ping\":\"autoheal_check\"}" > resp.json

find /I "ACC executed successfully" resp.json >nul
if %errorlevel%==0 (
    echo [%time%] Bridge verified successfully >> "%LOGFILE%"
    echo ACC communication verified successfully!
    del resp.json
    echo.
    echo SYSTEM HEALTHY AND STABLE.
    pause
    exit /b
) else (
    echo [%time%] Bridge verification failed >> "%LOGFILE%"
    echo Bridge verification failed. Redeploying again...
    del resp.json
    timeout /t %RETRY_DELAY% >nul
    goto LOOP
)
