@echo off
echo ======================================================
echo BsmartFlow Cloud Run Public Access Configuration
echo ======================================================
echo Project: bsmartflow-474718
echo Region: asia-south1
echo ------------------------------------------------------

set PROJECT=bsmartflow-474718
set REGION=asia-south1

echo Updating: bsmartflow-acc
gcloud run services update bsmartflow-acc --region=%REGION% --project=%PROJECT% --ingress=all --quiet
gcloud run services add-iam-policy-binding bsmartflow-acc --region=%REGION% --project=%PROJECT% --member="allUsers" --role="roles/run.invoker" --quiet

echo Updating: bsmartflow-acc-bridge
gcloud run services update bsmartflow-acc-bridge --region=%REGION% --project=%PROJECT% --ingress=all --quiet
gcloud run services add-iam-policy-binding bsmartflow-acc-bridge --region=%REGION% --project=%PROJECT% --member="allUsers" --role="roles/run.invoker" --quiet

echo Updating: bsmartflow-acc-builder
gcloud run services update bsmartflow-acc-builder --region=%REGION% --project=%PROJECT% --ingress=all --quiet
gcloud run services add-iam-policy-binding bsmartflow-acc-builder --region=%REGION% --project=%PROJECT% --member="allUsers" --role="roles/run.invoker" --quiet

echo Updating: bsmartflow-acc-intelligence
gcloud run services update bsmartflow-acc-intelligence --region=%REGION% --project=%PROJECT% --ingress=all --quiet
gcloud run services add-iam-policy-binding bsmartflow-acc-intelligence --region=%REGION% --project=%PROJECT% --member="allUsers" --role="roles/run.invoker" --quiet

echo Updating: bsmartflow-acc-ui
gcloud run
