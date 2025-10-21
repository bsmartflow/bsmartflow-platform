# ==========================================================
# 🧠 BsmartFlow System Auto-Maintenance & GPT Token Refresher
# ----------------------------------------------------------
# Author  : Bhavani Prasad
# Project : bsmartflow-474718
# Services: ACC, Bridge
# Region  : asia-south1
# ==========================================================

# === CONFIGURATION ===
$project = "bsmartflow-474718"
$region = "asia-south1"
$accService = "bsmartflow-acc"
$bridgeService = "bsmartflow-acc-bridge"
$bridgeSA = "bsmartflow-acc-bridge@$project.iam.gserviceaccount.com"
$logFile = "$PSScriptRoot\bridge_maintenance_log_$(Get-Date -Format yyyy-MM-dd).txt"

Add-Content $logFile "`n==========================================================="
Add-Content $logFile "[INIT] $(Get-Date -Format 'u') - Starting System Maintenance"
Add-Content $logFile "==========================================================="

# === AUTHENTICATION VALIDATION ===
Write-Host "🔑 Checking gcloud authentication..."
$authAccount = (gcloud auth list --format="value(account)" 2>$null)
if (-not $authAccount) {
    Write-Host "🔒 No active login found. Logging in..."
    gcloud auth login admin@bsmartflow.com
    $authAccount = (gcloud auth list --format="value(account)" 2>$null)
}
Add-Content $logFile "[AUTH] Active account: $authAccount"

# === 1️⃣ HEALTH CHECK ===
function Check-Service {
    param([string]$Service, [string]$Url)
    try {
        $response = Invoke-WebRequest -Uri "$Url/health" -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
        Add-Content $logFile "[$Service] ✅ Healthy ($($response.StatusCode))"
        return $true
    } catch {
        Add-Content $logFile "[$Service] ⚠️ Unhealthy or unreachable. Repairing IAM..."
        gcloud run services add-iam-policy-binding $Service `
            --region=$region `
            --project=$project `
            --member="serviceAccount:$bridgeSA" `
            --role="roles/run.invoker" | Out-File -Append -FilePath $logFile
        return $false
    }
}

$accUrl = "https://bsmartflow-acc-csrkdzkynq-el.a.run.app"
$bridgeUrl = "https://bsmartflow-acc-bridge-csrkdzkynq-el.a.run.app"

Add-Content $logFile "`n🩺 Checking service health..."
$accHealth = Check-Service $accService $accUrl
$bridgeHealth = Check-Service $bridgeService $bridgeUrl

# === 2️⃣ TOKEN REFRESH ===
Write-Host "`n🔄 Refreshing GPT token..."
try {
    $token = gcloud auth print-identity-token --impersonate-service-account=$bridgeSA --project=$project
    if ($token) {
        Set-Clipboard -Value $token
        Add-Content $logFile "[TOKEN] ✅ Refreshed and copied to clipboard"
        Write-Host "✅ Token generated and copied to clipboard. Paste it into GPT editor (Bearer token)."
    } else {
        Add-Content $logFile "[TOKEN] ❌ Failed to generate token"
        Write-Host "❌ Failed to refresh token"
    }
} catch {
    Add-Content $logFile "[TOKEN] ❌ Error during token refresh: $($_.Exception.Message)"
}

# === 3️⃣ FINAL REPORT ===
Add-Content $logFile "`n🧾 Maintenance Summary:"
Add-Content $logFile "-----------------------------------------------------------"
Add-Content $logFile "ACC Health    : $($accHealth)"
Add-Content $logFile "Bridge Health : $($bridgeHealth)"
Add-Content $logFile "Token Refresh : Completed ($(Get-Date -Format 'u'))"
Add-Content $logFile "-----------------------------------------------------------"
Add-Content $logFile "✅ Maintenance completed successfully."
Add-Content $logFile "===========================================================`n"

Write-Host "`n✅ Maintenance complete. Log saved at:"
Write-Host "  $logFile"
