#!/bin/bash
set -e

# =========================
# Variables
# =========================
BUCKET_NAME="m3ap-remote-state-1" # Change this to a globally unique name
AWS_REGION="eu-west-2"
AWS_PROFILE="my_account"

echo "Creating Terraform state bucket: $BUCKET_NAME in region: $AWS_REGION (profile: $AWS_PROFILE)"

# =========================
# Create S3 bucket
# =========================
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"

# =========================
# Enable versioning
# =========================
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --versioning-configuration Status=Enabled

echo "Versioning enabled"

# =========================
# Run Terraform workflow
# =========================
cd vault-jenkins 

terraform init 

terraform fmt --recursive
terraform apply -auto-approve

echo "Terraform state bucket configured and Terraform applied successfully!"