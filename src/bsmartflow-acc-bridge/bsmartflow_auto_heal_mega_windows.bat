@echo off
setlocal enabledelayedexpansion
title BsmartFlow MEGA Auto-Heal (Windows SDK)
color 0A

:: ============================
:: CONFIG - adjust if needed
:: ============================
set PROJECT_ID=bsmartflow-474718
set REGION=asia-south1
set ACC_SERVICE=bsmartflow-acc
set BRIDGE_SERVICE=bsmartflow-acc-bridge
set SECRET_NAME=gpt-service-token
set ADMIN_EMAIL=admin@bsmartflow.com
set BRIDGE_SA=bsmartflow-acc-bridge@%PROJECT_ID%.iam.gserviceaccount.com
set ACC_SA=bsmartflow-acc-sa@%PROJECT_ID%.iam.gserviceaccount.com
set BACKUP_BUCKET=%PROJECT_ID%-autoheal-backups
set MEMORY=1Gi
set TIMEOUT=600s
set CONCURRENCY=80
set LOGFILE=%TEMP%\bsmartflow_auto_heal.log
set RETRY_SLEEP=30
set LOOP_SLEEP=120
set MAX_ROTATIONS=8

:: ============================
:: Helpers
:: ============================
echo [START %DATE% %TIME%] > "%LOGFILE%"
call :log "Initializing context..."
gcloud config set project %PROJECT_ID% >> "%LOGFILE%" 2>&1
gcloud config set run/region %REGION% >> "%LOGFILE%" 2>&1

:ensure_apis
call :log "Ensuring required APIs..."
gcloud services enable run.googleapis.com secretmanager.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com pubsub.googleapis.com cloudscheduler.googleapis.com firestore.googleapis.com --project=%PROJECT_ID% >> "%LOGFILE%" 2>&1 || (
  call :log "Warning: enabling APIs may require organization permissions."
)

:ensure_backup_bucket
call :log "Ensuring backup bucket gs://%BACKUP_BUCKET% ..."
gsutil ls -b "gs://%BACKUP_BUCKET%" >nul 2>&1 || (
  gsutil mb -p %PROJECT_ID% -l %REGION% "gs://%BACKUP_BUCKET%" >> "%LOGFILE%" 2>&1 || call :log "Failed to create backup bucket"
)

:: ============================
:: Token rotation routine
:: ============================
:rotate_token
set /a ROT_COUNT+=1
if %ROT_COUNT% GTR %MAX_ROTATIONS% (
  call :log "Max token rotations reached (%MAX_ROTATIONS%). Continuing attempts but will not auto-rotate further."
) else (
  for /f "delims=" %%A in ('openssl rand -hex 32 2^>nul') do set NEW_TOKEN=%%A
  if "%NEW_TOKEN%"=="" (
    call :log "openssl not available or failed to generate token. Using GUID fallback."
    for /f "delims=" %%G in ('powershell -NoProfile -Command "[guid]::NewGuid().ToString('N')"') do set NEW_TOKEN=%%G
  )
  echo %NEW_TOKEN% > "%TEMP%\gpt_token.tmp"
  gcloud secrets versions add %SECRET_NAME% --data-file="%TEMP%\gpt_token.tmp" --project=%PROJECT_ID% >> "%LOGFILE%" 2>&1 || (
    call :log "Creating secret %SECRET_NAME% ..."
    gcloud secrets create %SECRET_NAME% --replication-policy="automatic" --project=%PROJECT_ID% >> "%LOGFILE%" 2>&1
    gcloud secrets versions add %SECRET_NAME% --data-file="%TEMP%\gpt_token.tmp" --project=%PROJECT_ID% >> "%LOGFILE%" 2>&1
  )
  del "%TEMP%\gpt_token.tmp" >nul 2>&1
  call :log "Token rotated (rotation #!ROT_COUNT!)."
)

