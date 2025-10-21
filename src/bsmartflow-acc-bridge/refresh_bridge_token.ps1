# =====================================================
# 🔐 BsmartFlow Bridge Identity Token Refresher
# Author: Bhavani Prasad | System: BsmartFlow Automation
# =====================================================

$project = "bsmartflow-474718"
$serviceAccount = "bsmartflow-acc-bridge@$project.iam.gserviceaccount.com"

Write-Host "====================================================="
Write-Host "🔄 Generating new Identity Token for Bridge Service..."
Write-Host "====================================================="

try {
    # Generate new identity token
    $token = gcloud auth print-identity-token --impersonate-service-account=$serviceAccount --project=$project

    if ($token) {
        # Copy token to clipboard
        Set-Clipboard -Value $token
        Write-Host "✅ New identity token generated and copied to clipboard."
        Write-Host ""
        Write-Host "🔹 Paste this token in your Custom GPT Authentication → API Key field (Bearer type)."
        Write-Host "🔹 Token valid for ~60 minutes."
        Write-Host "-----------------------------------------------------"
        Write-Host $token
        Write-Host "-----------------------------------------------------"
    } else {
        Write-Host "❌ Failed to generate token. Please verify gcloud authentication."
    }
}
catch {
    Write-Host "❌ Error while generating token:" $_.Exception.Message
}

Write-Host ""
Write-Host "🕒 Next steps:"
Write-Host "1. Paste token in ChatGPT GPT Editor → Authentication → API Key"
Write-Host "2. Save GPT configuration"
Write-Host "3. Test /health and /execute_task endpoints"
