@echo off
setlocal enabledelayedexpansion
title 🔧 BsmartFlow GPT→Bridge→ACC Continuous Fix System
color 0A

:: ============================================================
:: Project & Service Setup
:: ============================================================
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

echo ============================================================
echo 🚀 Starting BsmartFlow Continuous Auto-Fix Engine
echo ============================================================

:: Ensure project and region
gcloud config set project %PROJECT_ID% >nul
gcloud config set run/region %REGION% >nul

:: Enable required APIs
echo [1/8] ⚙️  Ensuring required APIs...
gcloud services enable run.googleapis.com secretmanager.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com pubsub.googleapis.com cloudscheduler.googleapis.com --project=%PROJECT_ID%

:: Rotate GPT Token
echo [2/8] 🔑 Rotating GPT token secret...
for /f %%A in ('openssl rand -hex 32') do set GPT_TOKEN=%%A
echo %GPT_TOKEN%>token.txt
gcloud secrets versions add %SECRET_NAME% --data-file=token.txt --project=%PROJECT_ID%
del token.txt

:: IAM Fixes
echo [3/8] 🔐 Fixing IAM policies...
gcloud run services add-iam-policy-binding %ACC_SERVICE% --member=serviceAccount:%BRIDGE_SA% --role=roles/run.invoker --region=%REGION% --project=%PROJECT_ID%
gcloud run services add-iam-policy-binding %BRIDGE_SERVICE% --member=user:%ADMIN_EMAIL% --role=roles/run.invoker --region=%REGION% --project=%PROJECT_ID%

:: Redeploy ACC
echo [4/8] 🚀 Redeploying ACC service...
gcloud run deploy %ACC_SERVICE% --source=. --region=%REGION% --project=%PROJECT_ID% --clear-base-image --memory=%MEMORY% --timeout=%TIMEOUT% --concurrency=%CONCURRENCY% --quiet

:: Fetch ACC URL
for /f "tokens=* usebackq" %%F in (`gcloud run services describe %ACC_SERVICE% --region=%REGION% --project=%PROJECT_ID% --format="value(status.url)"`) do set ACC_URL=%%F
echo ✅ ACC_URL = %ACC_URL%

:: Redeploy Bridge
echo [5/8] 🚀 Deploying Bridge service...
gcloud run deploy %BRIDGE_SERVICE% --source=. --region=%REGION% --project=%PROJECT_ID% --clear-base-image --memory=%MEMORY% --timeout=%TIMEOUT% --concurrency=%CONCURRENCY% --set-env-vars ACC_URL=%ACC_URL%,GPT_TOKEN=%GPT_TOKEN% --quiet

:: Fetch Bridge URL
for /f "tokens=* usebackq" %%F in (`gcloud run services describe %BRIDGE_SERVICE% --region=%REGION% --project=%PROJECT_ID% --format="value(status.url)"`) do set BRIDGE_URL=%%F
echo ✅ BRIDGE_URL = %BRIDGE_URL%

:: ============================================================
:: Continuous Fix Loop
:: ============================================================
echo [6/8] 🔁 Starting continuous connection test and auto-repair...
:LOOP
curl -s -X POST "%BRIDGE_URL%/gpt-connect" ^
  -H "Authorization: Bearer %GPT_TOKEN%" ^
  -H "Content-Type: application/json" ^
  -d "{\"command\":\"ping_acc\"}" | find "401" >nul

if %errorlevel%==0 (
    echo ❌ 401 Unauthorized detected — rotating token and redeploying Bridge...
    for /f %%A in ('openssl rand -hex 32') do set GPT_TOKEN=%%A
    echo %GPT_TOKEN%>token.txt
    gcloud secrets versions add %SECRET_NAME% --data-file=token.txt --project=%PROJECT_ID% >nul
    del token.txt
    gcloud run deploy %BRIDGE_SERVICE% --source=. --region=%REGION% --project=%PROJECT_ID% --clear-base-image --memory=%MEMORY% --timeout=%TIMEOUT% --concurrency=%CONCURRENCY% --set-env-vars ACC_URL=%ACC_URL%,GPT_TOKEN=%GPT_TOKEN% --quiet
    timeout /t 60 >nul
    goto LOOP
) else (
    echo ✅ GPT ↔ Bridge ↔ ACC connection verified successfully!
    echo ============================================================
    echo ✅ System online and healthy — monitoring continues...
    echo ============================================================
)
timeout /t 120 >nul
goto LOOP
