@echo off
title 🚀 BsmartFlow ACC + Bridge Auto-Deploy + Health Cycle
echo ======================================================
echo 🚀 Starting BsmartFlow ACC + Bridge Deployment Cycle
echo ======================================================

REM === 1️⃣ Environment Setup ===
set PROJECT_ID=bsmartflow-474718
set REGION=asia-south1
set ACC_SERVICE=bsmartflow-acc
set BRIDGE_SERVICE=bsmartflow-acc-bridge
set ACC_URL=https://bsmartflow-acc-147849918817.asia-south1.run.app
set BRIDGE_URL=https://bsmartflow-acc-bridge-147849918817.asia-south1.run.app
set SERVICE_ACCOUNT=bsmartflow-474718@appspot.gserviceaccount.com

echo ✅ Project: %PROJECT_ID%
echo ✅ Region:  %REGION%
echo ✅ ACC:     %ACC_SERVICE%
echo ✅ Bridge:  %BRIDGE_SERVICE%
echo.

REM === 2️⃣ Verify gcloud SDK ===
echo Checking gcloud SDK...
gcloud --version >nul 2>&1 || (
    echo ❌ Google Cloud SDK not found!
    echo Please install from https://cloud.google.com/sdk/docs/install
    pause
    exit /b
)
echo ✅ gcloud SDK OK
echo.

REM === 3️⃣ Deploy ACC ===
echo 🔄 Building and deploying ACC service...
gcloud run deploy %ACC_SERVICE% ^
  --source . ^
  --region=%REGION% ^
  --project=%PROJECT_ID% ^
  --memory=1Gi ^
  --timeout=900s ^
  --concurrency=80 ^
  --service-account=%SERVICE_ACCOUNT% ^
  --quiet

if errorlevel 1 (
    echo ❌ ACC deployment failed!
    pause
    exit /b
)
echo ✅ ACC deployment succeeded!
echo.

REM === 4️⃣ Deploy Bridge ===
echo 🔄 Deploying Bridge service...
gcloud run deploy %BRIDGE_SERVICE% ^
  --image=asia-south1-docker.pkg.dev/%PROJECT_ID%/bsmartflow-repo/bsmartflow-acc-bridge:latest ^
  --region=%REGION% ^
  --project=%PROJECT_ID% ^
  --memory=1Gi ^
  --timeout=600s ^
  --concurrency=80 ^
  --set-env-vars=ACC_URL=%ACC_URL%,GPT_TOKEN=test123 ^
  --service-account=%SERVICE_ACCOUNT% ^
  --quiet

if errorlevel 1 (
    echo ❌ Bridge deployment failed!
    pause
    exit /b
)
echo ✅ Bridge deployment succeeded!
echo.

REM === 5️⃣ Grant IAM permissions (Bridge can call ACC)
echo 🔐 Updating IAM policy for ACC (allow Bridge to invoke)...
gcloud run services add-iam-policy-binding %ACC_SERVICE% ^
  --region=%REGION% ^
  --project=%PROJECT_ID% ^
  --member="serviceAccount:%BRIDGE_SERVICE%@%PROJECT_ID%.iam.gserviceaccount.com" ^
  --role="roles/run.invoker" ^
  --quiet
echo ✅ IAM permissions updated!
echo.

REM === 6️⃣ Test ACC endpoints ===
echo 🌐 Testing ACC endpoints...
for %%E in ("/" "/health" "/api/health" "/acc/health" "/_internal/live") do (
    echo ------------------------------------------------------
    echo 🔎 Testing: %ACC_URL%%%E
    curl -I %ACC_URL%%%E
)
echo.

REM === 7️⃣ Test Bridge → ACC connection ===
echo 🔄 Testing Bridge → ACC connectivity...
curl -X POST "%BRIDGE_URL%/execute_task" ^
    -H "Authorization: Bearer test123" ^
    -H "Content-Type: application/json" ^
    -d "{\"ping\":\"ok\"}"
echo.

REM === 8️⃣ Health Retry Loop (auto-heal if needed) ===
echo ♻️  Monitoring health... (will retry 3 times if 404/401)
set /a retries=0
:retry_loop
curl -I %ACC_URL%/health | find "200 OK" >nul
if %errorlevel%==0 (
    echo ✅ ACC Healthy!
    goto healthy
)
set /a retries+=1
if %retries% GTR 3 (
    echo ❌ ACC still unhealthy after 3 retries.
    goto done
)
echo ⚠️ Health not ready yet. Retrying in 20s...
timeout /t 20 /nobreak >nul
goto retry_loop

:healthy
echo ======================================================
echo ✅ ACC + Bridge Deployed & Verified Successfully!
echo 🌍 ACC: %ACC_URL%
echo 🌉 Bridge: %BRIDGE_URL%
echo ======================================================

:done
pause
exit /b