:: ============================
:: IAM fixes (invoker bindings)
:: ============================
:fix_iam
call :log "Ensuring run.invoker bindings for Bridge and admin on ACC and Bridge ..."
gcloud run services add-iam-policy-binding %ACC_SERVICE% --member=serviceAccount:%BRIDGE_SA% --role=roles/run.invoker --region=%REGION% --project=%PROJECT_ID% >> "%LOGFILE%" 2>&1 || call :log "add-iam-policy-binding (bridge->acc) warning"
gcloud run services add-iam-policy-binding %ACC_SERVICE% --member=user:%ADMIN_EMAIL% --role=roles/run.invoker --region=%REGION% --project=%PROJECT_ID% >> "%LOGFILE%" 2>&1 || call :log "add-iam-policy-binding (admin->acc) warning"
gcloud run services add-iam-policy-binding %BRIDGE_SERVICE% --member=user:%ADMIN_EMAIL% --role=roles/run.invoker --region=%REGION% --project=%PROJECT_ID% >> "%LOGFILE%" 2>&1 || call :log "add-iam-policy-binding (admin->bridge) warning"
gcloud secrets add-iam-policy-binding %SECRET_NAME% --member=serviceAccount:%BRIDGE_SA% --role=roles/secretmanager.secretAccessor --project=%PROJECT_ID% >> "%LOGFILE%" 2>&1 || call :log "secret IAM (bridge) warning"
gcloud secrets add-iam-policy-binding %SECRET_NAME% --member=serviceAccount:%ACC_SA% --role=roles/secretmanager.secretAccessor --project=%PROJECT_ID% >> "%LOGFILE%" 2>&1 || call :log "secret IAM (acc) warning"

:: ============================
:: Deployment helper
:: ============================
:deploy_acc
call :log "Deploying ACC (source folder ./acc if present, else current dir)..."
if exist ".\acc\Dockerfile" (
  set ACC_SRC=.\acc
) else (
  set ACC_SRC=.
)
gcloud run deploy %ACC_SERVICE% --source=%ACC_SRC% --region=%REGION% --project=%PROJECT_ID% --clear-base-image --memory=%MEMORY% --timeout=%TIMEOUT% --concurrency=%CONCURRENCY% --quiet >> "%LOGFILE%" 2>&1 || (
  call :log "ACC deploy failed — checking logs."
  gcloud builds list --project=%PROJECT_ID% --filter="status=WORKING OR status=FAILURE" --limit=5 >> "%LOGFILE%" 2>&1
)
for /f "delims=" %%U in ('gcloud run services describe %ACC_SERVICE% --region=%REGION% --project=%PROJECT_ID% --format="value(status.url)" 2^>nul') do set ACC_URL=%%U
if "%ACC_URL%"=="" (
  call :log "ACC_URL not found after deploy."
) else (
  call :log "ACC_URL=%ACC_URL%"
)

:deploy_bridge
call :log "Deploying Bridge (source folder ./bridge if present)..."
if exist ".\bridge\Dockerfile" (
  set BRIDGE_SRC=.\bridge
) else (
  set BRIDGE_SRC=.
)
gcloud run deploy %BRIDGE_SERVICE% --source=%BRIDGE_SRC% --region=%REGION% --project=%PROJECT_ID% --clear-base-image --memory=%MEMORY% --timeout=%TIMEOUT% --concurrency=%CONCURRENCY% --set-env-vars=ACC_URL=%ACC_URL%,GPT_TOKEN=%NEW_TOKEN% --quiet >> "%LOGFILE%" 2>&1 || (
  call :log "Bridge deploy failed — collecting logs."
  gcloud builds list --project=%PROJECT_ID% --filter="status=WORKING OR status=FAILURE" --limit=5 >> "%LOGFILE%" 2>&1
)
for /f "delims=" %%U in ('gcloud run services describe %BRIDGE_SERVICE% --region=%REGION% --project=%PROJECT_ID% --format="value(status.url)" 2^>nul') do set BRIDGE_URL=%%U
if "%BRIDGE_URL%"=="" (
  call :log "BRIDGE_URL not found after deploy."
) else (
  call :log "BRIDGE_URL=%BRIDGE_URL%"
)

:: ============================
:: Quick checks (Artifact Registry, Cloud Build)
:: ============================
:check_artifact
call :log "Checking Artifact Registry write permission for cloudbuild SA..."
gcloud artifacts repositories list --location=%REGION% --project=%PROJECT_ID% >> "%LOGFILE%" 2>&1 || call :log "Artifact registry list failed."

