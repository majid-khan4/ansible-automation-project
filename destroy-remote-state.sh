#!/bin/bash
set -e

# =========================
# Variables
# =========================
BUCKET_NAME="m3ap-remote-state-1"   # Must match the created bucket
AWS_REGION="eu-west-2"
AWS_PROFILE="my_account"

echo "🧹 Destroying Terraform state bucket: $BUCKET_NAME in region: $AWS_REGION (profile: $AWS_PROFILE)"

# =========================
# Empty the S3 bucket (including all versions and delete markers)
# =========================
echo "🧺 Deleting all objects, versions, and delete markers in the bucket..."

aws s3api delete-objects \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --delete "$(aws s3api list-object-versions \
    --bucket "$BUCKET_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --output json \
    --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
  || echo "No versioned objects to delete."

aws s3api delete-objects \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --delete "$(aws s3api list-object-versions \
    --bucket "$BUCKET_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --output json \
    --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" \
  || echo "No delete markers to remove."

# =========================
# Delete the S3 bucket itself
# =========================
echo "🪣 Deleting the S3 bucket..."
aws s3api delete-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"

echo "✅ Successfully deleted bucket: $BUCKET_NAME"
