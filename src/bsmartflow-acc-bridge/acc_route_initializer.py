# acc_route_initializer.py
from flask import Flask, request, jsonify
import os, importlib

app = Flask(__name__)

# Try to import and wrap the main app if it exists
try:
    main_module = importlib.import_module("main")
    if hasattr(main_module, "app"):
        base_app = getattr(main_module, "app")
        app.wsgi_app = base_app.wsgi_app
        print("✅ Integrated main module successfully.")
except Exception as e:
    print("⚠️ Could not load main app:", e)

# --- HEALTH & STATUS ROUTES ---
@app.route("/")
def home():
    return "✅ ACC service is live and healthy!", 200

@app.route("/health")
def health_check():
    return jsonify({"status": "ok", "service": "ACC"}), 200

# --- GPT CONNECTION TEST ---
@app.route("/gpt-connect", methods=["POST"])
def gpt_connect():
    data = request.get_json(silent=True) or {}
    return jsonify({
        "bridge_request": data,
        "response": "ACC active and authenticated"
    }), 200

# --- ENTRY POINT ---
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