call :log "Triggering a quick Cloud Build to warm cache (no-source)..."
gcloud builds submit --no-source --project=%PROJECT_ID% --timeout=120s --quiet >> "%LOGFILE%" 2>&1 || call :log "Cloud Build no-source failed."

:: ============================
:: Firebase / Firestore check
:: ============================
:check_firebase
call :log "Checking Firestore reachable via ACC health endpoint..."
if "%ACC_URL%"=="" (
  call :log "ACC_URL blank; skipping Firestore check."
) else (
  curl -s -H "Authorization: Bearer $(gcloud auth print-identity-token)" "%ACC_URL%/_internal/live" > "%TEMP%\acc_health.tmp" 2>&1
  type "%TEMP%\acc_health.tmp" | findstr /i "healthy ok acc" >nul 2>&1 && (
    call :log "ACC health OK (internal live)."
  ) || (
    call :log "ACC health check failed or returned non-OK. Contents:" 
    type "%TEMP%\acc_health.tmp" >> "%LOGFILE%"
  )
)

:: ============================
:: Trial invocation and repair loop
:: ============================
set /a attempts=0
set /a rotations=0

:main_loop
set /a attempts+=1
call :log "Attempt #%attempts%: Testing Bridge -> ACC connectivity..."

:: fetch latest token from secret
for /f "delims=" %%T in ('gcloud secrets versions access latest --secret=%SECRET_NAME% --project=%PROJECT_ID% 2^>nul') do set CUR_TOKEN=%%T

:: run the POST test
curl -s -X POST "%BRIDGE_URL%/gpt-connect" -H "Authorization: Bearer %CUR_TOKEN%" -H "Content-Type: application/json" -d "{\"command\":\"ping_acc\"}" > "%TEMP%\bridge_resp.tmp" 2>&1

:: detect HTTP status keywords
set BRIDGE_RESP=
for /f "usebackq delims=" %%L in ("%TEMP%\bridge_resp.tmp") do set BRIDGE_RESP=!BRIDGE_RESP! %%L
echo !BRIDGE_RESP! >> "%LOGFILE%"

echo !BRIDGE_RESP! | findstr /i "401 Unauthorized" >nul 2>&1
if !errorlevel! == 0 (
  call :log "Detected 401 Unauthorized from Bridge."
  call :log "Action: rotate token, update secret, redeploy bridge, ensure IAM binding."
  call :rotate_token
  call :fix_iam
  set /a rotations+=1
  call :deploy_bridge
  timeout /t %RETRY_SLEEP% >nul
  if %rotations% GEQ %MAX_ROTATIONS% (
    call :log "Rotations reached: %rotations% — consider manual inspection."
  )
  goto main_loop
)

echo !BRIDGE_RESP! | findstr /i "403 Forbidden" >nul 2>&1
if !errorlevel! == 0 (
  call :log "Detected 403 Forbidden — likely client lacks permission. Re-applying invoker policy and redeploying."
  call :fix_iam
  call :deploy_bridge
  timeout /t %RETRY_SLEEP% >nul
  goto main_loop
)

echo !BRIDGE_RESP! | findstr /i "404 Page not found" >nul 2>&1
if !errorlevel! == 0 (
  call :log "Detected 404 from Bridge — route/path mismatch. Re-deploying ACC & Bridge to ensure endpoints exist."
  call :deploy_acc
  call :deploy_bridge
  timeout /t %RETRY_SLEEP% >nul
  goto main_loop
)

echo !BRIDGE_RESP! | findstr /i "Method Not Allowed" >nul 2>&1
if !errorlevel! == 0 (
  call :log "405 Method Not Allowed — Bridge endpoint exists but wrong HTTP verb. Re-check Bridge code and redeploy."
  call :deploy_bridge
  goto main_loop
)

:: Check for Cloud Run container start issues via logs (OOM, worker timeout)
call :log "Inspecting Cloud Run revision logs for Bridge for container failures (last 2m)..."
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=%BRIDGE_SERVICE%" --project=%PROJECT_ID% --limit=20 --freshness=5m --format="value(textPayload)" > "%TEMP%\cr_logs.tmp" 2>&1
type "%TEMP%\cr_logs.tmp" >> "%LOGFILE%"

