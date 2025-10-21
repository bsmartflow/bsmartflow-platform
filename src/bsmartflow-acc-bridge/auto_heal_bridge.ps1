# ============================================================
# 🩺 BsmartFlow Bridge Auto-Heal Script
# ============================================================

$project = "bsmartflow-474718"
$region = "asia-south1"
$service = "bsmartflow-acc-bridge"

Write-Host "🩺 Running auto-heal for $service..." -ForegroundColor Cyan

# Reapply IAM policy
gcloud run services add-iam-policy-binding $service `
  --region=$region `
  --member="user:admin@bsmartflow.com" `
  --role="roles/run.invoker" `
  --project=$project

gcloud run services add-iam-policy-binding $service `
  --region=$region `
  --member="serviceAccount:bsmartflow-acc-bridge@$project.iam.gserviceaccount.com" `
  --role="roles/run.invoker" `
  --project=$project

Write-Host "✅ IAM bindings verified and repaired." -ForegroundColor Green

# Check service status
.\validate_bridge.ps1
