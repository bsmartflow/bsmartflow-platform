@echo off
setlocal ENABLEDELAYEDEXPANSION

:: =======================================================
::   BSMARTFLOW BRIDGE→ACC FINAL ONE-SHOT AUTO REPAIR
::   SAFE + PERSISTENT VERSION (WINDOWS SDK TERMINAL)
:: =======================================================

title BsmartFlow Bridge ↔ ACC Repair (Safe Mode)
color 0A

:: === Survival Settings ===
set SURVIVE_LOOP=1
set EXIT_DELAY=999999

:: === Project Config ===
set PROJECT=bsmartflow-474718
set REGION=asia-south1
set ACC_SERVICE=bsmartflow-acc
set BRIDGE_SERVICE=bsmartflow-acc-bridge
set REPO=bsmartflow-repo
set IMAGE=bridge
set SECRET_NAME=gpt-service-token
set ADMIN_EMAIL=admin@bsmartflow.com
set BRIDGE_SA=bsmartflow-acc-bridge@%PROJECT%.iam.gserviceaccount.com
set ACC_SA=bsmartflow-acc-sa@%PROJECT%.iam.gserviceaccount.com
set MEMORY=1Gi
set TIMEOUT=600s
set CONCURRENCY=80
set BASE_DIR=%CD%

echo =====================================================
echo [INIT] SAFE MODE ACTIVE — Window will NOT close.
echo =====================================================

echo [1/12] Configuring project context...
gcloud config set project %PROJECT% --quiet
gcloud config set run/region %REGION% --quiet

echo [2/12] Resolving ACC URL...
for /f "usebackq tokens=*" %%A in (`gcloud run services describe %ACC_SERVICE% --project=%PROJECT% --region=%REGION% --format="value(status.url)" 2^>nul`) do set ACC_URL=%%A
if "%ACC_URL%"=="" (
  echo ❌ ERROR: ACC URL not found! Please check Cloud Run.
  goto survive
)
echo ✅ ACC_URL=%ACC_URL%

echo [3/12] Rotating GPT secret token...
for /f "usebackq tokens=*" %%T in (`powershell -NoProfile -Command "[guid]::NewGuid().ToString('N')"`) do set GPT_TOKEN=%%T
echo %GPT_TOKEN% > "%TEMP%\gpt_token.txt"
gcloud secrets describe %SECRET_NAME% --project=%PROJECT% >nul 2>nul || (
  gcloud secrets create %SECRET_NAME% --replication-policy="automatic" --project=%PROJECT% --quiet
)
gcloud secrets versions add %SECRET_NAME% --data-file="%TEMP%\gpt_token.txt" --project=%PROJECT% --quiet
del "%TEMP%\gpt_token.txt"
echo 🔁 Secret rotated successfully.

echo [4/12] Updating IAM bindings (Bridge ↔ ACC)...
gcloud run services add-iam-policy-binding %ACC_SERVICE% --region=%REGION% --project=%PROJECT% --member="serviceAccount:%BRIDGE_SA%" --role="roles/run.invoker" --quiet
gcloud run services add-iam-policy-binding %ACC_SERVICE% --region=%REGION% --project=%PROJECT% --member="user:%ADMIN_EMAIL%" --role="roles/run.invoker" --quiet
gcloud run services add-iam-policy-binding %BRIDGE_SERVICE% --region=%REGION% --project=%PROJECT% --member="user:%ADMIN_EMAIL%" --role="roles/run.invoker" --quiet

echo [5/12] Authenticate Docker for Artifact Registry...
gcloud auth configure-docker %REGION%-docker.pkg.dev --quiet >nul

set IMAGE_URI=%REGION%-docker.pkg.dev/%PROJECT%/%REPO%/%IMAGE%:latest
echo [6/12] Building container %IMAGE_URI% ...
gcloud builds submit "%BASE_DIR%\bridge" --tag=%IMAGE_URI% --project=%PROJECT% --quiet
if %ERRORLEVEL% NEQ 0 (
  echo ❌ ERROR: Container build failed. Review logs and retry.
  goto survive
)
echo ✅ Build success.

echo [7/12] Deploying Bridge...
gcloud run deploy %BRIDGE_SERVICE% --image=%IMAGE_URI% --region=%REGION% --project=%PROJECT% --memory=%MEMORY% --timeout=%TIMEOUT% --concurrency=%CONCURRENCY% --set-env-vars=ACC_URL=%ACC_URL%,GPT_TOKEN=%GPT_TOKEN% --service-account=%BRIDGE_SA% --quiet
if %ERRORLEVEL% NEQ 0 (
  echo ❌ ERROR: Bridge deployment failed. Gathering logs...
  gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=%BRIDGE_SERVICE%" --project=%PROJECT% --limit=100 --freshness=20m --format="value(textPayload)"
  goto survive
)
echo ✅ Bridge deployed successfully.

for /f "usebackq tokens=*" %%B in (`gcloud run services describe %BRIDGE_SERVICE% --project=%PROJECT% --region=%REGION% --format="value(status.url)"`) do set BRIDGE_URL=%%B
echo 🌐 BRIDGE_URL=%BRIDGE_URL%

echo [8/12] Testing Bridge → ACC connection...
curl -s -X POST "%BRIDGE_URL%/gpt-connect" ^
  -H "Authorization: Bearer %GPT_TOKEN%" ^
  -H "Content-Type: application/json" ^
  -d "{\"command\":\"ping_acc\"}" > "%TEMP%\bridge_test.json" 2>&1
type "%TEMP%\bridge_test.json"
findstr /i "unauthorized" "%TEMP%\bridge_test.json" >nul
if %ERRORLEVEL% EQU 0 (
  echo ⚠ Still Unauthorized — token or IAM mismatch.
  gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=%BRIDGE_SERVICE%" --project=%PROJECT% --limit=50 --freshness=30m --format="value(textPayload)"
  gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=%ACC_SERVICE%" --project=%PROJECT% --limit=50 --freshness=30m --format="value(textPayload)"
) else (
  echo ✅ Bridge successfully connected to ACC.
)

echo [9/12] Checking ACC Health...
for /f "usebackq tokens=*" %%T in (`gcloud auth print-identity-token`) do set IDTOKEN=%%T
curl -s -H "Authorization: Bearer %IDTOKEN%" "%ACC_URL%/" > "%TEMP%\acc_health.json" 2>&1
type "%TEMP%\acc_health.json"

echo [10/12] Summarizing IAM bindings...
echo --- ACC ---
gcloud run services get-iam-policy %ACC_SERVICE% --project=%PROJECT% --region=%REGION% --format="value(bindings)"
echo --- BRIDGE ---
gcloud run services get-iam-policy %BRIDGE_SERVICE% --project=%PROJECT% --region=%REGION% --format="value(bindings)"

echo [11/12] Review completed.
echo [12/12] System will remain open for analysis.

:: =======================================================
:survive
echo -------------------------------------------------------
echo 🛠  Script finished or interrupted.
echo ⚙  Terminal will remain alive for manual analysis.
echo ⏱  Sleeping indefinitely... (type CTRL+C then EXIT to quit)
echo -------------------------------------------------------
timeout /t %EXIT_DELAY% >nul
goto survive

