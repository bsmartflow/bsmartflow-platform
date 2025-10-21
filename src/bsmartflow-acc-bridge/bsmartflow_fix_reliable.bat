@echo off
echo ============================================================
echo 🚀 BsmartFlow 401 Authentication Repair (Windows CMD Safe)
echo ============================================================

REM --- CONFIGURATION ---
set PROJECT_ID=bsmartflow-474718
set REGION=asia-south1
set ACC_SERVICE=bsmartflow-acc
set BRIDGE_SERVICE=bsmartflow-acc-bridge
set SECRET_NAME=gpt-service-token
set BRIDGE_SA=bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.com

echo.
echo [1/5] Setting Google Cloud context...
gcloud config set project %PROJECT_ID%
gcloud config set run/region %REGION%

echo.
echo [2/5] Rotating GPT token and fixing secret access...
for /f "tokens=*" %%T in ('openssl rand -hex 32') do set GPT_TOKEN=%%T
echo %GPT_TOKEN% > gpt_token.txt
gcloud secrets versions add %SECRET_NAME% --data-file=gpt_token.txt --project=%PROJECT_ID%
del gpt_token.txt
gcloud secrets add-iam-policy-binding %SECRET_NAME% ^
  --member="serviceAccount:%BRIDGE_SA%" ^
  --role="roles/secretmanager.secretAccessor" ^
  --project=%PROJECT_ID%

echo.
echo [3/5] Fixing IAM between Bridge and ACC...
gcloud run services add-iam-policy-binding %ACC_SERVICE% ^
  --member="serviceAccount:%BRIDGE_SA%" ^
  --role="roles/run.invoker" ^
  --region=%REGION% ^
  --project=%PROJECT_ID%

echo.
echo [4/5] Getting ACC URL...
for /f "tokens=* usebackq" %%A in (`gcloud run services describe %ACC_SERVICE% --region=%REGION% --project=%PROJECT_ID% --format="value(status.url)"`) do set ACC_URL=%%A
echo ✅ ACC_URL = %ACC_URL%

echo.
echo [5/5] Redeploying Bridge with correct environment...
gcloud run deploy %BRIDGE_SERVICE% ^
  --region=%REGION% ^
  --project=%PROJECT_ID% ^
  --set-env-vars=ACC_URL=%ACC_URL%,GPT_TOKEN=%GPT_TOKEN% ^
  --memory=1Gi ^
  --timeout=600s ^
  --concurrency=80 ^
  --quiet

echo.
echo 🌐 Testing connection Bridge → ACC ...
curl -X POST "%ACC_URL%/execute_task" ^
  -H "Authorization: Bearer %GPT_TOKEN%" ^
  -H "Content-Type: application/json" ^
  -d "{\"ping\":\"ok\"}"

echo.
echo ============================================================
echo ✅ Repair Attempt Complete — Check for HTTP 200 OK Response
echo ============================================================
pause
