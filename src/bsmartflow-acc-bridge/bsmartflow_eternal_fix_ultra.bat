@echo off
title ⚙️ BsmartFlow ULTRA Eternal Cloud Auto-Fix Engine
color 0A
setlocal ENABLEDELAYEDEXPANSION

:: ========== CONFIG ==========
set PROJECT_ID=bsmartflow-474718
set REGION=asia-south1
set ACC_SERVICE=bsmartflow-acc
set BRIDGE_SERVICE=bsmartflow-acc-bridge
set SECRET_NAME=gpt-service-token
set ADMIN_EMAIL=admin@bsmartflow.com
set LOGFILE=%TEMP%\bsmartflow_ultra_fix.log
set MEMORY=1Gi
set TIMEOUT=600s
set CONCURRENCY=80
set RETRY_DELAY=30
set /a CYCLE=0
set /a SUMMARY_INTERVAL=10
set /a LOG_ROTATE_INTERVAL=5
set BRIDGE_SA=bsmartflow-acc-bridge@%PROJECT_ID%.iam.gserviceaccount.com

if exist "%LOGFILE%" del "%LOGFILE%"
echo ============================================================>>"%LOGFILE%"
echo [%DATE% %TIME%] 🚀 BsmartFlow ULTRA Eternal Engine Starting >>"%LOGFILE%"
echo ============================================================>>"%LOGFILE%"
echo.
echo [INFO] Eternal Fix Loop active. Will never stop.
echo [INFO] Logs stored at: %LOGFILE%
echo.

:INFINITE_LOOP
set /a CYCLE+=1
echo. & echo ===================================================
echo [%DATE% %TIME%] 🔁 Cycle #%CYCLE% BEGIN
echo ===================================================>>"%LOGFILE%"

:: PRECHECK
call :safe_exec "gcloud config set project %PROJECT_ID%"
call :safe_exec "gcloud config set run/region %REGION%"
if errorlevel 1 call :recover_sdk

:: Rotate GPT token each cycle
for /f "delims=" %%T in ('powershell -NoProfile -Command "[guid]::NewGuid().ToString('N')"') do set GPT_TOKEN=%%T
echo %GPT_TOKEN%>token.txt
call :safe_exec "gcloud secrets versions add %SECRET_NAME% --data-file=token.txt --project=%PROJECT_ID%"
del token.txt >nul 2>&1

:: Get URLs
for /f "delims=" %%U in ('gcloud run services describe %ACC_SERVICE% --region=%REGION% --project=%PROJECT_ID% --format="value(status.url)" 2^>nul') do set ACC_URL=%%U
for /f "delims=" %%V in ('gcloud run services describe %BRIDGE_SERVICE% --region=%REGION% --project=%PROJECT_ID% --format="value(status.url)" 2^>nul') do set BRIDGE_URL=%%V
if "%ACC_URL%"=="" call :log "⚠️ ACC URL missing → redeploying" & call :redeploy_acc
if "%BRIDGE_URL%"=="" call :log "⚠️ Bridge URL missing → redeploying" & call :redeploy_bridge

:: TEST BRIDGE ↔ ACC
if not "%BRIDGE_URL%"=="" (
  call :log "🔗 Testing GPT→Bridge→ACC link..."
  curl -s -X POST "%BRIDGE_URL%/gpt-connect" ^
    -H "Authorization: Bearer %GPT_TOKEN%" ^
    -H "Content-Type: application/json" ^
    -d "{\"command\":\"ping_acc\"}" >"%TEMP%\bridge_test.tmp"
)

:: CHECK RESULTS
findstr /i "401 Unauthorized" "%TEMP%\bridge_test.tmp" >nul && (
  call :log "❌ 401 Unauthorized: IAM/Token issue. Fixing..."
  call :fix_iam
  call :redeploy_bridge
)
findstr /i "402" "%TEMP%\bridge_test.tmp" >nul && (
  call :log "❌ 402 Billing issue detected → Enabling billing API"
  call :safe_exec "gcloud services enable billing.googleapis.com --project=%PROJECT_ID%"
)
findstr /i "403 Forbidden" "%TEMP%\bridge_test.tmp" >nul && (
  call :log "❌ 403 Forbidden: permission denied → rebinding IAM"
  call :fix_iam
)
findstr /i "500" "%TEMP%\bridge_test.tmp" >nul && (
  call :log "🔥 500 Internal Server Error: restarting bridge"
  call :redeploy_bridge
)
findstr /i "timeout" "%TEMP%\bridge_test.tmp" >nul && (
  call :log "⚠️ Timeout: increasing service timeout & redeploying bridge"
  call :safe_exec "gcloud run services update %BRIDGE_SERVICE% --timeout=%TIMEOUT% --region=%REGION% --project=%PROJECT_ID%"
)
findstr /i "acknowledged" "%TEMP%\bridge_test.tmp" >nul && (
  call :log "✅ GPT→Bridge→ACC working fine."
)

