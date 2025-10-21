

# ==========================================================
# 🔁 BsmartFlow Continuous Bridge Monitor & Token Refresher
# ----------------------------------------------------------
# Author : Bhavani Prasad
# Project: bsmartflow-474718   |  Region: asia-south1
# ==========================================================

$project     = "bsmartflow-474718"
$region      = "asia-south1"
$bridgeSA    = "bsmartflow-acc-bridge@$project.iam.gserviceaccount.com"
$accUrl      = "https://bsmartflow-acc-csrkdzkynq-el.a.run.app"
$bridgeUrl   = "https://bsmartflow-acc-bridge-csrkdzkynq-el.a.run.app"
$logFile     = "$PSScriptRoot\bridge_monitor_log_$(Get-Date -Format yyyy-MM-dd).txt"

# ----- COLOR UTILITY -----
function Write-Color($text, $color="White") {
    $old = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $color
    Write-Host $text
    $Host.UI.RawUI.ForegroundColor = $old
}

Add-Content $logFile "`n[$(Get-Date -Format u)] ▶ Monitor started"

# ----- AUTH CHECK -----
$auth = (gcloud auth list --format="value(account)" 2>$null)
if (-not $auth) {
    Write-Color "⚠️  No gcloud session; logging in..." Yellow
    gcloud auth login admin@bsmartflow.com | Out-Null
    $auth = (gcloud auth list --format="value(account)")
}
Write-Color "✅ Authenticated as $auth" Green
Add-Content $logFile "[AUTH] $auth"

# ----- FUNCTION: HEALTH -----
function Check-Service($name, $url) {
    try {
        $r = Invoke-WebRequest -Uri "$url/health" -UseBasicParsing -TimeoutSec 10
        if ($r.StatusCode -eq 200) {
            Write-Color "[$name] ✅ Healthy ($($r.StatusCode))" Green
            Add-Content $logFile "[$name] OK"
            return $true
        }
    } catch {
        Write-Color "[$name] ❌ $($_.Exception.Message)" Red
        Add-Content $logFile "[$name] FAIL"
        return $false
    }
}

# ----- FUNCTION: REFRESH TOKEN -----
function Refresh-BridgeToken {
    try {
        Write-Color "🔄 Refreshing Bridge identity token..." Yellow
        $token = gcloud auth print-identity-token --impersonate-service-account=$bridgeSA --project=$project
        if ($token) {
            Set-Clipboard -Value $token
            Add-Content $logFile "[TOKEN] Refreshed at $(Get-Date -Format u)"
            Write-Color "✅ Token refreshed and copied to clipboard" Green
            return $token
        } else {
            throw "Empty token output"
        }
    } catch {
        Write-Color "❌ Token refresh failed: $($_.Exception.Message)" Red
        Add-Content $logFile "[TOKEN] ERROR: $($_.Exception.Message)"
        return $null
    }
}

# ----- MAIN LOOP -----
while ($true) {
    Write-Color "`n==========================================================" Cyan
    Write-Color "🧠 BsmartFlow Bridge Monitor - $(Get-Date -Format T)" Cyan
    Write-Color "==========================================================" Cyan

    $accOK    = Check-Service "ACC" $accUrl
    $bridgeOK = Check-Service "Bridge" $bridgeUrl

    if (-not $bridgeOK) {
        Write-Color "⚠️  Bridge unhealthy → attempting token repair..." Yellow
        $token = Refresh-BridgeToken
        if ($token) {
            Write-Color "🔁 Re-testing Bridge health..." Yellow
            try {
                $hdr = @{ "Authorization" = "Bearer $token" }
                $resp = Invoke-RestMethod -Uri "$bridgeUrl/health" -Headers $hdr -Method GET
                if ($resp.status -eq "ok") {
                    Write-Color "✅ Bridge recovered successfully." Green
                    Add-Content $logFile "[AUTOHEAL] Bridge recovered"
                } else {
                    Write-Color "❌ Bridge still failing after token repair." Red
                }
            } catch {
                Write-Color "❌ Bridge test failed post-refresh." Red
            }
        }
    }

    Write-Color "`n🕒 Next check in 15 minutes..." White
    Add-Content $logFile "[LOOP] Next cycle 15m"
    Start-Sleep -Seconds 900   # 15 min loop
}



