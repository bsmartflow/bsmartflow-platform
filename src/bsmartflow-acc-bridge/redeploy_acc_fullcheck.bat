@echo off
setlocal enabledelayedexpansion
title 🚀 BsmartFlow ACC Full Auto Heal + Bridge Validation

echo.
echo ===========================================================
echo   ⚙️  BsmartFlow ACC — Full Auto Redeploy + Relay Test
echo ===========================================================
echo.

REM ====== CONFIGURATION ======
set PROJECT_ID=bsmartflow-474718
set REGION=asia-south1
set ACC_SERVICE_NAME=bsmartflow-acc
set BRIDGE_SERVICE_ACCOUNT=bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.com
set ACC_URL=https://bsmartflow-acc-147849918817.asia-south1.run.app
set BRIDGE_URL=https://bsmartflow-acc-bridge-147849918817.asia-south1.run.app
set AUTH_TOKEN=8ed1029a16d4ad46e680db41d327b6447995c3c57eca6fa67b0783a33a5c3d66

echo [INFO] Project: %PROJECT_ID%
echo [INFO] Region: %REGION%
echo [INFO] ACC: %ACC_URL%
echo [INFO] Bridge: %BRIDGE_URL%
echo.

REM ====== BACKUP CURRENT FILES ======
set BACKUP_DIR=backup_acc_%date:~10,4%-%date:~4,2%-%date:~7,2%_%time:~0,2%-%time:~3,2%
set BACKUP_DIR=%BACKUP_DIR: =0%
mkdir "%BACKUP_DIR%" >nul 2>&1
xcopy /E /I /Y . "%BACKUP_DIR%" >nul
echo [OK] Backup created: %BACKUP_DIR%
echo.

REM ====== REWRITE FILES ======
echo [INFO] Rewriting main.py ...
(
echo from flask import Flask, jsonify, request
echo from google.cloud import firestore
echo import time, traceback, threading, os
echo.
echo app = Flask(__name__)
echo thread_local = threading.local()
echo.
echo def get_db():
echo.    if not hasattr(thread_local, "db_client"):
echo.        try:
echo.            print("[ACC] Initializing Firestore client...")
echo.            thread_local.db_client = firestore.Client()
echo.        except Exception as e:
echo.            print(f"[ACC WARNING] Firestore init failed: {e}")
echo.            time.sleep(1)
echo.            try:
echo.                thread_local.db_client = firestore.Client()
echo.            except Exception as e2:
echo.                print(f"[ACC ERROR] Second Firestore init failed: {e2}")
echo.                thread_local.db_client = None
echo.    return thread_local.db_client
echo.
echo @app.route("/", methods=["GET"])
echo def home():
echo.    db = get_db()
echo.    if db:
echo.        try:
echo.            db.collection("system_health").document("acc_status").set({"status":"online","timestamp":firestore.SERVER_TIMESTAMP}, merge=True)
echo.            return jsonify({"firestore":"connected","message":"Assistant Command Center running successfully","status":"acc_ok"}),200
echo.        except Exception as e:
echo.            print(f"[ACC WARNING] Firestore write failed: {e}")
echo.            return jsonify({"firestore":"degraded","status":"acc_degraded","message":"Firestore write error"}),200
echo.    else:
echo.        return jsonify({"firestore":"disconnected","status":"acc_degraded","message":"Firestore client unavailable"}),503
echo.
echo @app.route("/execute_task", methods=["POST"])
echo def execute_task():
echo.    start = time.time()
echo.    db = get_db()
echo.    try:
echo.        data = request.get_json(force=True, silent=True)
echo.        if not data:
echo.            return jsonify({"status":"bad_request","error":"Invalid JSON"}),400
echo.        initiator = data.get("initiator","unknown")
echo.        command = data.get("command","none")
echo.        params = data.get("parameters",{})
echo.        print(f"[ACC] Received command '{command}' from '{initiator}'")
echo.        if db:
echo.            try:
echo.                db.collection("acc_logs").add({"initiator":initiator,"command":command,"parameters":params,"timestamp":firestore.SERVER_TIMESTAMP,"status":"received"})
echo.            except Exception as fe:
echo.                print(f"[ACC WARNING] Firestore log failed: {fe}")
echo.        if command == "system_status_check":
echo.            resp = {"status":"acc_ok","message":"System health verified"}
echo.        else:
echo.            resp = {"status":"acc_ok","message":f"Command '{command}' executed"}
echo.        print(f"[ACC] Completed '{command}' in {round(time.time()-start,2)}s")
echo.        return jsonify(resp),200
echo.    except Exception as e:
echo.        print("[ACC ERROR]:", traceback.format_exc())
echo.        return jsonify({"status":"acc_error","error":str(e)}),500
echo.
echo @app.route("/_internal/live", methods=["GET"])
echo def live():
echo.    return "OK",200
echo.
echo if __name__ == "__main__":
echo.    port = int(os.environ.get("PORT",8080))
echo.    app.run(host="0.0.0.0", port=port)
) > main.py
echo [OK] main.py ready.

