@echo off
echo ============================================================
echo 🚀 BsmartFlow 401 FINAL FIX (Pure Windows SDK - CMD Safe)
echo ============================================================

set PROJECT_ID=bsmartflow-474718
set REGION=asia-south1
set ACC_SERVICE=bsmartflow-acc
set BRIDGE_SERVICE=bsmartflow-acc-bridge
set SECRET_NAME=gpt-service-token
set BRIDGE_SA=bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.com
set ACC_URL=https://bsmartflow-acc-147849918817.asia-south1.run.app
set IMAGE=gcr.io/bsmartflow-474718/bsmartflow-acc-bridge:latest

echo [1/5] Setting project and region...
gcloud config set project %PROJECT_ID%
gcloud config set run/region %REGION%

echo [2/5] Rotating GPT token...
for /f %%T in ('openssl rand -hex 32') do set GPT_TOKEN=%%T
echo %GPT_TOKEN% > gpt_token.txt
gcloud secrets versions add %SECRET_NAME% --data-file=gpt_token.txt --project=%PROJECT_ID%
del gpt_token.txt
gcloud secrets add-iam-policy-binding %SECRET_NAME% --member="serviceAccount:%BRIDGE_SA%" --role="roles/secretmanager.secretAccessor" --project=%PROJECT_ID%

echo [3/5] Fixing IAM permissions...
gcloud run services add-iam-policy-binding %ACC_SERVICE% --member="serviceAccount:%BRIDGE_SA%" --role="roles/run.invoker" --region=%REGION% --project=%PROJECT_ID%

echo [4/5] Redeploying Bridge service...
gcloud run deploy %BRIDGE_SERVICE% --image=%IMAGE% --region=%REGION% --project=%PROJECT_ID% --set-env-vars ACC_URL=%ACC_URL%,GPT_TOKEN=%GPT_TOKEN% --memory 1Gi --timeout 600s --concurrency 80 --allow-unauthenticated --quiet

echo [5/5] Testing Bridge → ACC connection...
curl -X POST "%ACC_URL%/execute_task" -H "Authorization: Bearer %GPT_TOKEN%" -H "Content-Type: application/json" -d "{\"ping\":\"ok\"}"

echo ============================================================
echo ✅ Script completed. Look for HTTP 200 or JSON reply.
echo ============================================================
pause
