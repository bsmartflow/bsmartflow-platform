@echo off
setlocal enabledelayedexpansion
:: =====================================================
::   BsmartFlow ACC + Bridge Auto-Heal and Health Validator
:: =====================================================
set PROJECT=bsmartflow-474718
set REGION=asia-south1
set ACC_SERVICE=bsmartflow-acc
set BRIDGE_SERVICE=bsmartflow-acc-bridge
set ACC_URL=https://bsmartflow-acc-147849918817.asia-south1.run.app
set BRIDGE_URL=https://bsmartflow-acc-bridge-147849918817.asia-south1.run.app
set LOG_FILE=%~dp0auto_heal_log.txt
echo. >> "%LOG_FILE%"
echo ===================================================== >> "%LOG_FILE%"
echo 🩺 [%date% %time%] Starting ACC + Bridge Health Check >> "%LOG_FILE%"
echo ===================================================== >> "%LOG_FILE%"

:: Function to check and heal one service
call :CHECK_AND_HEAL %ACC_SERVICE% %ACC_URL%
call :CHECK_AND_HEAL %BRIDGE_SERVICE% %BRIDGE_URL%

echo ✅ [%date% %time%] Health check complete. >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"
exit /b

:: --------------------- SUBROUTINE ---------------------
:CHECK_AND_HEAL
set SERVICE=%1
set URL=%2

echo ----------------------------------------------------- >> "%LOG_FILE%"
echo Checking %SERVICE% health endpoint... >> "%LOG_FILE%"
for /f "delims=" %%I in ('curl -s -o nul -w "%%{http_code}" %URL%/health') do set STATUS=%%I
echo HTTP Status for %SERVICE%: !STATUS! >> "%LOG_FILE%"

if "!STATUS!"=="200" (
    echo ✅ %SERVICE% is healthy. >> "%LOG_FILE%"
    goto :EOF
)

if "!STATUS!"=="403" (
    echo ⚠️ %SERVICE% returned 403 (Forbidden) - repairing IAM... >> "%LOG_FILE%"
    gcloud run services add-iam-policy-binding %SERVICE% --region=%REGION% --project=%PROJECT% ^
        --member="serviceAccount:bsmartflow-acc-bridge@%PROJECT%.iam.gserviceaccount.com" ^
        --role="roles/run.invoker" >> "%LOG_FILE%" 2>&1
    goto :EOF
)

if "!STATUS!"=="401" (
    echo ⚠️ %SERVICE% returned 401 (Unauthorized) - repairing IAM... >> "%LOG_FILE%"
    gcloud run services add-iam-policy-binding %SERVICE% --region=%REGION% --project=%PROJECT% ^
        --member="serviceAccount:bsmartflow-acc-bridge@%PROJECT%.iam.gserviceaccount.com" ^
        --role="roles/run.invoker" >> "%LOG_FILE%" 2>&1
    goto :EOF
)

if "!STATUS!"=="404" (
    echo ❌ %SERVICE% not responding - redeploying... >> "%LOG_FILE%"
    gcloud run deploy %SERVICE% --region=%REGION% --project=%PROJECT% --source . --quiet >> "%LOG_FILE%" 2>&1
    goto :EOF
)

echo ⚠️ Unexpected response (!STATUS!) from %SERVICE%. Logged for manual review. >> "%LOG_FILE%"
goto :EOF
