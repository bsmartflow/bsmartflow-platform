=====================================================
✅ BsmartFlow ACC Service - Main API Entry
=====================================================
os.environ["GOOGLE_CLOUD_PROJECT"] = "bsmartflow-474718"
 from flask import Flask, jsonify, request
 import os
 app = Flask(name)
-----------------------------------------------------
🩺 Health and Root Endpoints
-----------------------------------------------------
@app.route("/")
 def home():
     return "✅ ACC service is live and healthy!", 200
 @app.route("/health")
 def health():
     return jsonify({"status": "ok", "service": "ACC"}), 200
 @app.route("/acc/health")
 @app.route("/api/health")
 @app.route("/acc")
 def acc_alias():
     return jsonify({"status": "ok", "alias": True, "service": "ACC"}), 200
-----------------------------------------------------
🤖 GPT / Bridge Communication Endpoints
-----------------------------------------------------
@app.route("/gpt-connect", methods=["POST"])
 def gpt_connect():
     """Used by GPT systems or other orchestration services"""
     data = request.get_json(silent=True) or {}
     return jsonify({
         "received": data,
         "response": "ACC active",
         "route": "/gpt-connect"
     }), 200
 @app.route("/execute_task", methods=["POST"])
 def execute_task():
     """Main endpoint for Bridge → ACC communication"""
     data = request.get_json(silent=True) or {}
     return jsonify({
         "bridge_request": data,
         "response": "ACC executed successfully",
         "source": "ACC"
     }), 200
-----------------------------------------------------
🚀 App Startup
-----------------------------------------------------
if name == "main":
     port = int(os.environ.get("PORT", 8080))
     print(f"🚀 Starting ACC service on port {port} ...")
     app.run(host="0.0.0.0", port=port)
Is this correct?
bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.comgcloud run deploy bsmartflow-acc-bridge ^
  --source . ^
  --region=asia-south1 ^
  --project=bsmartflow-474718 ^
  --memory=1Gi ^
  --timeout=900s ^
  --service-account=bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.com ^
  --quietgcloud run deploy bsmartflow-acc-bridge ^
  --source . ^
  --region=asia-south1 ^
  --project=bsmartflow-474718 ^
  --memory=1Gi ^
  --timeout=900s ^
  --service-account=bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.com ^
  --quiet
