# ======================================================
#  BsmartFlow ACC + Bridge Auto-Heal and Health Validator
# ======================================================

# Ensure gcloud is authenticated before running
$authAccount = (gcloud auth list --format="value(account)" 2>$null)
if (-not $authAccount) {
    Write-Host "🔒 No active gcloud authentication found. Logging in..."
    gcloud auth login admin@bsmartflow.com
} else {
    Write-Host "🔑 Authenticated as $authAccount"
}

# ======================================================
# Configuration
# ======================================================
$Project = "bsmartflow-474718"
$Region = "asia-south1"
$AccService = "bsmartflow-acc"
$BridgeService = "bsmartflow-acc-bridge"
$AccUrl = "https://bsmartflow-acc-147849918817.asia-south1.run.app"
$BridgeUrl = "https://bsmartflow-acc-bridge-147849918817.asia-south1.run.app"
$LogFile = "$PSScriptRoot\auto_heal_log.txt"

# ======================================================
# Logging Header
# ======================================================
Add-Content $LogFile "`n====================================================="
Add-Content $LogFile "🚀 [$((Get-Date).ToString('u'))] Starting ACC + Bridge Health Check"
Add-Content $LogFile "====================================================="

# ======================================================
# Function: Check-Service
# ======================================================
function Check-Service {
    param(
        [string]$Service,
        [string]$Url
    )

    Add-Content $LogFile "-----------------------------------------------------"
    Add-Content $LogFile "Checking $Service health endpoint..."

    try {
        $response = Invoke-WebRequest -Uri "$Url/health" -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
        $Status = $response.StatusCode
    } catch {
        if ($_.Exception.Response -ne $null) {
            $Status = $_.Exception.Response.StatusCode.Value__
        } else {
            $Status = 0
        }
    }

    Add-Content $LogFile ("HTTP Status for {0}: {1}" -f $Service, $Status)

    switch ($Status) {
        200 {
            Add-Content $LogFile "✅ $Service is healthy."
            return
        }
        401 {
            Add-Content $LogFile "⚠️ 401 Unauthorized — repairing IAM..."
            & gcloud run services add-iam-policy-binding $Service `
                --region=$Region `
                --project=$Project `
                --member="serviceAccount:bsmartflow-acc-bridge@$Project.iam.gserviceaccount.com" `
                --role="roles/run.invoker" | Out-File -Append -FilePath $LogFile
        }
        403 {
            Add-Content $LogFile "⚠️ 403 Forbidden — repairing IAM..."
            & gcloud run services add-iam-policy-binding $Service `
                --region=$Region `
                --project=$Project `
                --member="serviceAccount:bsmartflow-acc-bridge@$Project.iam.gserviceaccount.com" `
                --role="roles/run.invoker" | Out-File -Append -FilePath $LogFile
        }
        404 {
            Add-Content $LogFile "❌ $Service not responding — redeploying..."
            & gcloud run deploy $Service `
                --region=$Region `
                --project=$Project `
                --source . `
                --quiet | Out-File -Append -FilePath $LogFile
        }
        Default {
            Add-Content $LogFile "⚠️ Unexpected status $Status — logged for review."
        }
    }
}

# ======================================================
# Run Checks
# ======================================================
Check-Service $AccService $AccUrl
Check-Service $BridgeService $BridgeUrl

Add-Content $LogFile "✅ [$((Get-Date).ToString('u'))] Health check complete."
Add-Content $LogFile "`n"
Write-Host "✅ Auto-heal health check completed successfully. See log at $LogFile"
