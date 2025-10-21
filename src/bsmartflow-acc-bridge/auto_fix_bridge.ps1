# ======================================================
# 🔧 BsmartFlow Bridge Auto-Heal + Redeploy Script
# ======================================================

$Project = "bsmartflow-474718"
$Region = "asia-south1"
$Service = "bsmartflow-acc-bridge"
$ServiceAccount = "bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.com"
$Url = "https://bsmartflow-acc-bridge-147849918817.asia-south1.run.app"
$LogFile = "$PSScriptRoot\auto_fix_bridge_log.txt"

Write-Host "`n======================================================="
Write-Host "🩺 BsmartFlow Bridge Auto-Heal and Deployment Validator"
Write-Host "======================================================="

# 1️⃣ Check gcloud authentication
$auth = (gcloud auth list --format="value(account)")
if (-not $auth) {
    Write-Host "🔒 No authentication found, logging in..."
    gcloud auth login admin@bsmartflow.com
} else {
    Write-Host "✅ Authenticated as $auth"
}

# 2️⃣ Health check
try {
    $token = gcloud auth print-identity-token --impersonate-service-account=$ServiceAccount
    $headers = @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" }
    $response = Invoke-RestMethod -Uri "$Url/health" -Headers $headers -Method GET -ErrorAction Stop
    if ($response.status -eq "ok") {
        Write-Host "✅ Bridge healthy — no action required."
        Add-Content $LogFile "[$(Get-Date)] Bridge healthy."
        exit 0
    }
} catch {
    Write-Host "⚠️ Bridge unhealthy — redeploying..."
}

# 3️⃣ Redeploy
gcloud run deploy $Service `
    --source . `
    --region=$Region `
    --project=$Project `
    --memory=1Gi `
    --timeout=900s `
    --service-account=$ServiceAccount `
    --concurrency=80 `
    --quiet

# 4️⃣ Confirm new deployment
Start-Sleep -Seconds 15
$response = Invoke-RestMethod -Uri "$Url/health" -Headers $headers -Method GET -ErrorAction SilentlyContinue

if ($response.status -eq "ok") {
    Write-Host "✅ Bridge redeployed and healthy."
    Add-Content $LogFile "[$(Get-Date)] Bridge redeployed successfully."
} else {
    Write-Host "❌ Redeploy failed. Check Cloud Run logs."
    Add-Content $LogFile "[$(Get-Date)] Bridge redeploy failed. Manual check required."
}
