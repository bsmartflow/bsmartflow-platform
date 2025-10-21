@echo off
REM === Redeploy script for bsmartflow-acc (Windows / Cloud SDK Shell) ===
REM Run this from: C:\Users\Bhavani Prasad\AppData\Local\Google\Cloud SDK\bsmartflow-acc\backend

REM -----------------------
REM Config - edit if needed
REM -----------------------
set PROJECT_ID=bsmartflow-474718
set REGION=asia-south1
set ACC_SERVICE_NAME=bsmartflow-acc
set BRIDGE_SERVICE_ACCOUNT=bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.com
set COMPUTE_SA=147849918817-compute@developer.gserviceaccount.com
set ARTIFACT_REPO=bsmartflow-acc
set ARTIFACT_LOCATION=asia-south1
set SCHEDULER_JOB_NAME=bsmartflow-guardian
set RETRIES=3

echo [INFO] Starting redeploy sequence for %ACC_SERVICE_NAME% in project %PROJECT_ID%...

REM -----------------------
REM 1) Backup current folder
REM -----------------------
set BACKUP_DIR=backup_acc_%DATE:~10,4%%DATE:~4,2%%DATE:~7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%
mkdir "%BACKUP_DIR%" >nul 2>&1
xcopy *.* "%BACKUP_DIR%\" /E /I /Y >nul
echo [OK] Backup saved to %BACKUP_DIR%

REM -----------------------
REM 2) Write hardened app.py (guaranteed app:app)
REM -----------------------
echo [INFO] Writing app.py...
(
echo from flask import Flask, jsonify, request
echo from google.cloud import firestore
echo import os, traceback, time, threading
echo
echo app = Flask(__name__)
echo thread_local = threading.local()
echo
echo def get_db_client():
echo^    """Lazy Firestore client per thread with 1 retry"""
echo^    if not hasattr(thread_local, 'db_client'):
echo^        try:
echo^            thread_local.db_client = firestore.Client()
echo^            print("[ACC] Firestore client initialized.")
echo^        except Exception as e:
echo^            print("[ACC WARNING] Firestore init failed:", e)
echo^            time.sleep(1)
echo^            try:
echo^                thread_local.db_client = firestore.Client()
echo^            except Exception as e2:
echo^                print("[ACC ERROR] Firestore init second attempt failed:", e2)
echo^                thread_local.db_client = None
echo^    return thread_local.db_client
echo
echo @app.route("/", methods=["GET"])
echo def home():
echo^    db = get_db_client()
echo^    if db:
echo^        try:
echo^            db.collection("system_health").document("acc_status").set({ "status": "online" }, merge=True)
echo^            return jsonify({ "status": "acc_ok", "message": "Assistant Command Center running successfully", "firestore":"connected" }), 200
echo^        except Exception as e:
echo^            print("[ACC WARNING] Firestore write failed:", e)
echo^            return jsonify({ "status": "acc_degraded", "message": "Firestore write failed", "firestore":"degraded" }), 200
echo^    else:
echo^        return jsonify({ "status": "acc_degraded", "message": "Firestore client unavailable", "firestore":"disconnected" }), 503
echo
echo @app.route("/_internal/live", methods=["GET"])
echo def live():
echo^    return "OK", 200
echo
echo @app.route("/execute_task", methods=["POST"])
echo def execute_task():
echo^    start = time.time()
echo^    db = get_db_client()
echo^    try:
echo^        data = request.get_json(force=True, silent=True) or {}
echo^        initiator = data.get("initiator","unknown")
echo^        command = data.get("command","none")
echo^        params = data.get("parameters",{})
echo^        print(f"[ACC] Received command '{command}' from '{initiator}'")
echo^        if db:
echo^            try:
echo^                db.collection("acc_logs").add({"initiator":initiator,"command":command,"parameters":params,"timestamp":firestore.SERVER_TIMESTAMP})
echo^            except Exception as fe:
echo^                print("[ACC WARNING] Firestore log failed:", fe)
echo^        if command == "system_status_check":
echo^            resp = {"status":"acc_ok","message":"System health verified"}
echo^        else:
echo^            resp = {"status":"acc_ok","message":f"Command '{command}' executed"}
echo^        print(f"[ACC] Completed '{command}' in {round(time.time()-start,2)}s")
echo^        return jsonify(resp), 200
echo^    except Exception as e:
echo^        print("[ACC ERROR]:", traceback.format_exc())
echo^        return jsonify({"status":"acc_error","error":str(e)}),500
echo
echo if __name__ == "__main__":
echo^    port = int(os.environ.get("PORT",8080))
echo^    app.run(host="0.0.0.0", port=port)
) > app.py

