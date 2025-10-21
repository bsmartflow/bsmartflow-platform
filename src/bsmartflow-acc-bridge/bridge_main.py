
# ============================================================
# ✅ BsmartFlow ACC Bridge (PowerShell-Compatible Final Build)
# ============================================================

import os
import json
import requests
from flask import Flask, request, jsonify
from google.auth import default
from google.auth.transport.requests import Request
from datetime import datetime

# ------------------------------------------------------------
# 🔧 Basic Environment Setup
# ------------------------------------------------------------
os.environ["GOOGLE_CLOUD_PROJECT"] = "bsmartflow-474718"

PROJECT_ID = "bsmartflow-474718"
REGION = "asia-south1"
ACC_URL = "https://bsmartflow-acc-csrkdzkynq-el.a.run.app"
LOG_FILE = os.path.join(os.getcwd(), "bridge_activity_log.txt")

app = Flask(__name__)

# ------------------------------------------------------------
# 🧠 Utility Functions
# ------------------------------------------------------------
def log_event(message: str):
    """Append logs with timestamps (PowerShell-friendly text)."""
    timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(f"[{timestamp}] {message}\n")
    print(message)

def get_fresh_token():
    """Automatically refreshes Google Cloud identity token."""
    try:
        credentials, _ = default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
        credentials.refresh(Request())
        log_event("✅ Refreshed Google Cloud token successfully.")
        return credentials.token
    except Exception as e:
        log_event(f"❌ Token refresh failed: {e}")
        return None

# ------------------------------------------------------------
# 🩺 Health & Root Endpoints
# ------------------------------------------------------------
@app.route("/")
def home():
    log_event("🏠 Root accessed — Bridge active check OK.")
    return jsonify({
        "status": "ok",
        "service": "Bridge",
        "auto_refresh": True,
        "message": "BsmartFlow Bridge running via PowerShell."
    }), 200

@app.route("/health")
def health():
    log_event("🩺 Health check received.")
    return jsonify({
        "status": "ok",
        "service": "Bridge",
        "auto_refresh": True
    }), 200

# ------------------------------------------------------------
# 🤖 GPT → Bridge → ACC Communication
# ------------------------------------------------------------
@app.route("/execute_task", methods=["POST"])
def execute_task():
    """Relay command from GPT → Bridge → ACC (auto-refresh included)."""
    data = request.get_json(silent=True) or {}
    log_event(f"📩 Received execute_task payload: {data}")

    token = get_fresh_token()
    if not token:
        log_event("🚫 No token available — rejecting.")
        return jsonify({"error": "Token refresh failed"}), 401

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    try:
        resp = requests.post(f"{ACC_URL}/execute_task", headers=headers, json=data, timeout=25)
        if resp.status_code == 200:
            log_event("✅ Forwarded to ACC successfully.")
            return jsonify({
                "bridge_request": data,
                "acc_response": resp.json(),
                "status": "ok"
            }), 200
        else:
            log_event(f"⚠️ ACC responded with {resp.status_code}: {resp.text}")
            return jsonify({
                "error": f"ACC returned status {resp.status_code}",
                "details": resp.text
            }), resp.status_code
    except Exception as e:
        log_event(f"💥 Bridge internal error: {e}")
        return jsonify({"error": str(e)}), 500

# ------------------------------------------------------------
# 🔗 GPT Connection Test
# ------------------------------------------------------------
@app.route("/gpt-connect", methods=["POST"])
def gpt_connect():
    data = request.get_json(silent=True) or {}
    log_event("🤖 GPT handshake received.")
    return jsonify({
        "response": "Bridge auto-authenticated and connected.",
        "input": data
    }), 200

# ------------------------------------------------------------
# 🚀 App Startup
# ------------------------------------------------------------
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    log_event(f"🚀 Starting Bridge service on port {port} (PowerShell mode).")
    app.run(host="0.0.0.0", port=port)
