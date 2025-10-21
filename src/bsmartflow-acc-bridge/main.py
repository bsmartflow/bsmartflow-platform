import os
import requests
import google.auth
import google.auth.transport.requests
from flask import Flask, request

# ---- Configuration ----
# This is the correct trigger URL for your action-taker workflow.
WORKFLOW_TRIGGER_URL = "https://workflowexecutions.googleapis.com/v1/projects/bsmartflow-474718/locations/us-west1/workflows/action-taker/executions"

# ---- Flask Application ----
app = Flask(__name__)

# This is the original health check route. It handles GET requests.
@app.route("/", methods=["GET"])
def health_check():
    """Confirms the service is running."""
    print("Health check endpoint was called.")
    return {"service": "BsmartFlow ACC Bridge", "status": "ok"}, 200

# This is the new route to handle commands from the UI.
@app.route("/", methods=["POST"])
def trigger_workflow():
    """Receives a command via POST and triggers the action-taker workflow."""
    
    # 1. Get the JSON command from the incoming request.
    command_data = request.get_json()
    if not command_data:
        print("ERROR: No JSON payload received.")
        return ("No JSON payload received", 400)

    print(f"Received command: {command_data}")

    # 2. Get an identity token for this Cloud Run service's own service account.
    # This token proves the bridge's identity when it calls the workflow.
    try:
        auth_req = google.auth.transport.requests.Request()
        # The 'audience' must be the URL of the service we are calling.
        identity_token = google.auth.default(scopes=[WORKFLOW_TRIGGER_URL])[0].token
        print("Successfully fetched identity token.")
    except Exception as e:
        print(f"FATAL: Error fetching identity token: {e}")
        return ("Failed to get identity token for the service account.", 500)
    
    # 3. Set up the headers for the authenticated request to the workflow.
    headers = {
        "Authorization": f"Bearer {identity_token}",
        "Content-Type": "application/json"
    }

    # 4. Make the authenticated POST request to trigger the workflow.
    try:
        print(f"Triggering workflow at: {WORKFLOW_TRIGGER_URL}")
        workflow_response = requests.post(WORKFLOW_TRIGGER_URL, json=command_data, headers=headers)
        workflow_response.raise_for_status()  # This will raise an exception for 4xx or 5xx status codes.
        print(f"Successfully triggered workflow. Downstream status: {workflow_response.status_code}")
        return ("SUCCESS: Workflow triggered.", 200)
    except requests.exceptions.RequestException as e:
        print(f"FATAL: Error triggering workflow: {e}")
        error_message = f"Failed to trigger workflow. Status: {e.response.status_code if e.response else 'N/A'}, Body: {e.response.text if e.response else 'N/A'}"
        return (error_message, 500)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=True)
