@echo off
title BsmartFlow ACC Auto-Heal (Final Stable)
echo =====================================================
echo  BsmartFlow ACC Auto-Heal and Health Validator
echo =====================================================
echo Project: bsmartflow-474718
echo Region : asia-south1
echo -----------------------------------------------------

set PROJECT=bsmartflow-474718
set REGION=asia-south1
set SERVICE=bsmartflow-acc
set BRIDGE_SA=bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.com
set ACC_URL=https://bsmartflow-acc-147849918817.asia-south1.run.app
set LOGFILE=acc_autoheal_log.txt
set RETRY_DELAY=60

echo [INIT] Started at %date% %time% > "%LOGFILE%"
echo Checking health endpoint...

:LOOP
for /f %%A in ('curl -s -o nul -w "%%{http_code}" %ACC_URL%/health') do set STATUS=%%A
echo HTTP Status: %STATUS%

if "%STATUS%"=="200" goto HEALTHY
if "%STATUS%"=="403" goto REPAIR_IAM
if "%STATUS%"=="401" goto REPAIR_IAM
if "%STATUS%"=="404" goto REDEPLOY
if "%STATUS%"=="000" goto REDEPLOY
echo Unknown status (%STATUS%), forcing redeploy...
goto REDEPLOY

:REDEPLOY
echo ------------------------------------------------------
echo Redeploying ACC service...
echo ------------------------------------------------------
echo [%time%] Redeploy triggered (%STATUS%) >> "%LOGFILE%"

gcloud run deploy %SERVICE% --source . --region=%REGION% --project=%PROJECT% --memory=1Gi --timeout=900s --concurrency=80 --service-account=bsmartflow-474718@appspot.gserviceaccount.com --quiet >> "%LOGFILE%" 2>&1

echo [%time%] Redeployment completed. Waiting %RETRY_DELAY%s >> "%LOGFILE%"
timeout /t %RETRY_DELAY% >nul
goto LOOP

:REPAIR_IAM
echo ------------------------------------------------------
echo Repairing IAM permissions (roles/run.invoker)...
echo ------------------------------------------------------
echo [%time%] IAM fix triggered (%STATUS%) >> "%LOGFILE%"

gcloud run services add-iam-policy-binding %SERVICE% --region=%REGION% --project=%PROJECT% --member="serviceAccount:%BRIDGE_SA%" --role="roles/run.invoker" >> "%LOGFILE%" 2>&1

echo IAM fixed. Waiting %RETRY_DELAY%s...
timeout /t %RETRY_DELAY% >nul
goto LOOP

:HEALTHY
echo ------------------------------------------------------
echo ACC service is healthy. Verifying Bridge→ACC communication...
echo ------------------------------------------------------
echo [%time%] ACC healthy (HTTP 200) >> "%LOGFILE%"

for /f %%B in ('gcloud auth print-identity-token --impersonate-service-account=%BRIDGE_SA% --project=%PROJECT%') do set TOKEN=%%B

curl -s -X POST %ACC_URL%/execute_task -H "Authorization: Bearer %TOKEN%" -H "Content-Type: application/json" -d "{\"ping\":\"autoheal_check\"}" > resp.json

find /I "ACC executed successfully" resp.json >nul
if %errorlevel%==0 (
  echo ✅ ACC communication verified successfully!
  echo [%time%] Bridge communication OK >> "%LOGFILE%"
  del resp.json
  echo.
  echo SYSTEM HEALTHY AND STABLE.
  pause
  exit /b
)

echo Bridge→ACC test failed, reattempting...
del resp.json
timeout /t %RETRY_DELAY% >nul
goto REDEPLOY
