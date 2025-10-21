@echo off
echo ============================================================
echo 🚀 BsmartFlow 401 FINAL AUTH FIX (Windows SDK - IMAGE MODE)
echo ============================================================

set PROJECT_ID=bsmartflow-474718
set REGION=asia-south1
set ACC_SERVICE=bsmartflow-acc
set BRIDGE_SERVICE=bsmartflow-acc-bridge
set SECRET_NAME=gpt-service-token
set BRIDGE_SA=bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.com
set ACC_URL=https://bsmartflow-acc-147849918817.asia-south1.run.app
set IMAGE=gcr.io/bsmartflow-474718/bsmartflow-acc-bridge:latest

echo.
echo [1/4] Setting Cloud context...
gcloud config set project %PROJECT_ID%
gcloud config set run/region %REGION%

echo.
echo [2/4] Rotating GPT token and fixing secret IAM...
for /f "tokens=*" %%T in ('openssl rand -hex 32') do set GPT_TOKEN=%%T
echo %GPT_TOKEN%> gpt_token.txt
gcloud secrets versions add %SECRET_NAME% --data-file=gpt_token.txt --project=%PROJECT_ID%
del gpt_token.txt
gcloud secrets add-iam-policy-binding %SECRET_NAME% --member="serviceAccount:%BRIDGE_SA%" --role="roles/secretmanager.secretAccessor" --project=%PROJECT_ID%

echo.
echo [3/4] Fixing IAM policies Bridge -> ACC...
gcloud run services add-iam-policy-binding %ACC_SERVICE% --member="serviceAccount:%BRIDGE_SA%" --role="roles/run.invoker" --region=%REGION% --project=%PROJECT_ID%

echo.
echo [4/4] Redeploying Bridge from image...
gcloud run deploy %BRIDGE_SERVICE% --image=%IMAGE% --region=%REGION% --project=%PROJECT_ID% --set-env-vars=ACC_URL=%ACC_URL%,GPT_TOKEN=%GPT_TOKEN% --memory=1Gi --timeout=600s --concurrency=80 --allow-unauthenticated --quiet

echo.
echo 🌐 Testing secure call Bridge → ACC ...
curl -X POST "%ACC_URL%/execute_task" -H "Authorization: Bearer %GPT_TOKEN%" -H "Content-Type: application/json" -d "{\"ping\":\"ok\"}"

echo.
echo ============================================================
echo ✅ DONE — EXPECT HTTP 200 OK IF FIXED
echo ============================================================
pause
