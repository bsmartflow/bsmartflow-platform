

# ================================================================
# 🚀 BsmartFlow ACC Bridge - PowerShell Deployment Script (v3)
# ================================================================
# Author: Bhavani Prasad
# Description: Full build + deploy + IAM fix + health check automation
# ================================================================

$ErrorActionPreference = "Stop"
$project = "bsmartflow-474718"
$region = "asia-south1"
$service = "bsmartflow-acc-bridge"
$repo = "bsmartflow-repo"
$image = "asia-south1-docker.pkg.dev/$project/$repo/$service"

Write-Host "`n🚀 Starting Bridge Deployment..." -ForegroundColor Cyan

# ================================================================
# 🧱 STEP 1: Build container & push to Artifact Registry
# ================================================================
Write-Host "🛠️ Building and pushing container to Artifact Registry..." -ForegroundColor Yellow
gcloud builds submit --tag $image --project=$project

Write-Host "`n✅ Build complete. Image pushed successfully!" -ForegroundColor Green

# ================================================================
# ☁️ STEP 2: Deploy to Cloud Run
# ================================================================
Write-Host "`n🚀 Deploying Bridge service to Cloud Run..." -ForegroundColor Yellow

gcloud run deploy $service `
  --image=$image `
  --region=$region `
  --project=$project `
  --memory=1Gi `
  --timeout=900s `
  --ingress=all `
  --service-account="bsmartflow-acc-bridge@$project.iam.gserviceaccount.com" `
  --allow-unauthenticated `
  --quiet

Write-Host "`n✅ Deployment complete!" -ForegroundColor Green

# ================================================================
# 🛡️ STEP 3: Reapply IAM permissions (auto-fix)
# ================================================================
Write-Host "`n🔐 Reapplying IAM roles for Bridge access..." -ForegroundColor Yellow
gcloud run services add-iam-policy-binding $service `
  --region=$region `
  --member="allUsers" `
  --role="roles/run.invoker" `
  --project=$project

gcloud run services add-iam-policy-binding $service `
  --region=$region `
  --member="serviceAccount:bsmartflow-acc-bridge@$project.iam.gserviceaccount.com" `
  --role="roles/run.invoker" `
  --project=$project

Write-Host "✅ IAM bindings repaired and verified." -ForegroundColor Green

# ================================================================
# 🧪 STEP 4: Health Check
# ================================================================
Write-Host "`n🩺 Running health validation..." -ForegroundColor Cyan
.\validate_bridge.ps1

Write-Host "`n🎯 Bridge deployment completed successfully!" -ForegroundColor Green









