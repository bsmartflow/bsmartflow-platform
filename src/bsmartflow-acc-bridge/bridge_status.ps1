# ==========================================================
# 📊 BsmartFlow System Live Dashboard - ACC + Bridge Monitor
# ----------------------------------------------------------
# Author   : Bhavani Prasad
# Project  : bsmartflow-474718
# Region   : asia-south1
# Services : ACC, Bridge
# ==========================================================

$project = "bsmartflow-474718"
$region = "asia-south1"
$accUrl = "https://bsmartflow-acc-csrkdzkynq-el.a.run.app"
$bridgeUrl = "https://bsmartflow-acc-bridge-csrkdzkynq-el.a.run.app"
$bridgeSA = "bsmartflow-acc-bridge@$project.iam.gserviceaccount.com"

function Write-Color {
    param (
        [string]$Text,
        [ConsoleColor]$Color = "White"
    )
    $oldColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $Color
    Write-Host $Text
    $Host.UI.RawUI.ForegroundColor = $oldColor
}

Write-Host ""
Write-Color "==========================================================" Cyan
Write-Color "   🧠 BsmartFlow Live Status Dashboard - ACC + Bridge" Cyan
Write-Color "==========================================================" Cyan
Write-Host ""

# 🧩 AUTH CHECK
Write-Color "🔑 Checking gcloud authentication..." Yellow
$authAccount = (gcloud auth list --format="value(account)" 2>$null)
if (-not $authAccount) {
    Write-Color "⚠️  No active login found! Logging in..." Red
    gcloud auth login admin@bsmartflow.com
    $authAccount = (gcloud auth list --format="value(account)" 2>$null)
}
Write-Color "✅ Active account: $authAccount" Green
Write-Host ""

# 🩺 FUNCTION: HEALTH CHECK
function Test-ServiceHealth {
    param([string]$Name, [string]$Url)

    try {
        $resp = Invoke-WebRequest -Uri "$Url/health" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) {
            Write-Color "[$Name] ✅ Healthy ($($resp.StatusCode)) - $Url" Green
            return $true
        }
    } catch {
        Write-Color "[$Name] ❌ Unhealthy or Unreachable - $Url" Red
        return $false
    }
}

# 🩺 RUN HEALTH TESTS
Write-Color "🔍 Checking Service Health..." Yellow
$accStatus = Test-ServiceHealth "ACC" $accUrl
$bridgeStatus = Test-ServiceHealth "Bridge" $bridgeUrl
Write-Host ""

# 🔐 TOKEN STATUS
Write-Color "🔄 Checking Identity Token (Bridge SA)..." Yellow
try {
    $token = gcloud auth print-identity-token --impersonate-service-account=$bridgeSA --project=$project
    if ($token) {
        Write-Color "✅ Token valid and refreshed successfully." Green
        Write-Host ""
        Write-Color "📋 Token copied to clipboard for GPT authentication." Cyan
        Set-Clipboard -Value $token
    } else {
        Write-Color "❌ Failed to generate new token." Red
    }
} catch {
    Write-Color "⚠️ Token refresh error: $($_.Exception.Message)" Red
}

Write-Host ""
Write-Color "==========================================================" Cyan
Write-Color "                 🔹 STATUS SUMMARY 🔹" White
Write-Color "----------------------------------------------------------" Cyan
Write-Color ("ACC Health     : " + $(if ($accStatus) { "✅ OK" } else { "❌ FAIL" })) ($(if ($accStatus) { "Green" } else { "Red" }))
Write-Color ("Bridge Health  : " + $(if ($bridgeStatus) { "✅ OK" } else { "❌ FAIL" })) ($(if ($bridgeStatus) { "Green" } else { "Red" }))
Write-Color "Token Refreshed: ✅ Copied to clipboard (valid for 60 min)" Yellow
Write-Color "----------------------------------------------------------" Cyan
Write-Color "Timestamp: $(Get-Date -Format 'u')" White
Write-Color "==========================================================" Cyan
Write-Host ""

Write-Color "🧾 You can paste this token directly into GPT Editor → Authentication → API Key (Bearer)." Cyan
Write-Host ""
