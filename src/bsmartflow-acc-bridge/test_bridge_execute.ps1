# ======================================================
#  BsmartFlow Bridge → ACC API Connectivity Validator
# ======================================================
$Project   = "bsmartflow-474718"
$Region    = "asia-south1"
$AccURL    = "https://bsmartflow-acc-147849918817.asia-south1.run.app/execute_task"
$BridgeSA  = "bsmartflow-acc-bridge@$Project.iam.gserviceaccount.com"

Write-Host "🔑 Generating identity token using Bridge service account..."
$token = gcloud auth print-identity-token --impersonate-service-account=$BridgeSA --project=$Project

Write-Host "🌐 Sending test payload to ACC /execute_task..."
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

$body = @{
    ping = "ok_from_bridge"
    timestamp = (Get-Date).ToString("u")
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri $AccURL -Headers $headers -Method POST -Body $body
    Write-Host "✅ Response from ACC:" -ForegroundColor Green
    $response | ConvertTo-Json -Depth 4
}
catch {
    Write-Host "❌ Request failed:" $_.Exception.Message -ForegroundColor Red
}
