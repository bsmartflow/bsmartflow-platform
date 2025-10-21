# ======================================================
# 🧠  BsmartFlow Bridge + ACC Auto-Validation & Auto-Heal
# ======================================================

$Project       = "bsmartflow-474718"
$Region        = "asia-south1"
$BridgeService = "bsmartflow-acc-bridge"
$AccService    = "bsmartflow-acc"
$BridgeUrl     = "https://bsmartflow-acc-bridge-147849918817.asia-south1.run.app"
$AccUrl        = "https://bsmartflow-acc-147849918817.asia-south1.run.app"
$BridgeSA      = "bsmartflow-acc-bridge@bsmartflow-474718.iam.gserviceaccount.com"
$LogRoot       = "$PSScriptRoot"
$LogFile       = "$LogRoot\validate_bridge_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

Write-Host "`n====================================================="
Write-Host "🔍  BsmartFlow Bridge + ACC Health Validation & Auto-Heal"
Write-Host "====================================================="
Add-Content $LogFile "[START] $(Get-Date -Format 'u')  Validation run started"

# -------------------------------
# STEP 1 – Auth Validation
# -------------------------------
$auth = (gcloud auth list --format="value(account)")
if (-not $auth) {
    Write-Host "🔒 No gcloud login found. Logging in..."
    gcloud auth login admin@bsmartflow.com
    $auth = (gcloud auth list --format="value(account)")
}
Write-Host "✅ Authenticated as $auth"
Add-Content $LogFile "Authenticated as $auth"

# -------------------------------
# STEP 2 – Generate Token
# -------------------------------
Write-Host "🎟️  Generating identity token..."
$token = gcloud auth print-identity-token --impersonate-service-account=$BridgeSA
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

# Helper: run GET /health
function Check-Service {
    param([string]$Name, [string]$Url)
    try {
        $resp = Invoke-RestMethod -Uri "$Url/health" -Headers $headers -Method GET -TimeoutSec 20 -ErrorAction Stop
        if ($resp.status -eq "ok") {
            Write-Host "✅ $Name health: OK"
            Add-Content $LogFile "$Name health OK"
            return $true
        }
        else {
            Write-Host "⚠️ $Name health returned: $($resp.status)"
            Add-Content $LogFile "$Name health abnormal: $($resp.status)"
            return $false
        }
    }
    catch {
        Write-Host "❌ $Name health failed: $($_.Exception.Message)"
        Add-Content $LogFile "$Name health failed: $($_.Exception.Message)"
        return $false
    }
}

# -------------------------------
# STEP 3 – Individual Health Checks
# -------------------------------
$bridgeOK = Check-Service "Bridge" $BridgeUrl
$accOK    = Check-Service "ACC"    $AccUrl

# -------------------------------
# STEP 4 – Bridge /execute_task
# -------------------------------
Write-Host "🔧  Testing Bridge /execute_task..."
try {
    $body = @{ ping = "bridge_self_test" } | ConvertTo-Json
    $resp = Invoke-RestMethod -Uri "$BridgeUrl/execute_task" -Headers $headers -Method POST -Body $body -ErrorAction Stop
    if ($resp.response -match "Bridge executed successfully") {
        Write-Host "✅ Bridge /execute_task working."
        Add-Content $LogFile "Bridge /execute_task OK"
        $bridgeTaskOK = $true
    }
    else {
        Write-Host "⚠️ Bridge /execute_task unexpected."
        Add-Content $LogFile "Bridge /execute_task unexpected: $($resp | ConvertTo-Json -Compress)"
        $bridgeTaskOK = $false
    }
}
catch {
    Write-Host "❌ Bridge /execute_task failed: $($_.Exception.Message)"
    Add-Content $LogFile "Bridge /execute_task failed: $($_.Exception.Message)"
    $bridgeTaskOK = $false
}

# -------------------------------
# STEP 5 – GPT Handshake Simulation
# -------------------------------
Write-Host "🤖  Simulating GPT handshake..."
try {
    $body = @{ ping = "gpt_bridge_handshake" } | ConvertTo-Json
    $resp = Invoke-RestMethod -Uri "$BridgeUrl/execute_task" -Headers $headers -Method POST -Body $body -ErrorAction Stop
    if ($resp.bridge_request.ping -eq "gpt_bridge_handshake") {
        Write-Host "✅ GPT handshake successful."
        Add-Content $LogFile "GPT handshake OK"
        $gptOK = $true
    }
    else {
        Write-Host "⚠️ GPT handshake abnormal."
        Add-Content $LogFile "GPT handshake abnormal."
        $gptOK = $false
    }
}
catch {
    Write-Host "❌ GPT handshake failed: $($_.Exception.Message)"
    Add-Content $LogFile "GPT handshake failed: $($_.Exception.Message)"
    $gptOK = $false
}

# -------------------------------
# STEP 6 – Summary & Auto-Heal
# -------------------------------
Write-Host "`n====================================================="
Write-Host "📊  Health Validation Summary"
Write-Host "====================================================="
$allOK = ($bridgeOK -and $accOK -and $bridgeTaskOK -and $gptOK)

if ($allOK) {
    Write-Host "✅  ALL SYSTEMS HEALTHY AND OPERATIONAL"
    Add-Content $LogFile "[SUCCESS] All systems healthy"
}
else {
    Write-Host "❌  One or more systems failed health checks."
    Add-Content $LogFile "[FAIL] One or more checks failed — launching auto-fix"
    # --- Trigger auto-heal ---
    $autoFix = "$PSScriptRoot\auto_fix_bridge.ps1"
    if (Test-Path $autoFix) {
        Write-Host "🛠️  Running auto_fix_bridge.ps1 ..."
        Add-Content $LogFile "Auto-fix triggered at $(Get-Date -Format 'u')"
        powershell -ExecutionPolicy Bypass -File $autoFix | Tee-Object -Append -FilePath $LogFile
    }
    else {
        Write-Host "⚠️  auto_fix_bridge.ps1 not found in $PSScriptRoot"
        Add-Content $LogFile "Auto-fix script missing."
    }
}

Write-Host "====================================================="
Write-Host "🕓  Completed at: $(Get-Date -Format 'u')"
Write-Host "Log saved to: $LogFile"
Write-Host "====================================================="
Add-Content $LogFile "[END] $(Get-Date -Format 'u')  Validation run completed"
