@echo off
setlocal enabledelayedexpansion
title 🔁 BsmartFlow Eternal Auto-Heal Engine
color 0A

:: ===========================================================
:: CONFIG
:: ===========================================================
set PROJECT_ID=bsmartflow-474718
set REGION=asia-south1
set ACC_SERVICE=bsmartflow-acc
set BRIDGE_SERVICE=bsmartflow-acc-bridge
set SECRET_NAME=gpt-service-token
set ADMIN_EMAIL=admin@bsmartflow.com
set BRIDGE_SA=bsmartflow-acc-bridge@%PROJECT_ID%.iam.gserviceaccount.com
set ACC_SA=bsmartflow-acc-sa@%PROJECT_ID%.iam.gserviceaccount.com
set MEMORY=1Gi
set TIMEOUT=600s
set CONCURRENCY=80
set BACKUP_BUCKET=%PROJECT_ID%-autoheal-backups
set LOGFILE=%TEMP%\bsmartflow_eternal.log

if exist "%LOGFILE%" del "%LOGFILE%"

echo =========================================================== >> "%LOGFILE%"
echo 🔁 Starting BsmartFlow Eternal Auto-Heal Engine >> "%LOGFILE%"
echo =========================================================== >> "%LOGFILE%"
echo Starting infinite monitoring... Press CTRL+C to stop.
echo ===========================================================
timeout /t 2 >nul

:: ===========================================================
:: CORE LOOP
:: ===========================================================
:MAIN_LOOP
call :log "💡 Checking environment and APIs..."
gcloud config set project %PROJECT_ID% >nul
gcloud config set run/region %REGION% >nul
gcloud services enable run.googleapis.com secretmanager.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com pubsub.googleapis.com firestore.googleapis.com --project=%PROJECT_ID% >nul 2>&1

:: Create backup bucket if missing
gsutil ls -b gs://%BACKUP_BUCKET% >nul 2>&1 || gsutil mb -p %PROJECT_ID% -l %REGION% gs://%BACKUP_BUCKET% >> "%LOGFILE%" 2>&1

:: Rotate token
for /f "delims=" %%T in ('powershell -NoProfile -Command "[guid]::NewGuid().ToString('N')"') do set GPT_TOKEN=%%T
echo %GPT_TOKEN%>token.txt
gcloud secrets versions add %SECRET_NAME% --data-file=token.txt --project=%PROJECT_ID% >nul 2>&1
del token.txt

:: Fetch ACC URL
for /f "delims=" %%A in ('gcloud run services describe %ACC_SERVICE% --region=%REGION% --project=%PROJECT_ID% --format="value(status.url)" 2^>nul') do set ACC_URL=%%A
if "%ACC_URL%"=="" (
    call :log "⚠️ ACC URL missing, redeploying ACC..."
    gcloud run deploy %ACC_SERVICE% --source=. --region=%REGION% --project=%PROJECT_ID% --clear-base-image --memory=%MEMORY% --timeout=%TIMEOUT% --concurrency=%CONCURRENCY% --quiet >> "%LOGFILE%" 2>&1
    goto MAIN_LOOP
)

:: Fetch Bridge URL
for /f "delims=" %%B in ('gcloud run services describe %BRIDGE_SERVICE% --region=%REGION% --project=%PROJECT_ID% --format="value(status.url)" 2^>nul') do set BRIDGE_URL=%%B
if "%BRIDGE_URL%"=="" (
    call :log "⚠️ Bridge URL missing, redeploying Bridge..."
    gcloud run deploy %BRIDGE_SERVICE% --source=. --region=%REGION% --project=%PROJECT_ID% --clear-base-image --memory=%MEMORY% --timeout=%TIMEOUT% --concurrency=%CONCURRENCY% --set-env-vars ACC_URL=%ACC_URL%,GPT_TOKEN=%GPT_TOKEN% --quiet >> "%LOGFILE%" 2>&1
    goto MAIN_LOOP
)

call :log "🔗 Testing Bridge → ACC → Firebase → GCP connectivity..."

