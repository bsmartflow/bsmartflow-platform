# ============================================================
# ✅ Bridge Health Validator (PowerShell)
# ============================================================

$bridgeURL = "https://bsmartflow-acc-bridge-csrkdzkynq-el.a.run.app"

Write-Host "🔍 Checking Bridge Health..." -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri "$bridgeURL/health" -Method GET -TimeoutSec 15
    if ($response.status -eq "ok") {
        Write-Host "✅ Bridge is healthy. Service: $($response.service)" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Bridge returned unexpected response: $response" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Bridge health check failed: $($_.Exception.Message)" -ForegroundColor Red
}