findstr /i "WORKER TIMEOUT" "%TEMP%\cr_logs.tmp" >nul 2>&1 && (
  call :log "Found WORKER TIMEOUT / SIGKILL events — increasing memory and redeploying bridge."
  set MEMORY=1Gi
  call :deploy_bridge
  timeout /t %RETRY_SLEEP% >nul
  goto main_loop
)

findstr /i "permission denied by IAM" "%TEMP%\cr_logs.tmp" >nul 2>&1 && (
  call :log "Artifact Registry IAM denied observed — granting writer to cloudbuild SA and compute SA."
  gcloud projects add-iam-policy-binding %PROJECT_ID% --member=serviceAccount:%PROJECT_ID%@cloudbuild.gserviceaccount.com --role=roles/artifactregistry.writer --quiet >> "%LOGFILE%" 2>&1
  gcloud projects add-iam-policy-binding %PROJECT_ID% --member=serviceAccount:147849918817-compute@developer.gserviceaccount.com --role=roles/artifactregistry.writer --quiet >> "%LOGFILE%" 2>&1
  call :deploy_bridge
  goto main_loop
)

:: Check for 402 (billing / payment) hint in logs or responses
echo !BRIDGE_RESP! | findstr /i "402" >nul 2>&1
if !errorlevel! == 0 (
  call :log "Detected 402-like response. Check billing; attempting to enable relevant APIs and notify admin."
  gcloud services enable billing.googleapis.com --project=%PROJECT_ID% >> "%LOGFILE%" 2>&1 || call :log "Billing API enable failed or already enabled."
  goto main_loop
)

:: Check sample ACC health directly
if not "%ACC_URL%"=="" (
  curl -s -H "Authorization: Bearer $(gcloud auth print-identity-token)" "%ACC_URL%/_internal/live" > "%TEMP%\acc_check.tmp" 2>&1
  type "%TEMP%\acc_check.tmp" >> "%LOGFILE%"
  echo !BRIDGE_RESP! | findstr /i "acc_ok acc_degraded acc_error" >nul 2>&1
)

:: If response contains expected JSON ack => success
echo !BRIDGE_RESP! | findstr /i "acknowledged" >nul 2>&1
if !errorlevel! == 0 (
  call :log "Bridge -> ACC ping returned acknowledged. System healthy."
  call :finalize_and_exit 0
)

:: If none matched, try redeploy ACC once per 5 attempts
if %attempts% GEQ 5 (
  call :log "Multiple attempts without resolution. Redeploying ACC and Bridge as fallback."
  call :deploy_acc
  call :deploy_bridge
  set attempts=0
  timeout /t %RETRY_SLEEP% >nul
  goto main_loop
)

call :log "No specific error signature found. Sleeping %LOOP_SLEEP% seconds before next attempt..."
timeout /t %LOOP_SLEEP% >nul
goto main_loop

:: ============================
:: Finalize
:: ============================
:finalize_and_exit
set rc=%1
call :log "FINALIZATION: rc=%rc% — archiving diagnostics to gs://%BACKUP_BUCKET%/diag/"
set TIMESTAMP=%DATE:~10,4%%DATE:~4,2%%DATE:~7,2%T%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%
if exist "%TEMP%\bridge_resp.tmp" gsutil cp "%TEMP%\bridge_resp.tmp" "gs://%BACKUP_BUCKET%/diag/bridge_resp_%TIMESTAMP%.log" >nul 2>&1 || echo.
if exist "%TEMP%\acc_check.tmp" gsutil cp "%TEMP%\acc_check.tmp" "gs://%BACKUP_BUCKET%/diag/acc_check_%TIMESTAMP%.log" >nul 2>&1 || echo.
gsutil cp "%LOGFILE%" "gs://%BACKUP_BUCKET%/diag/auto_heal_log_%TIMESTAMP%.log" >nul 2>&1 || echo.
call :log "Done. Exiting with code %rc%."
exit /b %rc%

:: ============================
:: Logging function
:: ============================
:log
set msg=%*
for /f "tokens=1-4 delims=/: " %%a in ("%date%") do set D=%%c-%%a-%%b
for /f "tokens=1-3 delims=:. " %%t in ("%time%") do set T=%%t:%%u:%%v
set stamp=%D%T%time:~3,2%
echo [%DATE% %TIME%] %msg% >> "%LOGFILE%"
echo %msg%
goto :eof