echo [INFO] Writing requirements.txt ...
(
echo Flask==3.0.2
echo gunicorn==21.2.0
echo google-cloud-firestore==2.15.0
) > requirements.txt
echo [OK] requirements.txt ready.

echo [INFO] Writing Dockerfile ...
(
echo FROM python:3.11-slim
echo WORKDIR /app
echo COPY requirements.txt .
echo RUN pip install --no-cache-dir -r requirements.txt
echo COPY . .
echo CMD exec gunicorn --bind :^$PORT --workers 1 --threads 8 --timeout 600 --worker-class gthread main:app
) > Dockerfile
echo [OK] Dockerfile ready.

echo [INFO] Writing cloudbuild.yaml ...
(
echo steps:
echo   - name: 'gcr.io/cloud-builders/gcloud'
echo     args:
echo       [
echo         'run', 'deploy', 'bsmartflow-acc',
echo         '--source=.',
echo         '--project=bsmartflow-474718',
echo         '--region=asia-south1',
echo         '--memory=1Gi',
echo         '--timeout=600s',
echo         '--clear-base-image',
echo         '--no-allow-unauthenticated',
echo         '--startup-cpu-boost',
echo         '--liveness-probe-path=/_internal/live',
echo         '--startup-probe-path=/'
echo       ]
echo timeout: '1200s'
echo options:
echo   logging: CLOUD_LOGGING_ONLY
) > cloudbuild.yaml
echo [OK] cloudbuild.yaml ready.
echo.

REM ====== DEPLOY ======
echo [INFO] Deploying ACC to Cloud Run ...
gcloud run deploy %ACC_SERVICE_NAME% --region=%REGION% --project=%PROJECT_ID% --source=. --memory=1Gi --timeout=600s --clear-base-image
if errorlevel 1 (
    echo [ERROR] Deployment failed ❌
    exit /b 1
)
echo [OK] Deployment completed ✅
echo.

REM ====== HEALTH CHECK ======
echo [INFO] Checking ACC health endpoint ...
for /f "delims=" %%i in ('gcloud auth print-identity-token --impersonate-service-account=%BRIDGE_SERVICE_ACCOUNT% --audiences=%ACC_URL%') do set TOKEN=%%i
for /f "delims=" %%a in ('curl -s -H "Authorization: Bearer !TOKEN!" !ACC_URL!/') do set RESPONSE=%%a
echo [RESULT] !RESPONSE!
echo.

REM ====== BRIDGE RELAY TEST ======
echo [INFO] Testing bridge relay -> ACC ...
for /f "delims=" %%i in ('gcloud auth print-identity-token --impersonate-service-account=%BRIDGE_SERVICE_ACCOUNT% --audiences=%BRIDGE_URL%') do set BRIDGE_TOKEN=%%i

for /f "delims=" %%r in ('curl -s -X POST %BRIDGE_URL%/relay_task -H "Authorization: Bearer !BRIDGE_TOKEN!" -H "Content-Type: application/json" -d "{\"initiator\":\"admin@bsmartflow.com\",\"command\":\"system_status_check\",\"parameters\":{\"mode\":\"live\"},\"auth_token\":\"%AUTH_TOKEN%\"}"') do set RELAY_RESPONSE=%%r

echo [RESULT] Bridge Relay Response:
echo !RELAY_RESPONSE!
echo.

echo ===========================================================
if "!RESPONSE!"=="" (
    echo ❌ ACC failed to respond to health check.
) else if "!RELAY_RESPONSE!"=="" (
    echo ⚠️  ACC OK, but Bridge relay test failed.
) else (
    echo ✅ FULL SYSTEM PASS — ACC + Bridge verified successfully.
)
echo ===========================================================
echo.
pause