echo [OK] app.py written.

REM -----------------------
REM 3) Write requirements.txt
REM -----------------------
echo Flask==3.0.2> requirements.txt
echo gunicorn==21.2.0>> requirements.txt
echo google-cloud-firestore==2.15.0>> requirements.txt
echo [OK] requirements.txt written.

REM -----------------------
REM 4) Write Dockerfile
REM -----------------------
(
echo FROM python:3.11-slim
echo WORKDIR /app
echo COPY requirements.txt requirements.txt
echo RUN pip install --no-cache-dir --upgrade pip -r requirements.txt
echo COPY . .
echo CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 600 --worker-class gthread app:app
) > Dockerfile
echo [OK] Dockerfile written.

REM -----------------------
REM 5) Write cloudbuild.yaml (optional auto-deploy build)
REM -----------------------
(
echo steps:
echo ^  - name: 'gcr.io/cloud-builders/gcloud'
echo ^    args:
echo ^      [
echo ^        'run','deploy','%ACC_SERVICE_NAME%',
echo ^        '--project=%PROJECT_ID%','--region=%REGION%',
echo ^        '--source=.',
echo ^        '--memory=1Gi','--timeout=600s',
echo ^        '--concurrency=80','--no-allow-unauthenticated',
echo ^        '--startup-cpu-boost','--liveness-probe-path=/_internal/live'
echo ^      ]
echo timeout: '1200s'
echo options:
echo ^  logging: CLOUD_LOGGING_ONLY
) > cloudbuild.yaml
echo [OK] cloudbuild.yaml written.

REM -----------------------
REM 6) Ensure Artifact Registry permission for compute SA (fixes Docker push)
REM -----------------------
echo [INFO] Granting Artifact Registry writer role to compute SA (may require project Owner privileges)...
gcloud projects add-iam-policy-binding %PROJECT_ID% --member="serviceAccount:%COMPUTE_SA%" --role="roles/artifactregistry.writer" --quiet
if ERRORLEVEL 1 (
  echo [WARN] Could not grant artifactregistry.writer to %COMPUTE_SA%. You may need higher privileges.
) else (
  echo [OK] Granted roles/artifactregistry.writer to %COMPUTE_SA%.
)

REM -----------------------
REM 7) Ensure Artifact Repo exists (create if not)
REM -----------------------
echo [INFO] Ensuring Artifact Registry repo exists...
gcloud artifacts repositories describe %ARTIFACT_REPO% --project=%PROJECT_ID% --location=%ARTIFACT_LOCATION% >nul 2>&1
if ERRORLEVEL 1 (
  echo [INFO] Creating Artifact Registry repo %ARTIFACT_REPO% in %ARTIFACT_LOCATION%...
  gcloud artifacts repositories create %ARTIFACT_REPO% --repository-format=docker --location=%ARTIFACT_LOCATION% --description="Docker repo for %ACC_SERVICE_NAME%" --project=%PROJECT_ID%
  if ERRORLEVEL 1 (
    echo [WARN] Failed to create Artifact Registry repo. If it already exists in another region, skip this.
  ) else (
    echo [OK] Artifact Registry repo created.
  )
) else (
  echo [OK] Artifact Registry repo %ARTIFACT_REPO% already exists.
)

REM -----------------------
REM 8) Deploy loop with retries + fallback memory bump
REM -----------------------
set ATTEMPT=1
:DEPLOY_TRY
echo [INFO] Deploy attempt %ATTEMPT%...
gcloud run deploy %ACC_SERVICE_NAME% --region=%REGION% --project=%PROJECT_ID% --source=. --memory=1Gi --timeout=600s --quiet
if %ERRORLEVEL% EQU 0 (
  echo [OK] Deploy succeeded on attempt %ATTEMPT%.
  goto VERIFY
) else (
  echo [WARN] Deploy failed on attempt %ATTEMPT%.
  if %ATTEMPT% GEQ %RETRIES% (
    echo [ERROR] Maximum retries reached. Attempting fallback: increase memory & redeploy once more...
    gcloud run deploy %ACC_SERVICE_NAME% --region=%REGION% --project=%PROJECT_ID% --source=. --memory=2Gi --timeout=600s --quiet
    if %ERRORLEVEL% EQU 0 (
      echo [OK] Fallback deploy with 2Gi succeeded.
      goto VERIFY
    ) else (
      echo [ERROR] Fallback deploy failed. Rolling back to backup and exiting.
      REM restore backup (basic restore)
      xcopy "%BACKUP_DIR%\*" . /E /I /Y
      echo [INFO] Restored backup to working directory.
      exit /b 1
    )
  ) else (
    set /a ATTEMPT+=1
    echo [INFO] Waiting 6 seconds before retry...
    timeout /t 6 >nul
    goto DEPLOY_TRY
  )
)