:: Test the GPT Bridge call
curl -s -X POST "%BRIDGE_URL%/gpt-connect" ^
  -H "Authorization: Bearer %GPT_TOKEN%" ^
  -H "Content-Type: application/json" ^
  -d "{\"command\":\"ping_acc\"}" > "%TEMP%\bridge_test.tmp"

:: Check response
findstr /i "401 Unauthorized" "%TEMP%\bridge_test.tmp" >nul && (
    call :log "❌ 401 Unauthorized detected. IAM or token issue. Rebinding IAM and redeploying Bridge."
    call :fix_iam
    goto REDEPLOY_BRIDGE
)

findstr /i "402" "%TEMP%\bridge_test.tmp" >nul && (
    call :log "❌ 402 Payment or API quota issue detected. Enabling Billing APIs..."
    gcloud services enable billing.googleapis.com --project=%PROJECT_ID% >> "%LOGFILE%" 2>&1
    goto MAIN_LOOP
)

findstr /i "403 Forbidden" "%TEMP%\bridge_test.tmp" >nul && (
    call :log "❌ 403 Forbidden detected. Rebinding permissions..."
    call :fix_iam
    goto REDEPLOY_BRIDGE
)

findstr /i "404" "%TEMP%\bridge_test.tmp" >nul && (
    call :log "❌ 404 Not Found detected. ACC route unreachable. Redeploying ACC."
    call :redeploy_acc
    goto MAIN_LOOP
)

findstr /i "acknowledged" "%TEMP%\bridge_test.tmp" >nul && (
    call :log "✅ GPT → Bridge → ACC working perfectly now."
    echo.
    echo ✅ All systems functional. Monitoring continues.
    echo.
    timeout /t 120 >nul
    goto MAIN_LOOP
)

:: Firebase check (Firestore)
call :log "📡 Checking Firestore connectivity..."
gcloud firestore databases describe --project=%PROJECT_ID% >> "%LOGFILE%" 2>&1 || call :log "⚠️ Firestore unreachable. Check IAM or API enablement."

:: Unknown state → redeploy fallback
call :log "⚠️ Unknown state detected. Redeploying Bridge as fallback..."
:REDEPLOY_BRIDGE
gcloud run deploy %BRIDGE_SERVICE% --source=. --region=%REGION% --project=%PROJECT_ID% --clear-base-image --memory=%MEMORY% --timeout=%TIMEOUT% --concurrency=%CONCURRENCY% --set-env-vars ACC_URL=%ACC_URL%,GPT_TOKEN=%GPT_TOKEN% --quiet >> "%LOGFILE%" 2>&1

timeout /t 30 >nul
goto MAIN_LOOP

:: ===========================================================
:: FUNCTIONS
:: ===========================================================
:fix_iam
call :log "🔒 Fixing IAM bindings..."
gcloud run services add-iam-policy-binding %ACC_SERVICE% --member=serviceAccount:%BRIDGE_SA% --role=roles/run.invoker --region=%REGION% --project=%PROJECT_ID% >nul 2>&1
gcloud run services add-iam-policy-binding %BRIDGE_SERVICE% --member=user:%ADMIN_EMAIL% --role=roles/run.invoker --region=%REGION% --project=%PROJECT_ID% >nul 2>&1
gcloud secrets add-iam-policy-binding %SECRET_NAME% --member=serviceAccount:%BRIDGE_SA% --role=roles/secretmanager.secretAccessor --project=%PROJECT_ID% >nul 2>&1
exit /b

:redeploy_acc
call :log "♻️ Redeploying ACC..."
gcloud run deploy %ACC_SERVICE% --source=. --region=%REGION% --project=%PROJECT_ID% --clear-base-image --memory=%MEMORY% --timeout=%TIMEOUT% --concurrency=%CONCURRENCY% --quiet >> "%LOGFILE%" 2>&1
exit /b

:log
echo [%DATE% %TIME%] %~1
echo [%DATE% %TIME%] %~1 >> "%LOGFILE%"
exit /b