:: FIREBASE CHECK
call :safe_exec "gcloud firestore databases describe --project=%PROJECT_ID%"

:: SDK CRASH PROTECTION
if errorlevel 1 (
  call :log "💥 Cloud SDK Command failed! Restarting gcloud auth..."
  gcloud auth login --quiet >>"%LOGFILE%" 2>&1
)

:: WINDOWS FAILSAFE PROTECTION
if not exist "%ProgramFiles%\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd" (
  call :log "🚫 Google Cloud SDK binaries missing. Attempting auto-repair..."
  call :repair_sdk
)

:: EVERY 5 CYCLES rotate logs
if %CYCLE% GEQ %LOG_ROTATE_INTERVAL% (
  move "%LOGFILE%" "%LOGFILE%.old" >nul 2>&1
  echo [%DATE% %TIME%] 🔄 Log rotated. New session starts >>"%LOGFILE%"
  set /a CYCLE=0
)

:: EVERY 10 cycles generate summary
set /a SMOD=%CYCLE% %% %SUMMARY_INTERVAL%
if %SMOD%==0 call :generate_summary

:: Sleep and restart
call :log "⏳ Sleeping %RETRY_DELAY%s before next loop..."
timeout /t %RETRY_DELAY% >nul 2>&1
goto INFINITE_LOOP

:: ========== SUBROUTINES ==========

:safe_exec
%~1 >>"%LOGFILE%" 2>&1
if errorlevel 1 echo [%DATE% %TIME%] ⚠️ Command failed: %~1 >>"%LOGFILE%"
exit /b

:log
echo [%DATE% %TIME%] %~1
echo [%DATE% %TIME%] %~1 >>"%LOGFILE%"
exit /b

:fix_iam
call :log "🔐 Fixing IAM roles..."
call :safe_exec "gcloud run services add-iam-policy-binding %ACC_SERVICE% --member=serviceAccount:%BRIDGE_SA% --role=roles/run.invoker --region=%REGION% --project=%PROJECT_ID%"
call :safe_exec "gcloud run services add-iam-policy-binding %BRIDGE_SERVICE% --member=user:%ADMIN_EMAIL% --role=roles/run.invoker --region=%REGION% --project=%PROJECT_ID%"
call :safe_exec "gcloud secrets add-iam-policy-binding %SECRET_NAME% --member=serviceAccount:%BRIDGE_SA% --role=roles/secretmanager.secretAccessor --project=%PROJECT_ID%"
exit /b

:redeploy_acc
call :log "♻️ Redeploying ACC..."
call :safe_exec "gcloud run deploy %ACC_SERVICE% --source=. --region=%REGION% --project=%PROJECT_ID% --clear-base-image --memory=%MEMORY% --timeout=%TIMEOUT% --concurrency=%CONCURRENCY% --quiet"
exit /b

:redeploy_bridge
call :log "♻️ Redeploying Bridge..."
call :safe_exec "gcloud run deploy %BRIDGE_SERVICE% --source=. --region=%REGION% --project=%PROJECT_ID% --clear-base-image --memory=%MEMORY% --timeout=%TIMEOUT% --concurrency=%CONCURRENCY% --set-env-vars ACC_URL=%ACC_URL%,GPT_TOKEN=%GPT_TOKEN% --quiet"
exit /b

:recover_sdk
call :log "💥 SDK environment unstable — reloading context..."
call :safe_exec "gcloud init --quiet"
exit /b

:repair_sdk
call :log "🧩 Attempting Cloud SDK auto-repair..."
powershell -Command "Start-Process 'https://cloud.google.com/sdk/docs/install' -WindowStyle Hidden"
exit /b

:generate_summary
call :log "📊 Generating health summary..."
findstr /i "401 402 403 404 500 timeout error fail unauthorized forbidden billing" "%LOGFILE%" | sort | uniq >"%TEMP%\ultra_diagnosis.txt"
start notepad "%TEMP%\ultra_diagnosis.txt"
exit /b
