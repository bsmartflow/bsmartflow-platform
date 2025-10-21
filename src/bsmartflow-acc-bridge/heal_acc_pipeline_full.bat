@echo off
setlocal enabledelayedexpansion
title BsmartFlow ACC Full Auto-Heal Deployment
echo ============================================
echo 🚀 BsmartFlow ACC Full Auto-Heal Deployment
echo ============================================

set PROJECT_ID=bsmartflow-474718
set REGION=asia-south1
set SERVICE_NAME=bsmartflow-acc
set REPO_NAME=bsmartflow-repo
set IMAGE_NAME=asia-south1-docker.pkg.dev/%PROJECT_ID%/%REPO_NAME%/%SERVICE_NAME%:latest

echo.
echo [1/6] Enabling Artifact Registry API...
gcloud services enable artifactregistry.googleapis.com --project=%PROJECT_ID%

echo.
echo [2/6] Creating Artifact Registry repo (if not exists)...
gcloud artifacts repositories create %REPO_NAME% ^
  --repository-format=docker ^
  --location=%REGION% ^
  --description="Docker repo for BsmartFlow ACC" ^
  --project=%PROJECT_ID% ^
  --quiet 2>nul || echo Repository already exists.

echo.
echo [3/6] Granting Artifact Registry writer role to Cloud Build service account...
gcloud projects add-iam-policy-binding %PROJECT_ID% ^
  --member="serviceAccount:%PROJECT_ID%@cloudbuild.gserviceaccount.com" ^
  --role="roles/artifactregistry.writer" ^
  --quiet

echo.
echo [4/6] Cleaning old build cache...
gcloud builds submit --project=%PROJECT_ID% --region=%REGION% --no-source --timeout=300s || echo (No previous cache found.)

echo.
echo [5/6] Redeploying to Cloud Run...
gcloud run deploy %SERVICE_NAME% ^
  --region=%REGION% ^
  --project=%PROJECT_ID% ^
  --source=. ^
  --memory=1Gi ^
  --timeout=600s ^
  --allow-unauthenticated ^
  --no-cache ^
  --image=%IMAGE_NAME% ^
  --quiet

echo.
echo [6/6] Checking Service Health...
for /f "delims=" %%i in ('gcloud run services describe %SERVICE_NAME% --region=%REGION% --project=%PROJECT_ID% --format="value(status.url)"') do set ACC_URL=%%i
echo ✅ Service URL: %ACC_URL%
echo Running Health Check...
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" %ACC_URL%/

echo.
echo ============================================
echo ✅ Deployment & Auto-Heal Completed.
echo ============================================
pause