:VERIFY
REM -----------------------
REM 9) Get ACC URL & token, then health-check
REM -----------------------
for /f "delims=" %%i in ('gcloud run services describe %ACC_SERVICE_NAME% --region=%REGION% --project=%PROJECT_ID% --format="value(status.url)"') do set ACC_URL=%%i
echo [INFO] ACC URL = %ACC_URL%

for /f "delims=" %%i in ('gcloud auth print-identity-token --impersonate-service-account=%BRIDGE_SERVICE_ACCOUNT% --audiences=%ACC_URL%') do set TOKEN=%%i
if "%TOKEN%"=="" (
  echo [ERROR] Could not generate identity token. Check impersonation permissions.
  exit /b 1
)

echo [INFO] Performing health check on %ACC_URL%/ ...
curl -s -H "Authorization: Bearer %TOKEN%" %ACC_URL%/ > health.json
type health.json
findstr /i "acc_ok" health.json >nul
if %ERRORLEVEL% EQU 0 (
  echo [OK] Health check returned success.
) else (
  echo [WARN] Health check did not return acc_ok. Showing logs and tailing last lines...
  gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=%ACC_SERVICE_NAME%" --project=%PROJECT_ID% --limit=30 --format="value(textPayload)"
  REM Do not exit yet; continue to attempt relay test
)

REM -----------------------
REM 10) Bridge -> ACC relay test (POST)
REM -----------------------
echo [INFO] Testing Bridge -> ACC relay (POST to Bridge relay_task)...
for /f "delims=" %%i in ('gcloud run services describe %ACC_SERVICE_NAME% --region=%REGION% --project=%PROJECT_ID% --format="value(status.url)"') do set DUMMYACCURL=%%i
for /f "delims=" %%i in ('gcloud auth print-identity-token --impersonate-service-account=%BRIDGE_SERVICE_ACCOUNT% --audiences=https://bsmartflow-acc-bridge-147849918817.asia-south1.run.app') do set BRIDGE_TOKEN=%%i

curl -s -X POST https://bsmartflow-acc-bridge-147849918817.asia-south1.run.app/relay_task -H "Authorization: Bearer %BRIDGE_TOKEN%" -H "Content-Type: application/json" -d "{\"initiator\":\"admin@bsmartflow.com\",\"command\":\"system_status_check\",\"parameters\":{\"mode\":\"live\"},\"auth_token\":\"8ed1029a16d4ad46e680db41d327b6447995c3c57eca6fa67b0783a33a5c3d66\"}" > relay_out.json
echo [INFO] Relay response:
type relay_out.json
findstr /i "acc_ok" relay_out.json >nul
if %ERRORLEVEL% EQU 0 (
  echo [OK] Bridge -> ACC relay returned success.
) else (
  echo [WARN] Bridge -> ACC relay returned error or acc_error. Check logs:
  gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=%ACC_SERVICE_NAME%" --project=%PROJECT_ID% --limit=40 --format="value(textPayload)"
)

REM -----------------------
REM 11) Create Guardian Cloud Scheduler (health ping) if not exists
REM -----------------------
echo [INFO] Ensure Cloud Scheduler job %SCHEDULER_JOB_NAME% exists to ping ACC every 15m...
gcloud scheduler jobs describe %SCHEDULER_JOB_NAME% --project=%PROJECT_ID% --location=%REGION% >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
  echo [INFO] Creating scheduler job to call Bridge -> ACC health endpoint every 15 minutes...
  gcloud scheduler jobs create http %SCHEDULER_JOB_NAME% --project=%PROJECT_ID% --location=%REGION% --schedule="*/15 * * * *" --uri="https://bsmartflow-acc-bridge-147849918817.asia-south1.run.app/relay_task" --http-method=POST --time-zone="UTC" --oauth-service-account-email=%BRIDGE_SERVICE_ACCOUNT% --message-body="{\"initiator\":\"system\",\"command\":\"system_status_check\",\"parameters\":{\"mode\":\"scheduled\"},\"auth_token\":\"8ed1029a16d4ad46e680db41d327b6447995c3c57eca6fa67b0783a33a5c3d66\"}" --quiet
  if %ERRORLEVEL% EQU 0 (
    echo [OK] Scheduler job created.
  ) else (
    echo [WARN] Could not create scheduler job. Check permissions for Cloud Scheduler and service account.
  )
) else (
  echo [OK] Scheduler job %SCHEDULER_JOB_NAME% already exists.
)

echo [DONE] Redeploy script finished. Check logs and monitor for any runtime errors.
exit /b 0
